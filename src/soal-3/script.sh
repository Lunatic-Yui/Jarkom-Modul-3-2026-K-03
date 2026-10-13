#!/bin/sh

# ============================================================
# K-03 - SOAL 3: Konfigurasi DHCP Relay pada Jichi Menuju Tengen
# ============================================================

NODE="$(hostname)"
PREFIX="10.65"
DHCP_SERVER="${PREFIX}.4.10"
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
echo " K-03 - SOAL 3: DHCP Relay Jichi & Pembuktian Lease Client"
echo " Node terdeteksi : $NODE"
echo " DHCP Server Target: $DHCP_SERVER"
garis
echo ""

# ============================================================
# NODE: JICHI (DHCP RELAY)
# ============================================================
if [ "$NODE" = "jichi" ]; then
    echo "STEP 1/4 - Memastikan paket isc-dhcp-relay terpasang pada jichi..."
    echo "nameserver $EXT_DNS" > /etc/resolv.conf
    
    if dpkg -s isc-dhcp-relay >/dev/null 2>&1; then
        ok "Paket isc-dhcp-relay sudah terpasang."
    else
        echo "Mengunduh dan memasang isc-dhcp-relay..."
        apt-get update -y && apt-get install -y isc-dhcp-relay || fail "Instalasi isc-dhcp-relay gagal."
        ok "isc-dhcp-relay berhasil dipasang."
    fi

    echo ""
    echo "STEP 2/4 - Mengonfigurasi /etc/default/isc-dhcp-relay..."
    cat > /etc/default/isc-dhcp-relay <<EOF
SERVERS="$DHCP_SERVER"
INTERFACES="eth2 eth3 eth4"
OPTIONS=""
EOF
    ok "Konfigurasi relay diarahkan ke $DHCP_SERVER pada eth2 (Net2), eth3 (Net3), dan eth4 (DC)."

    echo ""
    echo "STEP 3/4 - Memastikan IP Forwarding aktif..."
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    ok "net.ipv4.ip_forward = 1"

    echo ""
    echo "STEP 4/4 - Memulai dan memverifikasi layanan DHCP Relay..."
    service isc-dhcp-relay restart
    sleep 2

    if service isc-dhcp-relay status >/dev/null 2>&1 || pgrep dhcrelay >/dev/null 2>&1; then
        ok "Layanan isc-dhcp-relay BERJALAN AKTIF."
    else
        echo "[INFO] Menjalankan dhcrelay daemon secara langsung jika init-script terkendala container..."
        killall dhcrelay 2>/dev/null
        dhcrelay -i eth2 -i eth3 -i eth4 $DHCP_SERVER
        sleep 1
        pgrep dhcrelay >/dev/null 2>&1 || fail "Gagal menjalankan dhcrelay."
        ok "dhcrelay daemon aktif di latar belakang."
    fi

    echo ""
    service isc-dhcp-relay status 2>/dev/null || ps aux | grep dhcrelay | grep -v grep
    garis
    ok "Konfigurasi DHCP Relay pada jichi SELESAI!"
    exit 0
fi

# ============================================================
# NODE: CLIENT (Divisi A atau Divisi B)
# ============================================================
echo "Menguji perolehan lease DHCP pada client $NODE..."
echo "Menjalankan udhcpc pada interface eth0..."

killall udhcpc 2>/dev/null
if udhcpc -i eth0 -n -q -T 3 -t 3; then
    ok "Client $NODE BERHASIL memperoleh lease IP melalui DHCP Relay!"
    echo ""
    ip -br a show dev eth0
    ip route show default
else
    echo "Mencoba kembali dengan mengirimkan opsi hostname..."
    udhcpc -i eth0 -x hostname:$NODE -c $NODE
    if [ $? -eq 0 ]; then
        ok "Client $NODE BERHASIL memperoleh lease IP!"
        ip -br a show dev eth0
    else
        fail "Client $NODE GAGAL memperoleh lease melalui DHCP Relay. Pastikan jichi & tengen running."
    fi
fi

garis
exit 0
