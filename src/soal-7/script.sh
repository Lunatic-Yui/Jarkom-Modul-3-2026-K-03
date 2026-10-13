#!/bin/sh

# ============================================================
# K-03 - SOAL 7: Audit dan Validasi Lengkap Alokasi Jaringan Klien
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
echo " K-03 - SOAL 7: Audit & Verifikasi Jaringan Client Divisi A & B"
echo " Node : $NODE"
garis
echo ""

# ============================================================
# JIKA DIJALANKAN DI TENGEN (AUDIT SERVER & LEASES)
# ============================================================
if [ "$NODE" = "tengen" ]; then
    echo "AUDIT SISI SERVER (/var/lib/dhcp/dhcpd.leases)"
    echo "--------------------------------------------------------------------------------"
    if [ ! -f /var/lib/dhcp/dhcpd.leases ]; then
        fail "File /var/lib/dhcp/dhcpd.leases tidak ditemukan!"
    fi

    echo "Daftar Lease Aktif yang Tercatat:"
    grep -E "lease 10\." /var/lib/dhcp/dhcpd.leases | sort -u
    echo ""

    echo "Memeriksa kemungkinan IP tumpang tindih (duplicate leases)..."
    DUPLICATES="$(grep -E "lease 10\." /var/lib/dhcp/dhcpd.leases | awk '{print $2}' | sort | uniq -d)"
    if [ -z "$DUPLICATES" ]; then
        ok "Tidak ada IP duplikat di tabel leases."
    else
        echo "[WARNING] Terdapat IP yang teralokasi berulang: $DUPLICATES"
    fi

    echo ""
    echo "Memeriksa apakah terdapat alokasi pada rentang terlarang (10.65.2.36 - 10.65.2.69)..."
    FORBIDDEN="$(awk '/lease 10.65.2./ {split($2,a,"."); if(a[4]>=36 && a[4]<=69) print $2}' /var/lib/dhcp/dhcpd.leases)"
    if [ -z "$FORBIDDEN" ]; then
        ok "Rentang terlarang (10.65.2.36 - 10.65.2.69) AMAN (0 alokasi)."
    else
        fail "DITEMUKAN pelanggaran kebijakan pool! IP di rentang terlarang: $FORBIDDEN"
    fi

    echo ""
    echo "Memeriksa host static Kugisaki..."
    grep "host kugisaki" /etc/dhcp/dhcpd.conf -A 3
    ok "Audit DHCP Server tengen selesai."
    garis
    exit 0
fi

# ============================================================
# JIKA DIJALANKAN DI CLIENT
# ============================================================
echo "AUDIT SISI CLIENT ($NODE)"
echo "--------------------------------------------------------------------------------"

IP_ADDR="$(ip -br a show dev eth0 2>/dev/null | awk '{print $3}' | cut -d/ -f1)"
NETMASK="$(ifconfig eth0 2>/dev/null | awk '/Mask:/ {print $4}' | cut -d: -f2)"
[ -z "$NETMASK" ] && NETMASK="$(ip a show dev eth0 | grep -o 'inet [0-9.]*/24' | cut -d/ -f2)"
GATEWAY="$(ip route show default 2>/dev/null | awk '{print $3}')"
BCAST="$(ifconfig eth0 2>/dev/null | awk '/Bcast:/ {print $3}' | cut -d: -f2)"
[ -z "$BCAST" ] && BCAST="$(ip a show dev eth0 | awk '/brd/ {print $4}')"

echo "Node             : $NODE"
echo "IP Address       : $IP_ADDR"
echo "Netmask / Prefix : $NETMASK"
echo "Default Gateway  : $GATEWAY"
echo "Broadcast        : $BCAST"
echo ""

echo "Isi /etc/resolv.conf:"
cat /etc/resolv.conf
echo ""

# Validasi Gateway
EXPECTED_GW=""
case "$NODE" in
    "itadori"|"fushiguro"|"zenin"|"okkotsu")
        EXPECTED_GW="${PREFIX}.2.1"
        ;;
    "ino"|"kusakabe"|"miwa"|"kugisaki")
        EXPECTED_GW="${PREFIX}.3.1"
        ;;
esac

if [ "$GATEWAY" = "$EXPECTED_GW" ]; then
    ok "Default Gateway Sesuai Wilayah: $GATEWAY"
else
    echo "[WARNING] Gateway $GATEWAY berbeda dari ekspektasi ($EXPECTED_GW)"
fi

# Validasi DNS
if grep -q "${PREFIX}.1.2" /etc/resolv.conf && grep -q "${PREFIX}.1.3" /etc/resolv.conf; then
    ok "DNS Master (${PREFIX}.1.2) dan DNS Slave (${PREFIX}.1.3) Sesuai"
else
    echo "[WARNING] DNS server belum lengkap di /etc/resolv.conf"
fi

# Validasi Domain
if grep -q "k03.com" /etc/resolv.conf; then
    ok "Search Domain 'k03.com' Sesuai"
fi

# Tes Ping Gateway
if ping -c 2 $GATEWAY >/dev/null 2>&1; then
    ok "Ping ke Gateway $GATEWAY: BERHASIL (0% Packet Loss)"
else
    echo "[GAGAL] Tidak dapat menghubungi gateway $GATEWAY"
fi

garis
ok "Verifikasi client $NODE selesai!"
exit 0
