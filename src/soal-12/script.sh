#!/bin/sh

# ============================================================
# K-03 - SOAL 12: A Record, CNAME www, Reverse DNS (PTR), & DNS Forwarder
# ============================================================

NODE="$(hostname)"
PREFIX="10.65"
DOMAIN="jujutsu.k03.com"
MASTER_IP="${PREFIX}.1.2"
SLAVE_IP="${PREFIX}.1.3"
GOJO_IP="${PREFIX}.1.4"
REV_ZONE="1.65.10.in-addr.arpa"
EXT_DNS="192.168.122.1"
SERIAL="2026101403"

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
echo " K-03 - SOAL 12: Pemetaan Domain, CNAME, PTR Reverse DNS, & Forwarder"
echo " Node terdeteksi : $NODE"
echo " Domain Target   : $DOMAIN"
echo " IP Gojo Proxy   : $GOJO_IP"
garis
echo ""

# ============================================================
# NODE: UTAHIME (DNS MASTER)
# ============================================================
if [ "$NODE" = "utahime" ]; then
    echo "STEP 1/5 - Memperbarui Forward Zone /etc/bind/jujutsu/$DOMAIN..."
    cat > /etc/bind/jujutsu/$DOMAIN <<EOF
\$TTL 86400
@   IN  SOA utahime.$DOMAIN. hostmaster.$DOMAIN. (
        $SERIAL ; Serial dinaikkan
        3600
        1800
        604800
        86400 )

@       IN  NS      utahime.$DOMAIN.
@       IN  NS      shoko.$DOMAIN.

utahime IN  A       $MASTER_IP
shoko   IN  A       $SLAVE_IP

; Pemetaan A Record Gojo
@       IN  A       $GOJO_IP
gojo    IN  A       $GOJO_IP

; CNAME www merujuk ke domain utama
www     IN  CNAME   $DOMAIN.
EOF
    ok "Forward Zone file diperbarui dengan A record gojo ($GOJO_IP) dan CNAME www."

    echo ""
    echo "STEP 2/5 - Mengonfigurasi Reverse DNS (PTR) di /etc/bind/named.conf.local..."
    cat > /etc/bind/named.conf.local <<EOF
zone "$DOMAIN" {
    type master;
    file "/etc/bind/jujutsu/$DOMAIN";
    notify yes;
    also-notify { $SLAVE_IP; };
    allow-transfer { $SLAVE_IP; };
};

zone "$REV_ZONE" {
    type master;
    file "/etc/bind/jujutsu/$REV_ZONE";
    notify yes;
    also-notify { $SLAVE_IP; };
    allow-transfer { $SLAVE_IP; };
};
EOF
    ok "Zona PTR $REV_ZONE dideklarasikan di named.conf.local."

    echo ""
    echo "STEP 3/5 - Membuat file zona Reverse DNS /etc/bind/jujutsu/$REV_ZONE..."
    cat > /etc/bind/jujutsu/$REV_ZONE <<EOF
\$TTL 86400
@   IN  SOA utahime.$DOMAIN. hostmaster.$DOMAIN. (
        $SERIAL
        3600
        1800
        604800
        86400 )

@       IN  NS      utahime.$DOMAIN.
@       IN  NS      shoko.$DOMAIN.

; Reverse DNS record untuk melacak IP gojo (10.65.1.4) ke domain resminya
4       IN  PTR     $DOMAIN.
EOF
    ok "File Reverse Zone $REV_ZONE berhasil dibuat."

    echo ""
    echo "STEP 4/5 - Mengaktifkan fitur DNS Forwarder ke IP gateway internet ($EXT_DNS)..."
    cat > /etc/bind/named.conf.options <<EOF
options {
    directory "/var/cache/bind";

    forwarders {
        $EXT_DNS;
    };

    allow-query { any; };
    recursion yes;
    dnssec-validation no;

    listen-on { any; };
    listen-on-v6 { none; };
};
EOF
    ok "DNS Forwarders ke $EXT_DNS dikonfigurasi di named.conf.options."

    echo ""
    echo "STEP 5/5 - Validasi & restart BIND9..."
    named-checkconf || fail "Sintaks named.conf tidak valid!"
    named-checkzone "$DOMAIN" "/etc/bind/jujutsu/$DOMAIN" || fail "Forward zone error!"
    named-checkzone "$REV_ZONE" "/etc/bind/jujutsu/$REV_ZONE" || fail "Reverse zone error!"

    service bind9 restart
    sleep 2
    service bind9 status >/dev/null 2>&1 || fail "bind9 tidak aktif!"
    ok "DNS Master utahime BERHASIL dimutakhirkan!"
    garis
    exit 0
fi

# ============================================================
# NODE: SHOKO (DNS SLAVE UPDATE)
# ============================================================
if [ "$NODE" = "shoko" ]; then
    echo "Memperbarui konfigurasi slave pada shoko..."
    cat > /etc/bind/named.conf.local <<EOF
zone "$DOMAIN" {
    type slave;
    file "/var/cache/bind/db.$DOMAIN";
    masters { $MASTER_IP; };
};

zone "$REV_ZONE" {
    type slave;
    file "/var/cache/bind/db.$REV_ZONE";
    masters { $MASTER_IP; };
};
EOF

    cat > /etc/bind/named.conf.options <<EOF
options {
    directory "/var/cache/bind";
    forwarders {
        $EXT_DNS;
    };
    allow-query { any; };
    recursion yes;
    dnssec-validation no;
    listen-on { any; };
    listen-on-v6 { none; };
};
EOF

    service bind9 restart
    sleep 2
    ok "DNS Slave shoko diperbarui untuk melayani forward zone, reverse zone, dan forwarders!"
    exit 0
fi

# ============================================================
# NODE: CLIENT (PENGUJIAN LENGKAP RESOLUSI & INTERNET)
# ============================================================
echo "Menguji pemetaan domain dari client $NODE..."
echo ""

echo "1. Cek A record $DOMAIN:"
dig @$MASTER_IP $DOMAIN A +short
echo ""

echo "2. Cek CNAME www.$DOMAIN:"
dig @$MASTER_IP www.$DOMAIN CNAME +noall +answer
echo ""

echo "3. Cek Reverse DNS (PTR) untuk IP Gojo ($GOJO_IP):"
dig @$MASTER_IP -x $GOJO_IP +short
echo ""

echo "4. Cek Resolusi Domain Internet Eksternal (DNS Forwarder ke google.com):"
dig @$MASTER_IP google.com A +short
echo ""

echo "5. Menguji Ping ke google.com:"
if ping -c 3 google.com >/dev/null 2>&1; then
    ok "SUKSES! Client dapat melakukan ping ke google.com melalui DNS Forwarder & Gateway!"
else
    fail "Ping ke google.com gagal. Periksa koneksi NAT internet di jichi."
fi

garis
ok "Pengujian Soal 12 SELESAI SEMPURNA!"
exit 0
