#!/bin/sh

# ============================================================
# K-03 - SOAL 1: Pemulihan Konektivitas Dasar & Routing Jichi
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
echo " K-03 - SOAL 1: Konektivitas Dasar & Source NAT"
echo " Node terdeteksi : $NODE"
echo " Prefix Kelompok : $PREFIX"
garis
echo ""

# ============================================================
# NODE: JICHI (ROUTER UTAMA)
# ============================================================
if [ "$NODE" = "jichi" ]; then
    echo "STEP 1/4 - Mengonfigurasi antarmuka jaringan jichi..."
    
    cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet static
    address ${PREFIX}.1.1
    netmask 255.255.255.0

auto eth2
iface eth2 inet static
    address ${PREFIX}.2.1
    netmask 255.255.255.0

auto eth3
iface eth3 inet static
    address ${PREFIX}.3.1
    netmask 255.255.255.0

auto eth4
iface eth4 inet static
    address ${PREFIX}.4.1
    netmask 255.255.255.0
EOF

    echo "nameserver $EXT_DNS" > /etc/resolv.conf
    
    # Terapkan IP secara dinamis langsung tanpa perlu restart jika sudah jalan
    ifconfig eth1 ${PREFIX}.1.1 netmask 255.255.255.0 up 2>/dev/null || ip addr add ${PREFIX}.1.1/24 dev eth1 2>/dev/null
    ifconfig eth2 ${PREFIX}.2.1 netmask 255.255.255.0 up 2>/dev/null || ip addr add ${PREFIX}.2.1/24 dev eth2 2>/dev/null
    ifconfig eth3 ${PREFIX}.3.1 netmask 255.255.255.0 up 2>/dev/null || ip addr add ${PREFIX}.3.1/24 dev eth3 2>/dev/null
    ifconfig eth4 ${PREFIX}.4.1 netmask 255.255.255.0 up 2>/dev/null || ip addr add ${PREFIX}.4.1/24 dev eth4 2>/dev/null
    
    ok "Interface eth0 - eth4 terkonfigurasi."

    echo ""
    echo "STEP 2/4 - Mengaktifkan IPv4 Forwarding..."
    sysctl -w net.ipv4.ip_forward=1
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    ok "IPv4 Forwarding aktif (sysctl net.ipv4.ip_forward = 1)."

    echo ""
    echo "STEP 3/4 - Mengonfigurasi Source NAT (MASQUERADE)..."
    iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    ok "Source NAT pada eth0 berhasil diterapkan."

    echo ""
    echo "STEP 4/4 - Verifikasi status router jichi..."
    ip -br a
    echo ""
    iptables -t nat -L POSTROUTING -v -n
    echo ""
    ok "Konfigurasi jichi selesai dan terverifikasi."
    exit 0
fi

# ============================================================
# HOST INFRASTRUKTUR STATIS
# ============================================================
STATIC_IP=""
STATIC_GW=""

case "$NODE" in
    "utahime")
        STATIC_IP="${PREFIX}.1.2"
        STATIC_GW="${PREFIX}.1.1"
        ;;
    "shoko")
        STATIC_IP="${PREFIX}.1.3"
        STATIC_GW="${PREFIX}.1.1"
        ;;
    "gojo")
        STATIC_IP="${PREFIX}.1.4"
        STATIC_GW="${PREFIX}.1.1"
        ;;
    "geto")
        STATIC_IP="${PREFIX}.4.2"
        STATIC_GW="${PREFIX}.4.1"
        ;;
    "maki")
        STATIC_IP="${PREFIX}.4.3"
        STATIC_GW="${PREFIX}.4.1"
        ;;
    "panda")
        STATIC_IP="${PREFIX}.4.4"
        STATIC_GW="${PREFIX}.4.1"
        ;;
    "nanami")
        STATIC_IP="${PREFIX}.4.5"
        STATIC_GW="${PREFIX}.4.1"
        ;;
    "todo")
        STATIC_IP="${PREFIX}.4.6"
        STATIC_GW="${PREFIX}.4.1"
        ;;
    "kirara")
        STATIC_IP="${PREFIX}.4.7"
        STATIC_GW="${PREFIX}.4.1"
        ;;
    "yaga")
        STATIC_IP="${PREFIX}.4.8"
        STATIC_GW="${PREFIX}.4.1"
        ;;
    "inumaki")
        STATIC_IP="${PREFIX}.4.9"
        STATIC_GW="${PREFIX}.4.1"
        ;;
    "tengen")
        STATIC_IP="${PREFIX}.4.10"
        STATIC_GW="${PREFIX}.4.1"
        ;;
esac

if [ -n "$STATIC_IP" ]; then
    echo "STEP 1/3 - Menetapkan IP statis $STATIC_IP pada $NODE..."
    cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address $STATIC_IP
    netmask 255.255.255.0
    gateway $STATIC_GW
EOF

    echo "nameserver $EXT_DNS" > /etc/resolv.conf
    
    # Terapkan langsung
    ifconfig eth0 $STATIC_IP netmask 255.255.255.0 up 2>/dev/null || ip addr add $STATIC_IP/24 dev eth0 2>/dev/null
    ip route del default 2>/dev/null
    ip route add default via $STATIC_GW dev eth0 2>/dev/null

    ok "IP $STATIC_IP gateway $STATIC_GW berhasil dikonfigurasi."

    echo ""
    echo "STEP 2/3 - Menguji konektivitas ke gateway ($STATIC_GW)..."
    if ping -c 2 $STATIC_GW >/dev/null 2>&1; then
        ok "Ping ke gateway $STATIC_GW BERHASIL."
    else
        fail "Ping ke gateway $STATIC_GW GAGAL."
    fi

    echo ""
    echo "STEP 3/3 - Menguji akses ke jaringan eksternal (8.8.8.8)..."
    if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        ok "Akses keluar ke 8.8.8.8 BERHASIL."
    else
        echo "[INFO] Gateway belum terhubung ke NAT internet, pastikan jichi sudah running."
    fi

    echo ""
    ip -br a
    garis
    ok "Host infrastruktur $NODE siap digunakan."
    exit 0
fi

echo "[INFO] Node $NODE adalah client dinamis DHCP. Konfigurasi IP akan diperoleh melalui DHCP Relay."
exit 0
