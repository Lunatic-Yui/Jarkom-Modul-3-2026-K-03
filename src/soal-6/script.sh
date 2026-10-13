#!/bin/sh

# ============================================================
# K-03 - SOAL 6: Fixed Address Static Lease Kugisaki (10.65.3.99)
# ============================================================

NODE="$(hostname)"
PREFIX="10.65"
FIXED_IP="${PREFIX}.3.99"

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
echo " K-03 - SOAL 6: DHCP Static Lease Kugisaki"
echo " Node terdeteksi : $NODE"
echo " Alamat Reservasi: $FIXED_IP"
garis
echo ""

# ============================================================
# NODE: TENGEN (DHCP SERVER)
# ============================================================
if [ "$NODE" = "tengen" ]; then
    MAC_INPUT="$1"
    
    # Jika tidak diberikan MAC argumen, coba deteksi dari leases atau gunakan default container MAC
    if [ -z "$MAC_INPUT" ]; then
        MAC_FOUND="$(grep -B 10 'client-hostname "kugisaki"' /var/lib/dhcp/dhcpd.leases 2>/dev/null | grep 'hardware ethernet' | tail -n 1 | awk '{print $3}' | tr -d ';')"
        if [ -n "$MAC_FOUND" ]; then
            MAC_INPUT="$MAC_FOUND"
            echo "MAC Address Kugisaki terdeteksi otomatis dari lease: $MAC_INPUT"
        else
            MAC_INPUT="02:42:0a:41:03:99"
            echo "Menggunakan MAC default container Kugisaki: $MAC_INPUT"
            echo "(Anda dapat menyertakan MAC secara spesifik: ./script.sh <MAC_ADDRESS>)"
        fi
    fi

    echo ""
    echo "STEP 1/3 - Menambahkan reservasi static host kugisaki ke /etc/dhcp/dhcpd.conf..."

    # Hapus entri host kugisaki lama jika ada
    sed -i '/host kugisaki/,/}/d' /etc/dhcp/dhcpd.conf 2>/dev/null

    cat >> /etc/dhcp/dhcpd.conf <<EOF

# Reservasi VIP Kugisaki (Soal 6)
host kugisaki {
    hardware ethernet $MAC_INPUT;
    fixed-address $FIXED_IP;
}
EOF

    ok "Host declaration untuk kugisaki ($MAC_INPUT -> $FIXED_IP) ditambahkan."

    echo ""
    echo "STEP 2/3 - Validasi sintaks dhcpd..."
    dhcpd -t -cf /etc/dhcp/dhcpd.conf || fail "Validasi sintaks dhcpd.conf gagal!"
    ok "Sintaks valid."

    echo ""
    echo "STEP 3/3 - Merestart service isc-dhcp-server..."
    service isc-dhcp-server restart
    sleep 2
    service isc-dhcp-server status >/dev/null 2>&1 || fail "Layanan isc-dhcp-server gagal aktif!"
    ok "Layanan isc-dhcp-server aktif dengan reservasi static $FIXED_IP untuk Kugisaki!"
    exit 0
fi

# ============================================================
# NODE: KUGISAKI (CLIENT VIP)
# ============================================================
if [ "$NODE" = "kugisaki" ]; then
    MY_MAC="$(cat /sys/class/net/eth0/address 2>/dev/null || ifconfig eth0 | awk '/HWaddr/ {print $5}')"
    echo "MAC Address Kugisaki (eth0): $MY_MAC"
    echo "Jika server belum mendaftarkan MAC ini, jalankan di tengen: ./script.sh $MY_MAC"
    echo ""
    echo "STEP 1/2 - Memperbarui (renew) lease DHCP pada eth0..."
    killall udhcpc 2>/dev/null
    udhcpc -i eth0 -x hostname:kugisaki -c kugisaki -n -q -T 3 -t 3

    echo ""
    echo "STEP 2/2 - Memverifikasi IP yang diperoleh..."
    IP_CURR="$(ip -br a show dev eth0 | awk '{print $3}' | cut -d/ -f1)"
    echo "IP Address saat ini: $IP_CURR"

    if [ "$IP_CURR" = "$FIXED_IP" ]; then
        ok "SUKSES SEMPURNA! Kugisaki menerima fixed address $FIXED_IP sesuai reservasi VIP."
    else
        echo "[WARNING] IP Kugisaki adalah $IP_CURR (Belum $FIXED_IP)."
        echo "Pastikan di tengen telah dijalankan: ./script.sh $MY_MAC lalu ulangi script ini."
    fi

    garis
    exit 0
fi

echo "[INFO] Script ini dijalankan pada 'tengen' (untuk konfigurasi) atau 'kugisaki' (untuk renew)."
exit 0
