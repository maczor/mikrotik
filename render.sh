#!/usr/bin/env bash
# =============================================================================
# render.sh — generuje finalne pliki .rsc z templates i .env
#
# Użycie:
#   ./render.sh                # generuje wszystko do out/
#   ./render.sh --dry-run      # pokazuje co by zrobiło, nic nie zapisuje
#   ./render.sh --check        # sprawdza czy wszystkie placeholdery uzupełnione
#
# Wymagania: bash 4+, sed, gawk (lub macOS sed)
# =============================================================================

set -euo pipefail

cd "$(dirname "$0")"

ENV_FILE=".env"
OUT_DIR="out"
TEMPLATES_DIR="configs"
TEMPLATES=(
    "$TEMPLATES_DIR/1-lhg-passthrough.rsc"
    "$TEMPLATES_DIR/2-hap-router.rsc"
    "$TEMPLATES_DIR/3-cap-light-config.rsc"
)

DRY_RUN=0
CHECK_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --check)   CHECK_ONLY=1 ;;
        -h|--help)
            grep -E "^# " "$0" | head -15 | sed 's/^# //'
            exit 0
            ;;
        *) echo "Nieznany argument: $arg" >&2; exit 1 ;;
    esac
done

# --- 1. Sprawdź .env ---------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
    echo "BŁĄD: brak pliku $ENV_FILE" >&2
    echo "Wykonaj: cp .env.example .env  &&  edytuj .env" >&2
    exit 1
fi

