#!/bin/sh
set -eu

PREFIX="10.65"
NODE="$(hostname)"
ACTION="${1:-bench}"
ARG="${2:-}"

DOMAIN="jujutsu.k03.com"
GOJO_IP="${PREFIX}.1.4"
TOTAL_REQUESTS=600
CONCURRENCY=30

RESULT_FILE="${HOME:-/root}/soal20-results.txt"
API_SNIPPET="/etc/nginx/snippets/gojo-api.conf"
ACCESS_LOG="/var/log/nginx/gojo.access.log"

log() {
    printf '[%s] %s\n' "$NODE" "$1"
}

die() {
    printf '[%s] ERROR: %s\n' "$NODE" "$1" >&2
    exit 1
}

require_gojo() {
    [ "$NODE" = "gojo" ] || die "perintah ini dijalankan di gojo"
}

ensure_ab() {
    command -v ab >/dev/null 2>&1 && return 0
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null || die "apt-get update gagal"
        apt-get install -y apache2-utils >/dev/null || die "instalasi apache2-utils gagal"
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache apache2-utils >/dev/null || die "instalasi apache2-utils gagal"
    else
        die "package manager tidak dikenali, pasang apache2-utils secara manual"
    fi
}

resolve_target() {
    if getent hosts "$DOMAIN" >/dev/null 2>&1; then
        TARGET_HOST="$DOMAIN"
        HOST_HEADER=""
    else
        TARGET_HOST="$GOJO_IP"
        HOST_HEADER="Host: ${DOMAIN}"
    fi
}

run_ab() {
    url="http://${TARGET_HOST}$1"
    out="$2"
    if [ -n "$HOST_HEADER" ]; then
        ab -n "$TOTAL_REQUESTS" -c "$CONCURRENCY" -H "$HOST_HEADER" "$url" > "$out" 2>&1 || log "ab selesai dengan peringatan untuk ${url}"
    else
        ab -n "$TOTAL_REQUESTS" -c "$CONCURRENCY" "$url" > "$out" 2>&1 || log "ab selesai dengan peringatan untuk ${url}"
    fi
}

record_result() {
    label="$1"
    name="$2"
    out="$3"

    rps="$(awk '/^Requests per second:/ { print $4 }' "$out")"
    mean="$(awk '/^Time per request:/ { print $4; exit }' "$out")"
    p95="$(awk '$1 == "95%" { print $2 }' "$out")"
    failed="$(awk '/^Failed requests:/ { print $3 }' "$out")"
    non2xx="$(awk '/^Non-2xx responses:/ { print $3 }' "$out")"

    [ -f "$RESULT_FILE" ] || : > "$RESULT_FILE"
    tmp="$(mktemp)"
    awk -F'\t' -v l="$label" -v n="$name" '!($1 == l && $2 == n)' "$RESULT_FILE" > "$tmp"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$label" "$name" "${rps:-0}" "${mean:-0}" "${p95:-0}" "${failed:-0}" "${non2xx:-0}" >> "$tmp"
    mv "$tmp" "$RESULT_FILE"
}

bench() {
    [ -n "$ARG" ] || die "label wajib diisi: baseline atau ratelimit"
    ensure_ab
    resolve_target

    for entry in root:/ api:/api; do
        name="${entry%%:*}"
        path="${entry#*:}"
        out="/tmp/ab_${ARG}_${name}.txt"
        log "ab -n ${TOTAL_REQUESTS} -c ${CONCURRENCY} http://${TARGET_HOST}${path}"
        run_ab "$path" "$out"
        record_result "$ARG" "$name" "$out"
        log "hasil lengkap tersimpan di ${out}"
    done

    report
}

