#!/bin/sh
set -eu

PREFIX="10.65"
NODE="$(hostname)"
ACTION="${1:-setup}"

DB_NAME="db_shibuya_k03"
DB_USER="shibuya"
DB_PASS="shibuya_pass"
REPL_USER="repl"
REPL_PASS="repl_pass"

NET4_MASK="${PREFIX}.4.%"
MASTER_IP="${PREFIX}.4.8"
CONF_FILE="/etc/mysql/mariadb.conf.d/99-replication.cnf"
BINLOG_FILE="mysql-bin.000001"

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

install_server() {
    if dpkg -s mariadb-server >/dev/null 2>&1; then
        return 0
    fi
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y mariadb-server mariadb-client >/dev/null || die "instalasi mariadb gagal"
}

write_config() {
    server_id="$1"
    shift
    {
        printf '[mysqld]\n'
        printf 'bind-address = 0.0.0.0\n'
        printf 'server-id = %s\n' "$server_id"
        for line in "$@"; do
            printf '%s\n' "$line"
        done
    } > "$CONF_FILE"
}

restart_server() {
    service mariadb restart >/dev/null 2>&1 || die "mariadb gagal direstart"
    tries=0
    until mariadb-admin ping --silent >/dev/null 2>&1; do
        tries=$((tries + 1))
        [ "$tries" -le 30 ] || die "mariadb tidak merespons"
        sleep 1
    done
}

slave_field() {
    mariadb -e "SHOW SLAVE STATUS\G" | awk -v key="$1:" '$1 == key { print $2 }'
}

setup_master() {
    write_config 1 \
        "log_bin = /var/lib/mysql/mysql-bin" \
        "binlog_format = ROW"
    restart_server

    if ! mariadb -N -e "SHOW DATABASES LIKE '${DB_NAME}'" | grep -q .; then
        mariadb -e "RESET MASTER"
    fi

    mariadb <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE TABLE IF NOT EXISTS ${DB_NAME}.request_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    worker VARCHAR(64) NOT NULL,
    method VARCHAR(10) NOT NULL DEFAULT 'GET',
    uri VARCHAR(255) NOT NULL,
    client_ip VARCHAR(45) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_client_ip (client_ip)
) ENGINE=InnoDB;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${NET4_MASK}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${NET4_MASK}';
CREATE USER IF NOT EXISTS '${REPL_USER}'@'${NET4_MASK}' IDENTIFIED BY '${REPL_PASS}';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '${REPL_USER}'@'${NET4_MASK}';
FLUSH PRIVILEGES;
SQL

    log "database ${DB_NAME} dan tabel request_logs siap"
    mariadb -e "SHOW MASTER STATUS"
}

setup_slave() {
    write_config 2 \
        "relay_log = /var/lib/mysql/relay-bin" \
        "read_only = 1"
    restart_server

    tries=0
    until mariadb -h "$MASTER_IP" -u "$REPL_USER" -p"$REPL_PASS" -e "SELECT 1" >/dev/null 2>&1; do
        tries=$((tries + 1))
        [ "$tries" -le 30 ] || die "master ${MASTER_IP} tidak dapat dihubungi"
        sleep 2
    done

    if [ -z "$(slave_field Master_Host)" ]; then
        mariadb <<SQL
CHANGE MASTER TO
    MASTER_HOST='${MASTER_IP}',
    MASTER_USER='${REPL_USER}',
    MASTER_PASSWORD='${REPL_PASS}',
    MASTER_LOG_FILE='${BINLOG_FILE}',
    MASTER_LOG_POS=4,
    MASTER_CONNECT_RETRY=10;
SQL
    fi
    mariadb -e "START SLAVE"

    tries=0
    until [ "$(slave_field Slave_IO_Running)" = "Yes" ] && [ "$(slave_field Slave_SQL_Running)" = "Yes" ]; do
        tries=$((tries + 1))
        [ "$tries" -le 30 ] || die "replikasi tidak berjalan: $(slave_field Last_IO_Error) $(slave_field Last_SQL_Error)"
        sleep 1
    done

    log "replikasi aktif"
    show_slave_status
}

show_slave_status() {
    mariadb -e "SHOW SLAVE STATUS\G" | awk '/Master_Host:|Slave_IO_Running:|Slave_SQL_Running:|Seconds_Behind_Master:|Last_(IO|SQL)_Error:/'
}

verify_master() {
    mariadb -e "INSERT INTO ${DB_NAME}.request_logs (worker, method, uri, client_ip) VALUES ('${NODE}', 'TEST', '/replication-check', '${MASTER_IP}')"
    log "data uji dimasukkan pada master"
    mariadb -e "SELECT * FROM ${DB_NAME}.request_logs ORDER BY id DESC LIMIT 5"
}

verify_slave() {
    sleep 2
    show_slave_status
    mariadb -e "SELECT * FROM ${DB_NAME}.request_logs ORDER BY id DESC LIMIT 5"
}

require_root

case "${NODE}:${ACTION}" in
    yaga:setup)
        install_server
        setup_master
        ;;
    yaga:verify)
        verify_master
        ;;
    inumaki:setup)
        install_server
        setup_slave
        ;;
    inumaki:verify)
        verify_slave
        ;;
    *)
        die "penggunaan: jalankan di yaga atau inumaki dengan argumen setup|verify"
        ;;
esac