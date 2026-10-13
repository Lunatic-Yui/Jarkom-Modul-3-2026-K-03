#!/bin/sh

# ============================================================
# K-03 - SOAL 2: Konfigurasi DHCP Server Tengen di Data Center
# ============================================================

NODE="$(hostname)"
PREFIX="10.65"
EXT_DNS="192.168.122.1"

ok() {
    echo "[OK] $1"
}

fail() {
    echo "[GAGAL] $1"
    exit 1
}

garis() {
    echo "============================================================"
}

echo ""
garis
echo " K-03 - SOAL 2: DHCP Server Tengen"
echo " Node terdeteksi : $NODE"
echo " Prefix Kelompok : $PREFIX"
garis
echo ""

if [ "$NODE" != "tengen" ]; then
    echo "[INFO] Script ini dijalankan pada node 'tengen' (DHCP Server)."
    echo "Jika ingin menguji pada node ini, pastikan node ini adalah tengen."
    exit 0
fi

echo "STEP 1/5 - Memastikan konektivitas dan resolver sementara..."
echo "nameserver $EXT_DNS" > /etc/resolv.conf

if ping -c 2 ${PREFIX}.4.1 >/dev/null 2>&1; then
    ok "Koneksi ke gateway ${PREFIX}.4.1 terhubung."
else
    echo "[WARNING] Gateway ${PREFIX}.4.1 belum merespons. Melanjutkan konfigurasi..."
fi

echo ""
echo "STEP 2/5 - Memastikan paket isc-dhcp-server terpasang..."
if dpkg -s isc-dhcp-server >/dev/null 2>&1; then
    ok "Paket isc-dhcp-server sudah terpasang."
else
    echo "Mengunduh dan memasang isc-dhcp-server..."
    apt-get update -y && apt-get install -y isc-dhcp-server || fail "Instalasi isc-dhcp-server gagal."
    ok "isc-dhcp-server berhasil dipasang."
fi

echo ""
echo "STEP 3/5 - Mengonfigurasi antarmuka layanan di /etc/default/isc-dhcp-server..."
cat > /etc/default/isc-dhcp-server <<EOF
INTERFACESv4="eth0"
INTERFACESv6=""
EOF
ok "Interface eth0 ditetapkan untuk isc-dhcp-server."

echo ""
echo "STEP 4/5 - Menyusun /etc/dhcp/dhcpd.conf..."
cat > /etc/dhcp/dhcpd.conf <<EOF
# dhcpd.conf - Shibuya Incident K-03
default-lease-time 1800;
max-lease-time 43200;
authoritative;

# Network 4 - Subnet Lokal Data Center (TIDAK ADA dynamic pool)
# Deklarasi ini wajib agar dhcpd tidak memunculkan error 'No subnet declaration'
subnet ${PREFIX}.4.0 netmask 255.255.255.0 {
}

# Network 2 - Divisi A (Scope DHCP awal)
subnet ${PREFIX}.2.0 netmask 255.255.255.0 {
    option routers ${PREFIX}.2.1;
    option broadcast-address ${PREFIX}.2.255;
    option domain-name-servers ${PREFIX}.1.2, ${PREFIX}.1.3;
    option domain-search "k03.com";
}

# Network 3 - Divisi B (Scope DHCP awal)
subnet ${PREFIX}.3.0 netmask 255.255.255.0 {
    option routers ${PREFIX}.3.1;
    option broadcast-address ${PREFIX}.3.255;
    option domain-name-servers ${PREFIX}.1.2, ${PREFIX}.1.3;
    option domain-search "k03.com";
}
EOF
ok "File /etc/dhcp/dhcpd.conf berhasil ditulis."

echo ""
echo "STEP 5/5 - Validasi konfigurasi & Start layanan..."
echo "Menjalankan syntax check: dhcpd -t -cf /etc/dhcp/dhcpd.conf"
dhcpd -t -cf /etc/dhcp/dhcpd.conf || fail "Validasi sintaks dhcpd.conf gagal!"
ok "Sintaks konfigurasi valid (Syntax test succeeded)."

service isc-dhcp-server restart
sleep 2

if service isc-dhcp-server status >/dev/null 2>&1 || pgrep dhcpd >/dev/null 2>&1; then
    ok "Layanan isc-dhcp-server BERJALAN AKTIF tanpa error 'No subnet declaration'."
else
    fail "Layanan isc-dhcp-server gagal aktif. Periksa log."
fi

echo ""
service isc-dhcp-server status
netstat -ulnp 2>/dev/null | grep dhcpd
garis
ok "Konfigurasi Soal 2 selesai sempurna!"
exit 0