report() {
    [ -s "$RESULT_FILE" ] || die "belum ada hasil benchmark"

    sort -t "$(printf '\t')" -k2,2 -k1,1 "$RESULT_FILE" | awk -F'\t' '
        BEGIN { printf "%-10s %-6s %-12s %-14s %-10s %-8s %s\n", "label", "path", "rps", "mean_ms", "p95_ms", "failed", "non2xx" }
        { printf "%-10s %-6s %-12s %-14s %-10s %-8s %s\n", $1, $2, $3, $4, $5, $6, $7 }
    '

    awk -F'\t' '
        $1 == "baseline" { base[$2] = $3 }
        $1 == "ratelimit" { limited[$2] = $3 }
        END {
            for (name in base) {
                if (name in limited && base[name] > 0) {
                    printf "perubahan rps %s: %.2f -> %.2f (%.1f%%)\n", name, base[name], limited[name], (limited[name] - base[name]) / base[name] * 100
                }
            }
        }
    ' "$RESULT_FILE"
}

ratelimit_off() {
    require_gojo
    if [ ! -f "${API_SNIPPET}.bak" ]; then
        [ -s "$API_SNIPPET" ] || die "rate limit belum dikonfigurasi, jalankan soal-19.sh setup"
        cp "$API_SNIPPET" "${API_SNIPPET}.bak"
    fi
    : > "$API_SNIPPET"
    reload_nginx
    log "rate limit dinonaktifkan"
}

ratelimit_on() {
    require_gojo
    [ -f "${API_SNIPPET}.bak" ] || die "tidak ada konfigurasi rate limit untuk dipulihkan"
    mv "${API_SNIPPET}.bak" "$API_SNIPPET"
    reload_nginx
    log "rate limit diaktifkan kembali"
}

reload_nginx() {
    nginx -t >/dev/null 2>&1 || { nginx -t; die "konfigurasi nginx tidak valid"; }
    nginx -s reload || die "nginx gagal direload"
}

analyze_logs() {
    require_gojo
    [ -f "$ACCESS_LOG" ] || die "${ACCESS_LOG} tidak ditemukan"

    awk '
        function field(name,    re, v) {
            re = name "=[^ ]+"
            if (match($0, re)) {
                v = substr($0, RSTART + length(name) + 1, RLENGTH - length(name) - 1)
                return v
            }
            return ""
        }
        {
            st = field("status")
            cache = field("cache")
            group = ($0 ~ /uri=\/api/) ? "api" : "web"
            if (st ~ /^[23]/) cat = "sukses"
            else if (st == "429") cat = "ditolak_rate_limit"
            else if (st == "499") cat = "koneksi_terputus_client"
            else if (st ~ /^5/) cat = "kegagalan_aplikasi"
            else cat = "lainnya"
            count[group, cat]++
            total[group]++
            if (group == "web" && cache != "-" && cache != "") cachecount[cache]++
        }
        END {
            n = split("sukses ditolak_rate_limit kegagalan_aplikasi koneksi_terputus_client lainnya", cats, " ")
            for (g = 1; g <= 2; g++) {
                group = (g == 1) ? "web" : "api"
                printf "%s total=%d\n", group, total[group] + 0
                for (i = 1; i <= n; i++) {
                    printf "  %-26s %d\n", cats[i], count[group, cats[i]] + 0
                }
            }
            for (c in cachecount) printf "cache %s %d\n", c, cachecount[c]
        }
    ' "$ACCESS_LOG"
}

reset_logs() {
    require_gojo
    : > "$ACCESS_LOG"
    nginx -s reopen
    log "access log gojo dikosongkan"
}

case "$ACTION" in
    bench)
        bench
        ;;
    report)
        report
        ;;
    ratelimit)
        case "$ARG" in
            off) ratelimit_off ;;
            on) ratelimit_on ;;
            *) die "penggunaan: soal-20.sh ratelimit [on|off]" ;;
        esac
        ;;
    logs)
        if [ "$ARG" = "reset" ]; then
            reset_logs
        else
            analyze_logs
        fi
        ;;
    *)
        die "penggunaan: soal-20.sh [bench label|report|ratelimit on|off|logs [reset]]"
        ;;
esac