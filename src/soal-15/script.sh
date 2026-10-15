#!/bin/sh
set -eu

PREFIX="10.65"
NODE="$(hostname)"
ACTION="${1:-setup}"
REQUESTS="${2:-40}"

DOMAIN="jujutsu.k03.com"
GOJO_IP="${PREFIX}.1.4"
GETO_IP="${PREFIX}.4.2"
NANAMI_IP="${PREFIX}.4.5"
TODO_IP="${PREFIX}.4.6"
NANAMI_WEIGHT=3
TODO_WEIGHT=1

SITE_FILE="/etc/nginx/sites-available/api-lb"
SITE_LINK="/etc/nginx/sites-enabled/api-lb"
UPSTREAM_CONF="/etc/nginx/conf.d/geto-upstream.conf"
ACCESS_CONF="/etc/nginx/conf.d/geto-access.conf"
PROXY_SNIPPET="/etc/nginx/snippets/geto-proxy.conf"
FAILOVER_SNIPPET="/etc/nginx/snippets/geto-failover.conf"
PACKAGES="nginx curl"

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

write_upstream() {
    cat > "$UPSTREAM_CONF" <<EOF
upstream api_cluster {
    zone api_cluster 64k;
    server ${NANAMI_IP} weight=${NANAMI_WEIGHT};
    server ${TODO_IP} weight=${TODO_WEIGHT};
}
EOF
}

write_access() {
    cat > "$ACCESS_CONF" <<EOF
geo \$realip_remote_addr \$geto_peer_allowed {
    default 0;
    127.0.0.1 1;
    ${GOJO_IP} 1;
    ${PREFIX}.4.0/24 1;
}
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
    [ -f "$FAILOVER_SNIPPET" ] || : > "$FAILOVER_SNIPPET"
}

write_vhost() {
    cat > "$SITE_FILE" <<EOF
server {
    listen 80 default_server;
    server_name ${DOMAIN} www.${DOMAIN};

    if (\$geto_peer_allowed = 0) {
        return 403;
    }

    location /api {
        proxy_pass http://api_cluster;
        include snippets/geto-proxy.conf;
        include snippets/geto-failover.conf;
    }

    location / {
        return 404;
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

setup_geto() {
    [ "$NODE" = "geto" ] || die "setup hanya dijalankan di geto"
    install_packages
    write_upstream
    write_access
    write_snippets
    write_vhost
    enable_site
    restart_nginx
    log "load balancer api_cluster aktif (${NANAMI_IP}:${NANAMI_WEIGHT}, ${TODO_IP}:${TODO_WEIGHT})"
}

count_worker() {
    printf '%s\n' "$1" | awk -v w="$2" '$2 == w { print $1 }'
}

verify_balance() {
    case "$REQUESTS" in
        ''|*[!0-9]*) die "jumlah request harus berupa angka" ;;
    esac

    log "mengirim ${REQUESTS} request ke http://${GETO_IP}/api"
    results="$(
        i=1
        while [ "$i" -le "$REQUESTS" ]; do
            worker="$(curl -s -m 5 "http://${GETO_IP}/api" | sed -n 's/.*"worker":"\([^"]*\)".*/\1/p')"
            printf '%s\n' "${worker:-error}"
            i=$((i + 1))
        done | sort | uniq -c
    )"

    printf '%s\n' "$results"

    nanami="$(count_worker "$results" nanami)"
    todo="$(count_worker "$results" todo)"
    nanami="${nanami:-0}"
    todo="${todo:-0}"

    if [ "$todo" -gt 0 ]; then
        ratio="$(awk -v n="$nanami" -v t="$todo" 'BEGIN { printf "%.2f", n / t }')"
    else
        ratio="n/a"
    fi
    log "nanami=${nanami} todo=${todo} rasio=${ratio} (target ${NANAMI_WEIGHT}:${TODO_WEIGHT})"
}

case "$ACTION" in
    setup)
        require_root
        setup_geto
        ;;
    verify)
        verify_balance
        ;;
    *)
        die "penggunaan: soal-15.sh [setup|verify [jumlah_request]]"
        ;;
esac