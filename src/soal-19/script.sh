#!/bin/sh
set -eu

PREFIX="10.65"
NODE="$(hostname)"
ACTION="${1:-setup}"
BURST_REQUESTS="${2:-30}"

DOMAIN="jujutsu.k03.com"
GOJO_IP="${PREFIX}.1.4"

ZONES_CONF="/etc/nginx/conf.d/gojo-zones.conf"
WEB_SNIPPET="/etc/nginx/snippets/gojo-web.conf"
API_SNIPPET="/etc/nginx/snippets/gojo-api.conf"
CACHE_DIR="/var/cache/nginx/gojo"

log() {
    printf '[%s] %s\n' "$NODE" "$1"
}

die() {
    printf '[%s] ERROR: %s\n' "$NODE" "$1" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "script harus dijalankan sebagai root"
}

reload_nginx() {
    nginx -t >/dev/null 2>&1 || { nginx -t; die "konfigurasi nginx tidak valid"; }
    nginx -s reload || die "nginx gagal direload"
}

setup_gojo() {
    [ "$NODE" = "gojo" ] || die "setup hanya dijalankan di gojo"
    [ -d /etc/nginx/snippets ] || die "jalankan soal-16.sh di gojo terlebih dahulu"

    mkdir -p "$CACHE_DIR"

    cat > "$ZONES_CONF" <<'EOF'
proxy_cache_path /var/cache/nginx/gojo levels=1:2 keys_zone=web_cache:10m max_size=100m inactive=10m use_temp_path=off;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
EOF

    cat > "$WEB_SNIPPET" <<'EOF'
proxy_cache web_cache;
proxy_cache_key $scheme$host$request_uri;
proxy_cache_valid 200 10m;
add_header X-Cache-Status $upstream_cache_status always;
EOF

    cat > "$API_SNIPPET" <<'EOF'
limit_req zone=api_limit burst=5 nodelay;
limit_req_status 429;
EOF

    rm -f "${API_SNIPPET}.bak"
    reload_nginx
    log "cache web 10 menit dan rate limit /api 10 r/s per IP aktif"
}

verify_cache() {
    url="http://${DOMAIN}/?cache_test=$(date +%s)"
    n=1
    while [ "$n" -le 3 ]; do
        status="$(curl -s -D - -o /dev/null -m 5 --resolve "${DOMAIN}:80:${GOJO_IP}" "$url" \
            | tr -d '\r' \
            | awk -F': ' 'tolower($1) == "x-cache-status" { print $2 }')"
        log "request ${n} ke ${url}: X-Cache-Status ${status:-tidak ada}"
        n=$((n + 1))
    done
}

verify_limit() {
    case "$BURST_REQUESTS" in
        ''|*[!0-9]*) die "jumlah request harus berupa angka" ;;
    esac

    log "${BURST_REQUESTS} request bersamaan ke http://${DOMAIN}/api"
    results="$(
        i=1
        while [ "$i" -le "$BURST_REQUESTS" ]; do
            curl -s -o /dev/null -m 10 -w '%{http_code}\n' --resolve "${DOMAIN}:80:${GOJO_IP}" "http://${DOMAIN}/api" &
            i=$((i + 1))
        done
        wait
    )"
    printf '%s\n' "$results" | sort | uniq -c
}

case "$ACTION" in
    setup)
        require_root
        setup_gojo
        ;;
    cache)
        verify_cache
        ;;
    limit)
        verify_limit
        ;;
    *)
        die "penggunaan: soal-19.sh [setup|cache|limit [jumlah_request]]"
        ;;
esac