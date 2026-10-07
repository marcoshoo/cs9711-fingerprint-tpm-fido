#!/bin/bash
# ============================================================================
# CS9711 Quick Rebuild & Reinstall
# ============================================================================
# Recompila o driver libfprint-CS9711 aplicando novo intervalo (retry delay)
# ou após atualizações de sistema.
# ============================================================================

set -eo pipefail

# Detect language: English is default, switch to Portuguese only if system locale is pt_*
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}" in
    pt*|pt_BR*|pt_PT*) LANG_IS_PT=1 ;;
    *)                 LANG_IS_PT=0 ;;
esac

_t() {
    if [ "$LANG_IS_PT" -eq 1 ]; then
        echo "$2"
    else
        echo "$1"
    fi
}

if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

REAL_USER="${SUDO_USER:-${USER}}"
if [ "$REAL_USER" = "root" ] && [ -n "${PKEXEC_UID:-}" ]; then
    REAL_USER=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
fi
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

CACHE_DIR="/var/lib/cs9711-fingerprint"
mkdir -p "$CACHE_DIR"

RETRY_DELAY="${1:-}"
if [ -z "$RETRY_DELAY" ] && [ -f "$CACHE_DIR/retry_delay" ]; then
    RETRY_DELAY=$(cat "$CACHE_DIR/retry_delay" 2>/dev/null || echo "1500")
fi
[ -z "$RETRY_DELAY" ] && RETRY_DELAY=1500

echo "$(_t "=== CS9711 Driver Rebuild ===" "=== Recompilação do Driver CS9711 ===")"
echo "$(_t "Retry delay" "Intervalo de nova tentativa"): ${RETRY_DELAY}ms"

# 1. Localizar ou obter o código-fonte do driver
SRC_DIR="$CACHE_DIR/src"
if [ ! -d "$SRC_DIR/libfprint/drivers/cs9711" ]; then
    echo "$(_t "[1/4] Preparing driver source code..." "[1/4] Preparando código-fonte do driver...")"
    if [ -d "$REAL_HOME/drivers/chipsailing-cs9711-fingerprint-linux/libfprint-CS9711" ]; then
        mkdir -p "$SRC_DIR"
        cp -a "$REAL_HOME/drivers/chipsailing-cs9711-fingerprint-linux/libfprint-CS9711"/. "$SRC_DIR"/
    else
        mkdir -p "$SRC_DIR"
        git clone --depth 1 https://github.com/archeYR/libfprint-CS9711.git "$SRC_DIR" >/dev/null 2>&1
    fi
else
    echo "$(_t "[1/4] Using local source cache in $SRC_DIR..." "[1/4] Usando cache local do código-fonte em $SRC_DIR...")"
fi

# 2. Aplicar patches
echo "$(_t "[2/4] Applying build parameters..." "[2/4] Aplicando parâmetros de compilação...")"
CS_SRC="$SRC_DIR/libfprint/drivers/cs9711/cs9711.c"
if [ -f "$CS_SRC" ]; then
    sed -i "s/#define CS9711_DEFAULT_RESET_SLEEP.*/#define CS9711_DEFAULT_RESET_SLEEP  $RETRY_DELAY/" "$CS_SRC"
fi

SIGFM="$SRC_DIR/libfprint/sigfm/meson.build"
if [ -f "$SIGFM" ]; then
    sed -i "s/dependency('doctest', required: true)/dependency('doctest', required: false)/" "$SIGFM"
fi

# 3. Compilar
echo "$(_t "[3/4] Compiling via Meson/Ninja..." "[3/4] Compilando via Meson/Ninja...")"
cd "$SRC_DIR"
rm -rf builddir
meson setup builddir \
    -Ddrivers=cs9711 \
    -Dudev_rules=disabled \
    -Dudev_hwdb=disabled \
    -Ddoc=false \
    -Dinstalled-tests=false \
    -Dgtk-examples=false >/dev/null 2>&1
meson compile -C builddir >/dev/null 2>&1
meson install -C builddir >/dev/null 2>&1

# 4. Atualizar cache do linker e registrar persistência
echo "$(_t "[4/4] Updating linker and restarting fprintd..." "[4/4] Atualizando linker e reiniciando fprintd...")"
LIB_DIR="/usr/local/lib/x86_64-linux-gnu"
echo -e "$LIB_DIR\n/usr/local/lib" > /etc/ld.so.conf.d/99-cs9711-local.conf
ldconfig

echo "$RETRY_DELAY" > "$CACHE_DIR/retry_delay"
cp -a "$LIB_DIR"/libfprint-2.so* "$CACHE_DIR"/ 2>/dev/null || true
echo "$LIB_DIR" > "$CACHE_DIR/install-dir"

systemctl restart fprintd 2>/dev/null || true

echo "$(_t "Success: CS9711 driver rebuilt and active (${RETRY_DELAY}ms)!" "Sucesso: Driver CS9711 recompilado e ativo (${RETRY_DELAY}ms)!")"