# Permissions check (Unix only)
if [[ "$(uname)" != "Darwin" && "$(uname)" != "Linux" ]]; then :;
elif [[ "$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE")" != "600" ]]; then
    echo "OSTRZEŻENIE: $ENV_FILE ma luźne uprawnienia. Wykonaj: chmod 600 $ENV_FILE" >&2
fi

# --- 2. Wczytaj zmienne ------------------------------------------------------
set -a
# shellcheck disable=SC1091
source "$ENV_FILE"
set +a

# Lista wymaganych zmiennych - musi pokrywać się z placeholderami w .rsc
REQUIRED_VARS=(
    LHG_ADMIN_PASSWORD HAP_ADMIN_PASSWORD CAP1_ADMIN_PASSWORD CAP2_ADMIN_PASSWORD
    PRIV_WIFI_PASSWORD CAMS_WIFI_PASSWORD
    APN HAP_ETHER1_MAC
    CAP1_IDENTITY CAP2_IDENTITY
)

# --- 3. Walidacja ------------------------------------------------------------
# Uwaga: pod `set -e` `((errors++))` wyjdzie ze skryptu gdy errors=0
# (post-increment zwraca 0 → exit status 1). Dlatego errors=$((errors+1)).
errors=0
for var in "${REQUIRED_VARS[@]}"; do
    val="${!var:-}"
    if [[ -z "$val" ]]; then
        echo "BŁĄD: zmienna $var jest pusta" >&2
        errors=$((errors+1))
    elif [[ "$val" == zmien-mnie* ]]; then
        echo "BŁĄD: zmienna $var nie została zmieniona z domyślnej wartości" >&2
        errors=$((errors+1))
    fi
done

# Specyficzna walidacja: MAC format
if [[ ! "$HAP_ETHER1_MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    echo "BŁĄD: HAP_ETHER1_MAC ($HAP_ETHER1_MAC) nie jest poprawnym MAC-iem (AA:BB:CC:DD:EE:FF)" >&2
    errors=$((errors+1))
fi

# APN nie może zawierać białych znaków (zepsuje syntax .rsc)
if [[ "$APN" =~ [[:space:]] ]]; then
    echo "BŁĄD: APN ($APN) zawiera białe znaki" >&2
    errors=$((errors+1))
fi

# Hasła admina min. długości (twardy próg)
for var in LHG_ADMIN_PASSWORD HAP_ADMIN_PASSWORD CAP1_ADMIN_PASSWORD CAP2_ADMIN_PASSWORD; do
    val="${!var:-}"
    if [[ ${#val} -lt 12 ]]; then
        echo "OSTRZEŻENIE: $var krótsze niż 12 znaków (${#val})" >&2
    fi
done

# Hasła WiFi min. długości (WPA2-PSK wymaga 8, my chcemy 12)
for var in PRIV_WIFI_PASSWORD CAMS_WIFI_PASSWORD; do
    val="${!var:-}"
    if [[ ${#val} -lt 12 ]]; then
        echo "OSTRZEŻENIE: $var krótsze niż 12 znaków (${#val})" >&2
    fi
done

if [[ $errors -gt 0 ]]; then
    echo "" >&2
    echo "$errors błędów - popraw .env i uruchom ponownie." >&2
    exit 2
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
    echo "OK: .env wygląda poprawnie (${#REQUIRED_VARS[@]} zmiennych)."
    exit 0
fi

# --- 4. Generuj pliki --------------------------------------------------------
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

# Escape znaków specjalnych dla replacement-stringa sed: \, &, |
# (| jest naszym delimiterem; \ i & mają znaczenie w replacement-stringu).
# Bez tego hasło zawierające np. '|' rozjedzie składnię sed.
sed_escape() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# Mapowanie placeholderów do zmiennych. Każdy template-specific.
render_lhg() {
    sed \
        -e "s|__PLACEHOLDER_ADMIN_PASSWORD__|$(sed_escape "$LHG_ADMIN_PASSWORD")|g" \
        -e "s|__PLACEHOLDER_HAP_ETHER1_MAC__|$(sed_escape "$HAP_ETHER1_MAC")|g" \
        -e "s|__PLACEHOLDER_APN__|$(sed_escape "$APN")|g" \
        "$TEMPLATES_DIR/1-lhg-passthrough.rsc"
}

render_hap() {
    sed \
        -e "s|__PLACEHOLDER_ADMIN_PASSWORD__|$(sed_escape "$HAP_ADMIN_PASSWORD")|g" \
        -e "s|__PLACEHOLDER_PRIV_WIFI_PASSWORD__|$(sed_escape "$PRIV_WIFI_PASSWORD")|g" \
        -e "s|__PLACEHOLDER_CAMS_WIFI_PASSWORD__|$(sed_escape "$CAMS_WIFI_PASSWORD")|g" \
        "$TEMPLATES_DIR/2-hap-router.rsc"
}

render_cap() {
    local identity="$1" admin_pwd="$2"
    sed \
        -e "s|__PLACEHOLDER_IDENTITY__|$(sed_escape "$identity")|g" \
        -e "s|__PLACEHOLDER_ADMIN_PASSWORD__|$(sed_escape "$admin_pwd")|g" \
        "$TEMPLATES_DIR/3-cap-light-config.rsc"
}

# --- LHG ---
out_lhg="$OUT_DIR/1-lhg-passthrough.rsc"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY: render LHG -> $out_lhg"
else
    render_lhg > "$out_lhg"
    chmod 600 "$out_lhg"
    echo "OK: $out_lhg"
fi

# --- hAP ---
out_hap="$OUT_DIR/2-hap-router.rsc"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY: render hAP -> $out_hap"
else
    render_hap > "$out_hap"
    chmod 600 "$out_hap"
    echo "OK: $out_hap"
fi

# --- cAP × 2 ---
out_cap1="$OUT_DIR/3-cap-pietro1.rsc"
out_cap2="$OUT_DIR/3-cap-pietro2.rsc"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY: render cAP1 -> $out_cap1"
    echo "DRY: render cAP2 -> $out_cap2"
else
    render_cap "$CAP1_IDENTITY" "$CAP1_ADMIN_PASSWORD" > "$out_cap1"
    render_cap "$CAP2_IDENTITY" "$CAP2_ADMIN_PASSWORD" > "$out_cap2"
    chmod 600 "$out_cap1" "$out_cap2"
    echo "OK: $out_cap1"
    echo "OK: $out_cap2"
fi

# --- 5. Final check: czy wszystkie placeholdery zostały podmienione ---------
if [[ $DRY_RUN -eq 0 ]]; then
    leftover=$(grep -l "__PLACEHOLDER_" "$OUT_DIR"/*.rsc 2>/dev/null || true)
    if [[ -n "$leftover" ]]; then
        echo "BŁĄD: nie podmieniono wszystkich placeholderów w:" >&2
        echo "$leftover" >&2
        grep -n "__PLACEHOLDER_" "$OUT_DIR"/*.rsc >&2
        exit 3
    fi
    echo ""
    echo "Gotowe. Pliki w $OUT_DIR/ - wgraj odpowiedni do każdego urządzenia."
fi
