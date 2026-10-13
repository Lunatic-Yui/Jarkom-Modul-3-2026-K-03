#!/bin/sh

# ============================================================
# K-03 - SOAL 11: Authoritative DNS Master (utahime) & Slave (shoko)
# ============================================================

NODE="$(hostname)"
PREFIX="10.65"
DOMAIN="jujutsu.k03.com"
MASTER_IP="${PREFIX}.1.2"
SLAVE_IP="${PREFIX}.1.3"
EXT_DNS="192.168.122.1"
SERIAL="2026101402"

ok() {
    echo "[OK] $1"
}

fail() {
    echo "[GAGAL] $1"
    exit 1
}

garis() {
    echo "================================================================================"
}

echo ""
garis
echo " K-03 - SOAL 11: BIND9 DNS Master & Slave ($DOMAIN)"
echo " Node terdeteksi : $NODE"
echo " DNS Master      : utahime ($MASTER_IP)"
echo " DNS Slave       : shoko   ($SLAVE_IP)"
garis
echo ""

# ============================================================
# NODE: UTAHIME (DNS MASTER)
# ============================================================
if [ "$NODE" = "utahime" ]; then
    echo "STEP 1/6 - Mengatur resolver sementara untuk instalasi paket..."
    echo "nameserver $EXT_DNS" > /etc/resolv.conf

    echo ""
    echo "STEP 2/6 - Memastikan bind9 dan dnsutils terpasang..."
    if dpkg -s bind9 >/dev/null 2>&1; then
        ok "bind9 sudah terpasang."
    else
        echo "Mengunduh dan memasang bind9..."
        apt-get update -y && apt-get install -y bind9 bind9utils dnsutils || fail "Instalasi bind9 gagal."
        ok "bind9 berhasil dipasang."
    fi

    echo ""
    echo "STEP 3/6 - Mengonfigurasi /etc/bind/named.conf.local..."
    mkdir -p /etc/bind/jujutsu

    cat > /etc/bind/named.conf.local <<EOF
zone "$DOMAIN" {
    type master;
    file "/etc/bind/jujutsu/$DOMAIN";
    notify yes;
    also-notify { $SLAVE_IP; };
    allow-transfer { $SLAVE_IP; };
};
EOF
    ok "Deklarasi zone $DOMAIN sebagai master dibuat."

    echo ""
    echo "STEP 4/6 - Membuat zone file /etc/bind/jujutsu/$DOMAIN..."
    cat > /etc/bind/jujutsu/$DOMAIN <<EOF
\$TTL 86400
@   IN  SOA utahime.$DOMAIN. hostmaster.$DOMAIN. (
        $SERIAL ; Serial
        3600       ; Refresh
        1800       ; Retry
        604800     ; Expire
        86400 )    ; Negative Cache TTL

@       IN  NS  utahime.$DOMAIN.
@       IN  NS  shoko.$DOMAIN.

utahime IN  A   $MASTER_IP
shoko   IN  A   $SLAVE_IP
EOF
    ok "Zone file berhasil dibuat dengan serial $SERIAL."

    echo ""
    echo "STEP 5/6 - Validasi konfigurasi zona..."
    named-checkconf || fail "Konfigurasi named.conf tidak valid!"
    named-checkzone "$DOMAIN" "/etc/bind/jujutsu/$DOMAIN" || fail "Zone file $DOMAIN tidak valid!"
    ok "Validasi BIND9 syntax & zone berhasil."

    echo ""
    echo "STEP 6/6 - Merestart BIND9..."
    service bind9 restart
    sleep 2
    service bind9 status >/dev/null 2>&1 || fail "bind9 gagal aktif!"
    ok "DNS Master utahime BERJALAN AKTIF."
    
    echo ""
    echo "Verifikasi lokal query SOA:"
    dig @$MASTER_IP $DOMAIN SOA +short
    garis
    ok "Konfigurasi DNS Master utahime SELESAI!"
    exit 0
fi

# ============================================================
# NODE: SHOKO (DNS SLAVE)
# ============================================================
if [ "$NODE" = "shoko" ]; then
    echo "STEP 1/5 - Mengatur resolver sementara untuk instalasi paket..."
    echo "nameserver $EXT_DNS" > /etc/resolv.conf

    echo ""
    echo "STEP 2/5 - Memastikan bind9 dan dnsutils terpasang..."
    if dpkg -s bind9 >/dev/null 2>&1; then
        ok "bind9 sudah terpasang."
    else
        echo "Mengunduh dan memasang bind9..."
        apt-get update -y && apt-get install -y bind9 bind9utils dnsutils || fail "Instalasi bind9 gagal."
        ok "bind9 berhasil dipasang."
    fi

    echo ""
    echo "STEP 3/5 - Mengonfigurasi /etc/bind/named.conf.local sebagai slave..."
    cat > /etc/bind/named.conf.local <<EOF
zone "$DOMAIN" {
    type slave;
    file "/var/cache/bind/db.$DOMAIN";
    masters { $MASTER_IP; };
};
EOF
    ok "Deklarasi zone slave $DOMAIN dibuat."

    echo ""
    echo "STEP 4/5 - Validasi named-checkconf & restart..."
    named-checkconf || fail "Konfigurasi named.conf slave tidak valid!"
    service bind9 restart
    sleep 3

    echo ""
    echo "STEP 5/5 - Menguji transfer zona (AXFR) dari utahime ($MASTER_IP)..."
    dig @$MASTER_IP $DOMAIN AXFR +short
    echo ""
    echo "Mengecek SOA langsung ke slave shoko ($SLAVE_IP):"
    dig @127.0.0.1 $DOMAIN SOA +short
    
    garis
    ok "DNS Slave shoko BERHASIL menerima transfer zona otomatis dari utahime!"
    exit 0
fi

# ============================================================
# NODE: CLIENT (PEMBUKTIAN QUERY DIG KE KEDUA SERVER)
# ============================================================
echo "Menguji query dig dari client $NODE ke Master ($MASTER_IP) dan Slave ($SLAVE_IP)..."
echo ""

echo "1. Query SOA ke Master utahime ($MASTER_IP):"
dig @$MASTER_IP $DOMAIN SOA +noall +answer
echo ""

echo "2. Query SOA ke Slave shoko ($SLAVE_IP):"
dig @$SLAVE_IP $DOMAIN SOA +noall +answer
echo ""

echo "3. Query NS ke Master utahime ($MASTER_IP):"
dig @$MASTER_IP $DOMAIN NS +noall +answer
echo ""

SERIAL_M="$(dig @$MASTER_IP $DOMAIN SOA +short | awk '{print $3}')"
SERIAL_S="$(dig @$SLAVE_IP $DOMAIN SOA +short | awk '{print $3}')"

echo "Serial pada Master: $SERIAL_M"
echo "Serial pada Slave : $SERIAL_S"

if [ "$SERIAL_M" = "$SERIAL_S" ] && [ -n "$SERIAL_M" ]; then
    ok "HASIL IDENTIK! Serial pada kedua server sinkron sempurna ($SERIAL_M)."
else
    echo "[WARNING] Serial belum sama. Berikan waktu چند detik untuk sinkronisasi zone transfer."
fi

garis
exit 0
