#!/bin/sh
set -eu

PREFIX="10.65"
NODE="$(hostname)"
ACTION="${1:-setup}"
TARGET="${2:-nginx}"
REQUESTS="${2:-40}"

DOMAIN="jujutsu.k03.com"
GOJO_IP="${PREFIX}.1.4"
NANAMI_IP="${PREFIX}.4.5"
TODO_IP="${PREFIX}.4.6"
KIRARA_IP="${PREFIX}.4.7"
NANAMI_WEIGHT=3
TODO_WEIGHT=1
MAX_FAILS=2
FAIL_TIMEOUT="5s"

UPSTREAM_CONF="/etc/nginx/conf.d/geto-upstream.conf"
FAILOVER_SNIPPET="/etc/nginx/snippets/geto-failover.conf"

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

check_backends() {
    for entry in "nanami:${NANAMI_IP}" "todo:${TODO_IP}" "kirara:${KIRARA_IP}"; do
        name="${entry%%:*}"
        ip="${entry#*:}"
        code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' -H "Host: ${DOMAIN}" "http://${ip}/api" || true)"
        log "backend ${name} (${ip}) /api: HTTP ${code:-000}"
    done
}

setup_geto() {
    [ "$NODE" = "geto" ] || die "setup hanya dijalankan di geto"
    [ -d /etc/nginx/snippets ] || die "jalankan soal-15.sh di geto terlebih dahulu"

    cat > "$UPSTREAM_CONF" <<EOF
upstream api_cluster {
    zone api_cluster 64k;
    server ${NANAMI_IP} weight=${NANAMI_WEIGHT} max_fails=${MAX_FAILS} fail_timeout=${FAIL_TIMEOUT};
    server ${TODO_IP} weight=${TODO_WEIGHT} max_fails=${MAX_FAILS} fail_timeout=${FAIL_TIMEOUT};
    server ${KIRARA_IP} backup;
}
EOF

    cat > "$FAILOVER_SNIPPET" <<'EOF'
proxy_connect_timeout 2s;
proxy_next_upstream error timeout http_502 http_503 http_504;
proxy_next_upstream_tries 3;
EOF

    reload_nginx
    log "kirara menjadi backup, max_fails=${MAX_FAILS} fail_timeout=${FAIL_TIMEOUT}"
    check_backends
}

service_name() {
    case "$1" in
        nginx)
            printf 'nginx'
            ;;
        php)
            version="$(ls /etc/php | sort -V | tail -n 1)"
            [ -n "$version" ] || die "versi php tidak terdeteksi"
            printf 'php%s-fpm' "$version"
            ;;
        *)
            die "layanan harus nginx atau php"
            ;;
    esac
}

require_worker() {
    case "$NODE" in
        nanami|todo|kirara) ;;
        *) die "perintah ini dijalankan di nanami, todo, atau kirara" ;;
    esac
}

stop_worker() {
    require_worker
    svc="$(service_name "$TARGET")"
    service "$svc" stop >/dev/null 2>&1 || die "gagal menghentikan ${svc}"
    log "layanan ${svc} dihentikan"
}

start_worker() {
    require_worker
    svc="$(service_name "$TARGET")"
    service "$svc" start >/dev/null 2>&1 || die "gagal menjalankan ${svc}"
    log "layanan ${svc} dijalankan"
}

verify_failover() {
    case "$REQUESTS" in
        ''|*[!0-9]*) die "jumlah request harus berupa angka" ;;
    esac

    tmp="$(mktemp)"
    log "${REQUESTS} request ke http://${DOMAIN}/api"
    results="$(
        i=1
        while [ "$i" -le "$REQUESTS" ]; do
            code="$(curl -s -o "$tmp" -m 10 -w '%{http_code}' --resolve "${DOMAIN}:80:${GOJO_IP}" "http://${DOMAIN}/api" || true)"
            worker="$(sed -n 's/.*"worker":"\([^"]*\)".*/\1/p' "$tmp")"
            printf '%s %s\n' "${code:-000}" "${worker:-none}"
            i=$((i + 1))
        done | sort | uniq -c
    )"
    rm -f "$tmp"

    printf '%s\n' "$results"
    bad="$(printf '%s\n' "$results" | awk '$2 == "502" { sum += $1 } END { print sum + 0 }')"
    log "jumlah respons 502: ${bad}"
}

case "$ACTION" in
    setup)
        require_root
        setup_geto
        ;;
    stop)
        require_root
        stop_worker
        ;;
    start)
        require_root
        start_worker
        ;;
    verify)
        verify_failover
        ;;
    *)
        die "penggunaan: soal-18.sh [setup|stop [nginx|php]|start [nginx|php]|verify [jumlah_request]]"
        ;;
esac