#!/bin/sh

# ============================================================
# K-03 - SOAL 5: Short Lease & Long Lease serta Opsi DNS di Network 3
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
echo " K-03 - SOAL 5: Short Lease & Long Lease Network 3"
echo " Node terdeteksi : $NODE"
echo " Subnet Network 3: ${PREFIX}.3.0/24"
garis
echo ""

# ============================================================
# NODE: TENGEN (DHCP SERVER)
# ============================================================
if [ "$NODE" = "tengen" ]; then
    echo "STEP 1/3 - Menyusun konfigurasi Short Lease (1800s) & Long Lease (43200s)..."

    cat > /etc/dhcp/dhcpd.conf <<EOF
# dhcpd.conf - Soal 5: Lease Times & Options
default-lease-time 1800;
max-lease-time 43200;
authoritative;

# --- Network 2 Classes ---
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

# --- Network 3 Classes ---
# Short Lease: ino & kusakabe (1800 detik / 30 menit)
class "short-lease-team" {
    match if (
        substring(option dhcp-client-identifier, 1, 3) = "ino"
        or substring(option dhcp-client-identifier, 1, 8) = "kusakabe"
        or option host-name = "ino"
        or option host-name = "kusakabe"
        or hardware = 1:02:42:0a:41:03:10
        or hardware = 1:02:42:0a:41:03:11
    );
    default-lease-time 1800;
    max-lease-time 1800;
}

# Long Lease: miwa (43200 detik / 12 jam)
class "long-lease-team" {
    match if (
        substring(option dhcp-client-identifier, 1, 4) = "miwa"
        or option host-name = "miwa"
        or hardware = 1:02:42:0a:41:03:64
    );
    default-lease-time 43200;
    max-lease-time 43200;
}

# Network 4 - Subnet Lokal Data Center
subnet ${PREFIX}.4.0 netmask 255.255.255.0 {
}

# Network 2 - Divisi A
subnet ${PREFIX}.2.0 netmask 255.255.255.0 {
    option routers ${PREFIX}.2.1;
    option broadcast-address ${PREFIX}.2.255;
    option domain-name-servers ${PREFIX}.1.2, ${PREFIX}.1.3;
    option domain-search "k03.com";

    pool {
        allow members of "pool1-dev";
        range ${PREFIX}.2.10 ${PREFIX}.2.35;
    }
    pool {
        allow members of "pool2-support";
        range ${PREFIX}.2.70 ${PREFIX}.2.95;
    }
}

# Network 3 - Divisi B (Short & Long Lease Pools)
subnet ${PREFIX}.3.0 netmask 255.255.255.0 {
    option routers ${PREFIX}.3.1;
    option broadcast-address ${PREFIX}.3.255;
    option domain-name-servers ${PREFIX}.1.2, ${PREFIX}.1.3;
    option domain-search "k03.com";

    # Short lease pool (10.65.3.10 - 10.65.3.89)
    pool {
        allow members of "short-lease-team";
        range ${PREFIX}.3.10 ${PREFIX}.3.89;
    }

    # Long lease pool (10.65.3.100 - 10.65.3.199)
    pool {
        allow members of "long-lease-team";
        range ${PREFIX}.3.100 ${PREFIX}.3.199;
    }
}
EOF

    ok "dhcpd.conf dikonfigurasi dengan short lease & long lease pools."

    echo ""
    echo "STEP 2/3 - Validasi sintaks..."
    dhcpd -t -cf /etc/dhcp/dhcpd.conf || fail "Validasi sintaks gagal!"
    ok "Sintaks valid."

    echo ""
    echo "STEP 3/3 - Merestart isc-dhcp-server..."
    service isc-dhcp-server restart
    sleep 2
    service isc-dhcp-server status >/dev/null 2>&1 || fail "Layanan isc-dhcp-server gagal aktif!"
    ok "isc-dhcp-server aktif dengan aturan lease time Soal 5!"
    exit 0
fi

# ============================================================
# NODE: CLIENT NETWORK 3 (ino, kusakabe, miwa)
# ============================================================
echo "Menguji alokasi lease & DNS options untuk node $NODE..."
killall udhcpc 2>/dev/null

udhcpc -i eth0 -x hostname:$NODE -c $NODE -n -q -T 3 -t 3

IP_OBTAINED="$(ip -br a show dev eth0 | awk '{print $3}' | cut -d/ -f1)"
echo "IP yang diperoleh: $IP_OBTAINED"

case "$NODE" in
    "ino"|"kusakabe")
        OCTET4="$(echo $IP_OBTAINED | cut -d. -f4)"
        if [ "$OCTET4" -ge 10 ] && [ "$OCTET4" -le 89 ]; then
            ok "SUKSES! $NODE memperoleh IP $IP_OBTAINED di rentang Short Lease (10.65.3.10 - 10.65.3.89)."
        else
            fail "IP $IP_OBTAINED di luar rentang short lease!"
        fi
        ;;
    "miwa")
        OCTET4="$(echo $IP_OBTAINED | cut -d. -f4)"
        if [ "$OCTET4" -ge 100 ] && [ "$OCTET4" -le 199 ]; then
            ok "SUKSES! $NODE memperoleh IP $IP_OBTAINED di rentang Long Lease (10.65.3.100 - 10.65.3.199)."
        else
            fail "IP $IP_OBTAINED di luar rentang long lease!"
        fi
        ;;
esac

echo ""
echo "Memeriksa /etc/resolv.conf..."
cat /etc/resolv.conf
if grep -q "${PREFIX}.1.2" /etc/resolv.conf && grep -q "k03.com" /etc/resolv.conf; then
    ok "DHCP Options DNS (${PREFIX}.1.2, ${PREFIX}.1.3) dan domain-search k03.com terkonfigurasi!"
else
    fail "Opsi DNS/domain belum sesuai di /etc/resolv.conf."
fi

garis
exit 0
