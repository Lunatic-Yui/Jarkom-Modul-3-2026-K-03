#!/bin/sh

# ============================================================
# K-03 - SOAL 4: Konfigurasi Dua Pool DHCP Berdasarkan Class di Network 2
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
    echo "============================================================"
}

echo ""
garis
echo " K-03 - SOAL 4: DHCP Class & Pool 1 / Pool 2 Network 2"
echo " Node terdeteksi : $NODE"
echo " Subnet Network 2: ${PREFIX}.2.0/24"
garis
echo ""

# ============================================================
# NODE: TENGEN (DHCP SERVER)
# ============================================================
if [ "$NODE" = "tengen" ]; then
    echo "STEP 1/3 - Menyusun definisi Class & Pool di /etc/dhcp/dhcpd.conf..."

    cat > /etc/dhcp/dhcpd.conf <<EOF
# dhcpd.conf - Soal 4: Two Pools Network 2 (Divisi A)
default-lease-time 1800;
max-lease-time 43200;
authoritative;

# Definisi Class Pool 1: itadori & fushiguro (Dev Team)
class "pool1-dev" {
    match if (
        substring(option dhcp-client-identifier, 1, 8) = "itadori"
        or substring(option dhcp-client-identifier, 1, 9) = "fushiguro"
        or option host-name = "itadori"
        or option host-name = "fushiguro"
        or hardware = 1:02:42:0a:41:02:10
        or hardware = 1:02:42:0a:41:02:11
    );
}

# Definisi Class Pool 2: zenin & okkotsu (Support Team)
class "pool2-support" {
    match if (
        substring(option dhcp-client-identifier, 1, 5) = "zenin"
        or substring(option dhcp-client-identifier, 1, 7) = "okkotsu"
        or option host-name = "zenin"
        or option host-name = "okkotsu"
        or hardware = 1:02:42:0a:41:02:70
        or hardware = 1:02:42:0a:41:02:71
    );
}

# Network 4 - Subnet Lokal Data Center (tanpa dynamic pool)
subnet ${PREFIX}.4.0 netmask 255.255.255.0 {
}

# Network 2 - Divisi A (Dua Pool terpisah + Rentang .36-.69 dilarang)
subnet ${PREFIX}.2.0 netmask 255.255.255.0 {
    option routers ${PREFIX}.2.1;
    option broadcast-address ${PREFIX}.2.255;
    option domain-name-servers ${PREFIX}.1.2, ${PREFIX}.1.3;
    option domain-search "k03.com";

    # Pool 1 (10.65.2.10 - 10.65.2.35)
    pool {
        allow members of "pool1-dev";
        range ${PREFIX}.2.10 ${PREFIX}.2.35;
    }

    # Pool 2 (10.65.2.70 - 10.65.2.95)
    pool {
        allow members of "pool2-support";
        range ${PREFIX}.2.70 ${PREFIX}.2.95;
    }
}

# Network 3 - Divisi B scope
subnet ${PREFIX}.3.0 netmask 255.255.255.0 {
    option routers ${PREFIX}.3.1;
    option broadcast-address ${PREFIX}.3.255;
    option domain-name-servers ${PREFIX}.1.2, ${PREFIX}.1.3;
    option domain-search "k03.com";
}
EOF

    ok "dhcpd.conf diperbarui dengan class pool1-dev dan pool2-support."

    echo ""
    echo "STEP 2/3 - Validasi sintaks dhcpd..."
    dhcpd -t -cf /etc/dhcp/dhcpd.conf || fail "Validasi sintaks dhcpd.conf gagal!"
    ok "Sintaks valid."

    echo ""
    echo "STEP 3/3 - Merestart service isc-dhcp-server..."
    service isc-dhcp-server restart
    sleep 2
    service isc-dhcp-server status >/dev/null 2>&1 || fail "isc-dhcp-server tidak aktif!"
    ok "Layanan isc-dhcp-server aktif dengan kebijakan class Pool 1 & Pool 2!"
    exit 0
fi

# ============================================================
# NODE: CLIENT NETWORK 2 (itadori, fushiguro, zenin, okkotsu)
# ============================================================
echo "Menguji alokasi IP berdasarkan class untuk node $NODE..."
killall udhcpc 2>/dev/null

# Jalankan udhcpc dengan menyertakan Client-ID dan hostname
udhcpc -i eth0 -x hostname:$NODE -c $NODE -n -q -T 3 -t 3

IP_OBTAINED="$(ip -br a show dev eth0 | awk '{print $3}' | cut -d/ -f1)"
echo "IP yang diperoleh: $IP_OBTAINED"

case "$NODE" in
    "itadori"|"fushiguro")
        # Harusnya berada di rentang .10 - .35
        OCTET4="$(echo $IP_OBTAINED | cut -d. -f4)"
        if [ "$OCTET4" -ge 10 ] && [ "$OCTET4" -le 35 ]; then
            ok "SUKSES! $NODE memperoleh IP $IP_OBTAINED dari Pool 1 (10.65.2.10 - 10.65.2.35)."
        else
            fail "IP $IP_OBTAINED berada di luar rentang Pool 1 (10.65.2.10 - 10.65.2.35)!"
        fi
        ;;
    "zenin"|"okkotsu")
        # Harusnya berada di rentang .70 - .95
        OCTET4="$(echo $IP_OBTAINED | cut -d. -f4)"
        if [ "$OCTET4" -ge 70 ] && [ "$OCTET4" -le 95 ]; then
            ok "SUKSES! $NODE memperoleh IP $IP_OBTAINED dari Pool 2 (10.65.2.70 - 10.65.2.95)."
        else
            fail "IP $IP_OBTAINED berada di luar rentang Pool 2 (10.65.2.70 - 10.65.2.95)!"
        fi
        ;;
    *)
        echo "[INFO] Node $NODE bukan target class Network 2."
        ;;
esac

garis
exit 0
