#!/bin/sh
set -eu

PREFIX="10.65"
NODE="$(hostname)"
ACTION="${1:-setup}"
REQUESTS="${2:-40}"

DOMAIN="jujutsu.k03.com"
GOJO_IP="${PREFIX}.1.4"
GETO_IP="${PREFIX}.4.2"
MAKI_IP="${PREFIX}.4.3"
PANDA_IP="${PREFIX}.4.4"

SITE_FILE="/etc/nginx/sites-available/gojo"
SITE_LINK="/etc/nginx/sites-enabled/gojo"
LOG_CONF="/etc/nginx/conf.d/gojo-log.conf"
PROXY_SNIPPET="/etc/nginx/snippets/gojo-proxy.conf"
WEB_SNIPPET="/etc/nginx/snippets/gojo-web.conf"
API_SNIPPET="/etc/nginx/snippets/gojo-api.conf"
ACCESS_LOG="/var/log/nginx/gojo.access.log"
PACKAGES="nginx curl"

WEB_EXPR='s/.*Served by: \([A-Za-z0-9_-]*\).*/\1/p'
API_EXPR='s/.*"worker":"\([^"]*\)".*/\1/p'

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

install_packages() {
    missing=0
    for pkg in $PACKAGES; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing=1
    done
    [ "$missing" -eq 1 ] || return 0
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null || die "apt-get update gagal, periksa resolv.conf"
    apt-get install -y $PACKAGES >/dev/null || die "instalasi paket gagal"
}

write_log_format() {
    cat > "$LOG_CONF" <<'EOF'
log_format gojo_main 'ip=$remote_addr time=$time_iso8601 uri=$request_uri status=$status bytes=$body_bytes_sent rt=$request_time cache=$upstream_cache_status limit=$limit_req_status up="$upstream_status" addr="$upstream_addr"';
EOF
}

write_snippets() {
    if [ ! -f "$PROXY_SNIPPET" ]; then
        cat > "$PROXY_SNIPPET" <<'EOF'
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host $host;
EOF
    fi
    [ -f "$WEB_SNIPPET" ] || : > "$WEB_SNIPPET"
    [ -f "$API_SNIPPET" ] || : > "$API_SNIPPET"
}

write_vhost() {
    cat > "$SITE_FILE" <<EOF
upstream web_cluster {
    zone web_cluster 64k;
    server ${MAKI_IP};
    server ${PANDA_IP};
}

server {
    listen 80 default_server;
    server_name _;
    return 404;
}

server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    access_log ${ACCESS_LOG} gojo_main;

    location ~ ^/api(/|\$) {
        proxy_pass http://${GETO_IP};
        include snippets/gojo-proxy.conf;
        include snippets/gojo-api.conf;
    }

    location / {
        proxy_pass http://web_cluster;
        include snippets/gojo-proxy.conf;
        include snippets/gojo-web.conf;
    }
}
EOF
}

enable_site() {
    rm -f /etc/nginx/sites-enabled/default
    ln -sf "$SITE_FILE" "$SITE_LINK"
    nginx -t >/dev/null 2>&1 || { nginx -t; die "konfigurasi nginx tidak valid"; }
}

restart_nginx() {
    service nginx restart >/dev/null 2>&1 || die "nginx gagal dijalankan"
}

setup_gojo() {
    [ "$NODE" = "gojo" ] || die "setup hanya dijalankan di gojo"
    install_packages
    write_log_format
    write_snippets
    write_vhost
    enable_site
    restart_nginx
    log "gojo aktif: / ke maki dan panda, /api ke geto"
}

sample() {
    path="$1"
    expr="$2"
    i=1
    while [ "$i" -le "$REQUESTS" ]; do
        value="$(curl -s -m 5 --resolve "${DOMAIN}:80:${GOJO_IP}" "http://${DOMAIN}${path}" | sed -n "$expr")"
        printf '%s\n' "${value:-error}"
        i=$((i + 1))
    done | sort | uniq -c
}

verify_routing() {
    case "$REQUESTS" in
        ''|*[!0-9]*) die "jumlah request harus berupa angka" ;;
    esac

    www_code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' --resolve "www.${DOMAIN}:80:${GOJO_IP}" "http://www.${DOMAIN}/")"
    log "www.${DOMAIN}/ : HTTP ${www_code}"

    log "${REQUESTS} request ke http://${DOMAIN}/ (diharapkan dijawab maki dan panda)"
    sample "/" "$WEB_EXPR"

    log "${REQUESTS} request ke http://${DOMAIN}/api (diharapkan dijawab nanami dan todo)"
    sample "/api" "$API_EXPR"
}

case "$ACTION" in
    setup)
        require_root
        setup_gojo
        ;;
    verify)
        verify_routing
        ;;
    *)
        die "penggunaan: soal-16.sh [setup|verify [jumlah_request]]"
        ;;
esac