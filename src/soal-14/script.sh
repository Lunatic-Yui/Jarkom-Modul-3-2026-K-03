#!/bin/sh
set -eu

PREFIX="10.65"
NODE="$(hostname)"
ACTION="${1:-setup}"

DOMAIN="jujutsu.k03.com"
GOJO_IP="${PREFIX}.1.4"
GETO_IP="${PREFIX}.4.2"

DB_HOST="${PREFIX}.4.8"
DB_NAME="db_shibuya_k03"
DB_USER="shibuya"
DB_PASS="shibuya_pass"

PACKAGES="nginx php-fpm php-cli php-mysql curl"
SITE_FILE="/etc/nginx/sites-available/jujutsu"
SITE_LINK="/etc/nginx/sites-enabled/jujutsu"
WEB_ROOT="/var/www/jujutsu"
API_ROOT="/var/www/api"
DB_CONF_DIR="/etc/jujutsu"

log() {
    printf '[%s] %s\n' "$NODE" "$1"
}

die() {
    printf '[%s] ERROR: %s\n' "$NODE" "$1" >&2
    exit 1
}

case "$NODE" in
    maki|panda)
        ROLE="web"
        ALLOW_IP="$GOJO_IP"
        ;;
    nanami|todo|kirara)
        ROLE="api"
        ALLOW_IP="$GETO_IP"
        ;;
    *)
        die "node tidak dikenali, jalankan di maki, panda, nanami, todo, atau kirara"
        ;;
esac

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

detect_php() {
    PHP_VER="$(ls /etc/php | sort -V | tail -n 1)"
    [ -n "$PHP_VER" ] || die "versi php tidak terdeteksi"
    PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"
}

write_web_app() {
    mkdir -p "$WEB_ROOT"
    cat > "$WEB_ROOT/index.php" <<'PHP'
<?php
$hostname = gethostname();
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="utf-8">
    <title>Jujutsu High</title>
</head>
<body>
    <h1>Jujutsu High Frontend</h1>
    <p>Served by: <?= htmlspecialchars($hostname, ENT_QUOTES, 'UTF-8') ?></p>
</body>
</html>
PHP
    chown -R www-data:www-data "$WEB_ROOT"
}

write_api_app() {
    mkdir -p "$API_ROOT" "$DB_CONF_DIR"

    cat > "$DB_CONF_DIR/db.php" <<EOF
<?php
return [
    'host' => '${DB_HOST}',
    'name' => '${DB_NAME}',
    'user' => '${DB_USER}',
    'pass' => '${DB_PASS}',
    'trusted_proxies' => ['${GETO_IP}'],
];
EOF
    chown root:www-data "$DB_CONF_DIR/db.php"
    chmod 640 "$DB_CONF_DIR/db.php"

    cat > "$API_ROOT/index.php" <<'PHP'
<?php
header('Content-Type: application/json');

$config = require '/etc/jujutsu/db.php';
$worker = gethostname();
$remote = $_SERVER['REMOTE_ADDR'] ?? '';
$client = $remote;

if (in_array($remote, $config['trusted_proxies'], true)) {
    $candidate = $_SERVER['HTTP_X_REAL_IP'] ?? '';
    if (filter_var($candidate, FILTER_VALIDATE_IP)) {
        $client = $candidate;
    }
}

try {
    $pdo = new PDO(
        sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4', $config['host'], $config['name']),
        $config['user'],
        $config['pass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 3]
    );
    $stmt = $pdo->prepare('INSERT INTO request_logs (worker, method, uri, client_ip) VALUES (?, ?, ?, ?)');
    $stmt->execute([
        $worker,
        substr($_SERVER['REQUEST_METHOD'] ?? 'GET', 0, 10),
        substr($_SERVER['REQUEST_URI'] ?? '/', 0, 255),
        $client,
    ]);
    echo json_encode([
        'status' => 'ok',
        'worker' => $worker,
        'client_ip' => $client,
        'log_id' => (int) $pdo->lastInsertId(),
    ]);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'worker' => $worker,
        'message' => 'database unavailable',
    ]);
}
PHP
    chown -R www-data:www-data "$API_ROOT"
}

write_web_vhost() {
    cat > "$SITE_FILE" <<EOF
server {
    listen 80 default_server;
    server_name ${DOMAIN} www.${DOMAIN};

    allow 127.0.0.1;
    allow ${ALLOW_IP};
    deny all;

    root ${WEB_ROOT};
    index index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }
}
EOF
}

write_api_vhost() {
    cat > "$SITE_FILE" <<EOF
server {
    listen 80 default_server;
    server_name ${DOMAIN} www.${DOMAIN};

    allow 127.0.0.1;
    allow ${ALLOW_IP};
    deny all;

    root ${API_ROOT};

    location ~ ^/api(/|\$) {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME ${API_ROOT}/index.php;
        fastcgi_pass unix:${PHP_SOCK};
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

restart_services() {
    service "php${PHP_VER}-fpm" restart >/dev/null 2>&1 || die "php${PHP_VER}-fpm gagal dijalankan"
    service nginx restart >/dev/null 2>&1 || die "nginx gagal dijalankan"
    tries=0
    until [ -S "$PHP_SOCK" ]; do
        tries=$((tries + 1))
        [ "$tries" -le 15 ] || die "socket ${PHP_SOCK} tidak tersedia"
        sleep 1
    done
}

check_database() {
    [ "$ROLE" = "api" ] || return 0
    if php -r "try { new PDO('mysql:host=${DB_HOST};dbname=${DB_NAME}', '${DB_USER}', '${DB_PASS}', [PDO::ATTR_TIMEOUT => 3]); } catch (Exception \$e) { exit(1); }"; then
        log "koneksi ke database ${DB_HOST} berhasil"
    else
        log "peringatan: database ${DB_HOST} belum dapat dihubungi"
    fi
}

setup_node() {
    install_packages
    detect_php
    if [ "$ROLE" = "web" ]; then
        write_web_app
        write_web_vhost
    else
        write_api_app
        write_api_vhost
    fi
    enable_site
    restart_services
    check_database
    log "worker ${ROLE} siap, hanya menerima trafik dari ${ALLOW_IP}"
}

verify_node() {
    own_ip="$(ip -4 -o addr show dev eth0 | awk '{print $4}' | cut -d/ -f1 | head -n 1)"
    path="/"
    [ "$ROLE" = "api" ] && path="/api"

    local_code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${DOMAIN}" "http://127.0.0.1${path}")"
    direct_code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${DOMAIN}" "http://${own_ip}${path}")"

    log "akses lokal 127.0.0.1${path}: HTTP ${local_code}"
    log "akses langsung via ${own_ip}${path}: HTTP ${direct_code}"
    curl -s -H "Host: ${DOMAIN}" "http://127.0.0.1${path}"
    printf '\n'
}

require_root

case "$ACTION" in
    setup)
        setup_node
        ;;
    verify)
        verify_node
        ;;
    *)
        die "penggunaan: script.sh [setup|verify]"
        ;;
esac