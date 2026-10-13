#!/bin/sh

# ============================================================
# K-03 - MASTER SETUP RUNNER (SOAL 1 - 12)
# ============================================================
# Jalankan script ini pada node mana saja untuk melakukan
# setup otomatis seluruh konfigurasi yang relevan untuk node tersebut.
# ============================================================

NODE="$(hostname)"
BASE_DIR="$(dirname "$0")"

echo "============================================================"
echo " JUJUTSU HIGH - SHIBUYA INCIDENT (K-03)"
echo " MENJALANKAN MASTER SETUP PADA NODE: $NODE"
echo "============================================================"

# Jalankan Soal 1 (Konektivitas Dasar & IP Statis)
if [ -f "$BASE_DIR/soal-1/script.sh" ]; then
    echo ">>> Menjalankan Setup Soal 1..."
    sh "$BASE_DIR/soal-1/script.sh"
fi

# Jalankan Soal 2 (DHCP Server Tengen)
if [ "$NODE" = "tengen" ] && [ -f "$BASE_DIR/soal-2/script.sh" ]; then
    echo ">>> Menjalankan Setup Soal 2..."
    sh "$BASE_DIR/soal-2/script.sh"
fi

# Jalankan Soal 3 (DHCP Relay Jichi)
if [ "$NODE" = "jichi" ] && [ -f "$BASE_DIR/soal-3/script.sh" ]; then
    echo ">>> Menjalankan Setup Soal 3..."
    sh "$BASE_DIR/soal-3/script.sh"
fi

# Jalankan Soal 4, 5, 6 (DHCP Pools, Leases, Static pada Tengen)
if [ "$NODE" = "tengen" ]; then
    echo ">>> Menjalankan Setup Kebijakan DHCP Lengkap (Soal 4, 5, 6)..."
    sh "$BASE_DIR/soal-4/script.sh"
    sh "$BASE_DIR/soal-5/script.sh"
    sh "$BASE_DIR/soal-6/script.sh"
fi

# Jalankan Soal 10 (Autostart Tengen / Jichi)
if [ "$NODE" = "tengen" ] || [ "$NODE" = "jichi" ]; then
    echo ">>> Menjalankan Setup Autostart & Persistensi (Soal 10)..."
    sh "$BASE_DIR/soal-10/script.sh"
fi

# Jalankan Soal 11 & 12 (DNS Master Utahime & Slave Shoko)
if [ "$NODE" = "utahime" ] || [ "$NODE" = "shoko" ]; then
    echo ">>> Menjalankan Setup DNS Master / Slave & Forwarder (Soal 11, 12)..."
    sh "$BASE_DIR/soal-11/script.sh"
    sh "$BASE_DIR/soal-12/script.sh"
fi

# Jika Client, minta lease DHCP
case "$NODE" in
    "itadori"|"fushiguro"|"zenin"|"okkotsu"|"ino"|"kusakabe"|"miwa"|"kugisaki")
        echo ">>> Menjalankan Request DHCP Client..."
        killall udhcpc 2>/dev/null
        udhcpc -i eth0 -x hostname:$NODE -c $NODE -n -q -T 3 -t 3
        sh "$BASE_DIR/soal-7/script.sh"
        ;;
esac

echo ""
echo "============================================================"
echo " MASTER SETUP PADA NODE $NODE SELESAI!"
echo "============================================================"
