#!/bin/sh

# ============================================================
# K-03 - SOAL 10: Autostart, Persistensi Setelah Reboot, & Re-Verifikasi
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
echo " K-03 - SOAL 10: Persistensi Layanan & Kebijakan DHCP Pasca-Reboot"
echo " Node : $NODE"
garis
echo ""

# ============================================================
# NODE: TENGEN (DHCP SERVER AUTOSTART)
# ============================================================
if [ "$NODE" = "tengen" ]; then
    echo "STEP 1/3 - Memastikan autostart isc-dhcp-server diaktifkan..."
    
    # Daftarkan ke sysv-rc runlevel
    update-rc.d isc-dhcp-server defaults 2>/dev/null
    
    # Tambahkan safety hook di /root/.bashrc atau rc.local agar container docker tetap menyala saat re-attach
    if ! grep -q "service isc-dhcp-server" /root/.bashrc 2>/dev/null; then
        echo "service isc-dhcp-server status >/dev/null 2>&1 || service isc-dhcp-server start" >> /root/.bashrc
    fi

    # Pastikan file interfaces tetap memuat gateway
    cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address ${PREFIX}.4.10
    netmask 255.255.255.0
    gateway ${PREFIX}.4.1
    up service isc-dhcp-server start
EOF

    ok "Autostart isc-dhcp-server terkonfigurasi."

    echo ""
    echo "STEP 2/3 - Memeriksa status saat ini..."
    service isc-dhcp-server status

    echo ""
    echo "STEP 3/3 - Memvalidasi kepatuhan konfigurasi dhcpd.conf..."
    dhcpd -t -cf /etc/dhcp/dhcpd.conf || fail "Sintaks tidak valid!"
    ok "Konfigurasi utuh dan siap bertahan setelah reboot."
    garis
    exit 0
fi

# ============================================================
# NODE: JICHI (DHCP RELAY AUTOSTART)
# ============================================================
if [ "$NODE" = "jichi" ]; then
    echo "STEP 1/3 - Mengonfigurasi autostart isc-dhcp-relay & iptables..."
    
    update-rc.d isc-dhcp-relay defaults 2>/dev/null
    
    if ! grep -q "service isc-dhcp-relay" /root/.bashrc 2>/dev/null; then
        echo "service isc-dhcp-relay status >/dev/null 2>&1 || service isc-dhcp-relay start" >> /root/.bashrc
    fi

    cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    up sysctl -w net.ipv4.ip_forward=1
    up iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

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
    up service isc-dhcp-relay start
EOF

    ok "Autostart isc-dhcp-relay & routing interfaces terkonfigurasi."

    echo ""
    echo "STEP 2/3 - Memeriksa status layanan..."
    service isc-dhcp-relay status

    echo ""
    echo "STEP 3/3 - Memeriksa tabel NAT..."
    iptables -t nat -L POSTROUTING -v -n
    garis
    exit 0
fi

# ============================================================
# NODE: CLIENT (VERIFIKASI SEMUA KEBIJAKAN SETELAH REBOOT)
# ============================================================
echo "Memverifikasi kesinambungan lease dan gateway pada $NODE..."
killall udhcpc 2>/dev/null
udhcpc -i eth0 -x hostname:$NODE -c $NODE -n -q -T 3 -t 3

echo ""
ip -br a show dev eth0
ip route show default

echo ""
echo "Menguji ping ke Gateway..."
GW="$(ip route show default | awk '{print $3}')"
if ping -c 2 $GW >/dev/null 2>&1; then
    ok "Koneksi ke Gateway $GW BERHASIL."
else
    fail "Koneksi ke Gateway GAGAL."
fi

echo ""
echo "Menguji ping ke DHCP Server tengen (${PREFIX}.4.10)..."
if ping -c 2 ${PREFIX}.4.10 >/dev/null 2>&1; then
    ok "Koneksi antar-subnet ke DHCP Server BERHASIL."
fi

garis
ok "Verifikasi persistensi Soal 10 SELESAI!"
exit 0
