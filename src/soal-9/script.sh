#!/bin/sh

# ============================================================
# K-03 - SOAL 9: Simulasi Gangguan Relay & Pemulihan Layanan
# ============================================================

NODE="$(hostname)"
ACTION="$1"

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
echo " K-03 - SOAL 9: Simulasi Gangguan Relay & Pemulihan Layanan"
echo " Node : $NODE"
garis
echo ""

# ============================================================
# NODE: JICHI (ROUTER / RELAY)
# ============================================================
if [ "$NODE" = "jichi" ]; then
    if [ "$ACTION" = "stop" ]; then
        echo "SIMULASI GANGGUAN: Menghentikan service DHCP Relay..."
        service isc-dhcp-relay stop
        killall dhcrelay 2>/dev/null
        sleep 1
        service isc-dhcp-relay status 2>/dev/null || ok "Service DHCP Relay BERHASIL DIHENTIKAN."
        echo ""
        echo "Langkah selanjutnya: Jalankan './script.sh' di client untuk mengamati kegagalan."
        exit 0
    elif [ "$ACTION" = "start" ] || [ "$ACTION" = "restore" ]; then
        echo "PEMULIHAN: Menjalankan kembali service DHCP Relay..."
        service isc-dhcp-relay start
        sleep 1
        if service isc-dhcp-relay status >/dev/null 2>&1 || pgrep dhcrelay >/dev/null 2>&1; then
            ok "Service DHCP Relay BERHASIL DIPULIHKAN."
        else
            dhcrelay -i eth2 -i eth3 -i eth4 10.65.4.10
            ok "dhcrelay dijalankan manual."
        fi
        echo ""
        echo "Langkah selanjutnya: Jalankan './script.sh' di client untuk menguji pemulihan."
        exit 0
    else
        echo "Pilihan aksi untuk jichi:"
        echo "  ./script.sh stop     -> Menghentikan service relay (simulasi gangguan)"
        echo "  ./script.sh restore  -> Menghidupkan kembali service relay (pemulihan)"
        exit 0
    fi
fi

# ============================================================
# NODE: CLIENT (itadori, fushiguro, zenin, ino, kusakabe, miwa, kugisaki)
# ============================================================
echo "Menguji permintaan sewa alamat baru pada $NODE..."
killall udhcpc 2>/dev/null

echo "Menjalankan: udhcpc -i eth0 -n -q -T 3 -t 2"
if udhcpc -i eth0 -x hostname:$NODE -c $NODE -n -q -T 3 -t 2; then
    echo ""
    ok "PEMULIHAN BERHASIL! Client memperoleh IP kembali."
    echo ""
    echo "Detail Konfigurasi:"
    ip -br a show dev eth0
    ip route show default
else
    echo ""
    echo "[GEJALA GANGGUAN TERCATAT]"
    echo "udhcpc mengalami timeout (no lease, failing)."
    echo "Penyebab: Paket DHCPDISCOVER broadcast dari client tidak dapat diteruskan menyeberang router jichi ke Data Center karena relay nonaktif."
fi

garis
exit 0
