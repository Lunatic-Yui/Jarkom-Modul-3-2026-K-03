#!/bin/sh

# ============================================================
# K-03 - SOAL 8: Packet Capture Analisis Protokol DORA & giaddr
# ============================================================

NODE="$(hostname)"
PREFIX="10.65"

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
echo " K-03 - SOAL 8: Packet Capture tcpdump Analisis DORA & giaddr"
echo " Node : $NODE"
garis
echo ""

# ============================================================
# NODE: TENGEN (DHCP SERVER) ATAU JICHI (ROUTER)
# ============================================================
if [ "$NODE" = "tengen" ] || [ "$NODE" = "jichi" ]; then
    echo "Memeriksa ketersediaan tcpdump..."
    if ! command -v tcpdump >/dev/null 2>&1; then
        echo "Memasang tcpdump..."
        apt-get update -y && apt-get install -y tcpdump || fail "Instalasi tcpdump gagal."
    fi

    echo ""
    echo "Menjalankan tcpdump menangkap 4 paket proses DHCP (DORA)..."
    echo "Perintah: tcpdump -i eth0 -n -vvv -s 0 'port 67 or port 68' -c 4"
    echo "Silakan jalankan request DHCP di salah satu client (misal: udhcpc -i eth0)..."
    echo ""

    # Jalankan tcpdump untuk 4 paket
    tcpdump -i eth0 -n -vvv -s 0 'port 67 or port 68' -c 4

    echo ""
    garis
    echo "PANDUAN IDENTIFIKASI PAKET DORA:"
    echo "1. DHCPDISCOVER :"
    echo "   - Dikirim oleh Relay Agent (IP jichi) menuju Server 10.65.4.10"
    echo "   - Periksa field 'giaddr': harus berisi IP interface jichi asal subnet client"
    echo "     (10.65.2.1 untuk Network 2 / Divisi A, atau 10.65.3.1 untuk Network 3 / Divisi B)"
    echo "2. DHCPOFFER    :"
    echo "   - Dikirim oleh Server 10.65.4.10 ke Relay Agent"
    echo "   - Berisi 'Your-IP' (yiaddr) dan 'Lease-Time'"
    echo "3. DHCPREQUEST  :"
    echo "   - Konfirmasi client atas penawaran IP, diteruskan relay dengan giaddr"
    echo "4. DHCPACK      :"
    echo "   - Pengesahan resmi sewa alamat dari Server ke Client"
    garis
    ok "Capture paket DORA selesai!"
    exit 0
fi

# ============================================================
# NODE: CLIENT (Trigger DORA)
# ============================================================
echo "Memicu request lease baru untuk ditangkap oleh tcpdump di server..."
echo "Menjalankan: udhcpc -i eth0 -n -q"
killall udhcpc 2>/dev/null
udhcpc -i eth0 -x hostname:$NODE -c $NODE -n -q

echo ""
ok "Request DHCP berhasil dikirimkan oleh $NODE."
exit 0
