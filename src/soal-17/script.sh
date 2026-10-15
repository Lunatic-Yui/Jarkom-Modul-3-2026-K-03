#!/bin/sh
set -eu

PREFIX="10.65"
NODE="$(hostname)"
ACTION="${1:-setup}"

DOMAIN="jujutsu.k03.com"
GOJO_IP="${PREFIX}.1.4"
GETO_IP="${PREFIX}.4.2"
DB_NAME="db_shibuya_k03"
SPOOF_IP="9.9.9.9"

GOJO_PROXY_SNIPPET="/etc/nginx/snippets/gojo-proxy.conf"
GETO_PROXY_SNIPPET="/etc/nginx/snippets/geto-proxy.conf"
GETO_REALIP_CONF="/etc/nginx/conf.d/geto-realip.conf"

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

own_ip() {
    ip -4 -o addr show dev eth0 | awk '{print $4}' | cut -d/ -f1 | head -n 1
}

setup_gojo() {
    [ -d /etc/nginx/snippets ] || die "jalankan soal-16.sh di gojo terlebih dahulu"
    cat > "$GOJO_PROXY_SNIPPET" <<'EOF'
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
EOF
    reload_nginx
    log "gojo meneruskan X-Real-IP dan X-Forwarded-For"
}

setup_geto() {
    [ -d /etc/nginx/snippets ] || die "jalankan soal-15.sh di geto terlebih dahulu"

    cat > "$GETO_REALIP_CONF" <<EOF
set_real_ip_from ${GOJO_IP};
real_ip_header X-Forwarded-For;
real_ip_recursive on;

map \$http_x_forwarded_for \$geto_forwarded_for {
    default "\$http_x_forwarded_for, \$realip_remote_addr";
    "" \$realip_remote_addr;
}
EOF

    cat > "$GETO_PROXY_SNIPPET" <<'EOF'
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $geto_forwarded_for;
EOF
    reload_nginx
    log "geto hanya mempercayai alamat client dari proxy ${GOJO_IP}"
}

extract_ip() {
    printf '%s' "$1" | sed -n 's/.*"client_ip":"\([^"]*\)".*/\1/p'
}

report_match() {
    recorded="$(extract_ip "$3")"
    if [ "$recorded" = "$2" ]; then
        verdict="sesuai"
    else
        verdict="TIDAK SESUAI"
    fi
    log "$1: ip_client=$2 tercatat=${recorded:-kosong} (${verdict})"
}

verify_client() {
    own="$(own_ip)"
    plain="$(curl -s -m 5 --resolve "${DOMAIN}:80:${GOJO_IP}" "http://${DOMAIN}/api")"
    spoofed="$(curl -s -m 5 --resolve "${DOMAIN}:80:${GOJO_IP}" \
        -H "X-Forwarded-For: ${SPOOF_IP}" -H "X-Real-IP: ${SPOOF_IP}" \
        "http://${DOMAIN}/api")"
    report_match "request normal via gojo" "$own" "$plain"
    report_match "request dengan header palsu via gojo" "$own" "$spoofed"
}

verify_spoof() {
    own="$(own_ip)"
    response="$(curl -s -m 5 -H "Host: ${DOMAIN}" \
        -H "X-Forwarded-For: ${SPOOF_IP}" -H "X-Real-IP: ${SPOOF_IP}" \
        "http://${GETO_IP}/api")"
    report_match "akses langsung ke geto dengan header palsu" "$own" "$response"
}

show_db() {
    mariadb -e "SELECT id, worker, method, uri, client_ip, created_at FROM ${DB_NAME}.request_logs ORDER BY id DESC LIMIT 10"
}

case "$ACTION" in
    setup)
        require_root
        case "$NODE" in
            gojo) setup_gojo ;;
            geto) setup_geto ;;
            *) die "setup dijalankan di gojo dan geto" ;;
        esac
        ;;
    verify)
        verify_client
        ;;
    spoof)
        verify_spoof
        ;;
    db)
        show_db
        ;;
    *)
        die "penggunaan: soal-17.sh [setup|verify|spoof|db]"
        ;;
esac