#!/usr/bin/env bash
# ============================================================================
# Chipsailing CS9711 & TPM-FIDO2 — Master Installer (Ubuntu 26.04)
# ============================================================================
# Instala o suporte biométrico completo:
#  - Driver libfprint com suporte ao Chipsailing CS9711 (USB ID 2541:0236)
#  - Integração PAM para sudo, login e polkit
#  - Proteção automática contra substituição por 'apt upgrade'
#  - Módulo uhid, regras udev e permissões TPM (tss) e HID (plugdev)
#  - TPM-FIDO2 compilado com patch para silenciar popups redundantes
#  - Serviço de usuário systemd 'tpm-fido.service' para Passkeys/WebAuthn
#  - Interface gráfica 'cs9711-manager' com ícone PNG 256x256 portátil
# ============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "  [${BLUE}>>${NC}] $1"; }
ok()   { echo -e "  [${GREEN}✓ OK${NC}] $1"; }
warn() { echo -e "  [${YELLOW}! AVISO${NC}] $1"; }
fail() { echo -e "  [${RED}✗ ERRO${NC}] $1"; exit 1; }

# Parse flags
SILENT_MODE=1
DO_VERIFY_ONLY=0

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "Uso: sudo ./install.sh [OPÇÕES]"
            echo ""
            echo "Opções:"
            echo "  -y, --silent     Execução não-interativa e silenciosa (padrão)"
            echo "  --verify         Executa o diagnóstico pós-instalação (verify.sh)"
            echo "  --uninstall      Remove e reverte todas as modificações (uninstall.sh)"
            echo "  -h, --help       Mostra esta mensagem de ajuda"
            exit 0
            ;;
        --verify)
            exec "$SCRIPT_DIR/verify.sh"
            ;;
        --uninstall)
            exec "$SCRIPT_DIR/uninstall.sh"
            ;;
        -y|--silent)
            SILENT_MODE=1
            ;;
    esac
done

# Checar privilégios de root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${YELLOW}Privilégios de superusuário necessários. Elevando via sudo...${NC}"
    exec sudo "$0" "$@"
fi

REAL_USER="${SUDO_USER:-$USER}"
if [ "$REAL_USER" = "root" ] && [ -n "${PKEXEC_UID:-}" ]; then
    REAL_USER=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
fi
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_UID=$(id -u "$REAL_USER")

echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}   Instalador Unificado: CS9711 Biometria & TPM-FIDO2           ${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "Usuário do sistema: ${BLUE}$REAL_USER${NC} | Diretório: ${BLUE}$REAL_HOME${NC}"
echo ""

# ----------------------------------------------------------------------------
# 1. Pré-checagens de Ambiente e Hardware
# ----------------------------------------------------------------------------
info "[1/8] Verificando compatibilidade e hardware..."

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    fail "Arquitetura $ARCH não suportada diretamente. Requer x86_64."
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    ok "Sistema detectado: $PRETTY_NAME ($ID)"
else
    warn "Não foi possível ler /etc/os-release."
fi

# Detectar leitor no USB (sysfs ou lsusb)
cs9711_detected() {
    for f in /sys/bus/usb/devices/*/idVendor; do
        [ -r "$f" ] || continue
        if [ "$(cat "$f" 2>/dev/null)" = "2541" ] && [ "$(cat "${f%idVendor}idProduct" 2>/dev/null)" = "0236" ]; then
            return 0
        fi
    done
    command -v lsusb >/dev/null 2>&1 && lsusb | grep -qi "2541:0236"
}

if cs9711_detected; then
    ok "Leitor Chipsailing CS9711 (2541:0236) detectado no USB."
else
    warn "Leitor CS9711 não encontrado no USB neste momento. A instalação continuará."
fi

# ----------------------------------------------------------------------------
# 2. Instalação de Dependências de Sistema
# ----------------------------------------------------------------------------
info "[2/8] Instalando dependências do sistema via APT..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq \
    build-essential git meson ninja-build golang golang-go pkg-config \
    libfprint-2-dev libglib2.0-dev libgusb-dev libpixman-1-dev \
    libcairo2-dev libssl-dev libopencv-dev doctest-dev \
    gobject-introspection libgirepository1.0-dev \
    fprintd libpam-fprintd tpm-udev libtss2-dev \
    python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 >/dev/null

ok "Dependências essenciais instaladas."

# ----------------------------------------------------------------------------
# 3. Driver CS9711 e Guarda de Atualização
# ----------------------------------------------------------------------------
info "[3/8] Instalando driver libfprint customizado para CS9711..."

LIB_DIR="/usr/local/lib/x86_64-linux-gnu"
mkdir -p "$LIB_DIR"

# Prioridade: Pacote local .deb pré-compilado, caso disponível
DEB_PACKAGE=$(ls "$SCRIPT_DIR/packages"/cs9711-fingerprint_*.deb 2>/dev/null | head -1 || true)
DRIVER_INSTALLED=0

if [ -n "$DEB_PACKAGE" ] && [ -f "$DEB_PACKAGE" ]; then
    info "Instalando pacote local $DEB_PACKAGE..."
    dpkg -i "$DEB_PACKAGE" >/dev/null 2>&1 && DRIVER_INSTALLED=1 || true
fi

# Fallback: Compilação caso o .deb não esteja presente ou falhe
if [ "$DRIVER_INSTALLED" -eq 0 ]; then
    info "Compilando libfprint-CS9711 a partir do código-fonte..."
    BUILD_DIR="/tmp/cs9711-build-$$"
    rm -rf "$BUILD_DIR"
    git clone --depth 1 https://github.com/archeYR/libfprint-CS9711.git "$BUILD_DIR" >/dev/null 2>&1
    
    # Patch de retry delay
    CS_SRC="$BUILD_DIR/libfprint/drivers/cs9711/cs9711.c"
    if [ -f "$CS_SRC" ]; then
        sed -i 's/#define CS9711_DEFAULT_RESET_SLEEP.*/#define CS9711_DEFAULT_RESET_SLEEP  1500/' "$CS_SRC"
    fi
    
    # Ajustes meson
    SIGFM="$BUILD_DIR/libfprint/sigfm/meson.build"
    if [ -f "$SIGFM" ]; then
        sed -i "s/dependency('doctest', required: true)/dependency('doctest', required: false)/" "$SIGFM"
    fi

    meson setup "$BUILD_DIR/builddir" "$BUILD_DIR" \
        -Ddrivers=cs9711 \
        -Dudev_rules=disabled \
        -Dudev_hwdb=disabled \
        -Ddoc=false \
        -Dinstalled-tests=false \
        -Dgtk-examples=false >/dev/null 2>&1
    meson compile -C "$BUILD_DIR/builddir" >/dev/null 2>&1
    meson install -C "$BUILD_DIR/builddir" >/dev/null 2>&1
    rm -rf "$BUILD_DIR"
fi

# Assegurar precedência no linker (/etc/ld.so.conf.d/)
echo -e "/usr/local/lib/x86_64-linux-gnu\n/usr/local/lib" > /etc/ld.so.conf.d/99-cs9711-local.conf
ldconfig

# Cache do driver para restauração automática após upgrades do APT
CACHE_DIR="/var/lib/cs9711-fingerprint"
mkdir -p "$CACHE_DIR"
cp -a "$LIB_DIR"/libfprint-2.so* "$CACHE_DIR"/ 2>/dev/null || true
echo "$LIB_DIR" > "$CACHE_DIR/install-dir"

# Instalar hook e script do Update Guard
cp -a "$SCRIPT_DIR/helpers/cs9711-update-guard" /usr/local/bin/cs9711-update-guard
chmod 755 /usr/local/bin/cs9711-update-guard
cp -a "$SCRIPT_DIR/helpers/99-cs9711-guard" /etc/apt/apt.conf.d/99-cs9711-guard

ok "Driver CS9711 e APT Update Guard configurados com sucesso."

# ----------------------------------------------------------------------------
# 4. Configuração do PAM para Biometria
# ----------------------------------------------------------------------------
info "[4/8] Configurando PAM para autenticação biométrica..."

MARK="# cs9711-managed"
LINE="auth\tsufficient\tpam_fprintd.so\tmax-tries=7 timeout=30\t$MARK"

add_pam_rule() {
    local target="$1"
    [ -f "$target" ] || return 0
    grep -q "$MARK" "$target" && return 0
    awk -v ins="$LINE" '
        { lines[NR]=$0
          if (!anchor && (($1=="@include" && $2 ~ /auth/) ||
                          ($1=="auth" && ($2=="include" || $2=="substack")))) anchor=NR
          if ($1=="auth" && ($2=="required" || $2=="requisite")) lastreq=NR }
        END{ if (anchor) pos=anchor-1; else if (lastreq) pos=lastreq;
             else pos=(lines[1] ~ /^#/) ? 1 : 0
             for (i=1;i<=NR;i++) { if (i==pos+1) print ins; print lines[i] }
             if (pos>=NR) print ins }' "$target" > "$target.tmp"
    mv "$target.tmp" "$target"
    chmod 644 "$target"
}

add_pam_rule "/etc/pam.d/sudo"
add_pam_rule "/etc/pam.d/sudo-i"
add_pam_rule "/etc/pam.d/polkit-1"

# Limpeza de pam_fprintd em common-auth para evitar duplicações
for cf in /etc/pam.d/common-auth /etc/pam.d/common-auth-pc; do
    [ -f "$cf" ] && sed -i '/pam_fprintd\.so/d' "$cf" 2>/dev/null || true
done

ok "Regras do PAM adicionadas com proteção contra lockouts."

# ----------------------------------------------------------------------------
# 5. Módulo UHID, Regras UDEV e Grupos
# ----------------------------------------------------------------------------
info "[5/8] Configurando módulo 'uhid' e regras de permissões UDEV..."

# Módulo uhid persistente
mkdir -p /etc/modules-load.d
echo "uhid" > /etc/modules-load.d/uhid.conf
modprobe uhid 2>/dev/null || true

# Regras UDEV
cp -a "$SCRIPT_DIR/rules/70-tpm-permissions.rules" /etc/udev/rules.d/70-tpm-permissions.rules
cp -a "$SCRIPT_DIR/rules/90-tpm-fido-uhid.rules" /etc/udev/rules.d/90-tpm-fido-uhid.rules

udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

# Adicionar usuário aos grupos 'tss' e 'plugdev'
usermod -aG tss "$REAL_USER"
usermod -aG plugdev "$REAL_USER"

ok "Permissões de UDEV e grupos 'tss' e 'plugdev' associados ao usuário $REAL_USER."

# ----------------------------------------------------------------------------
# 6. Compilação e Instalação do TPM-FIDO2 (com patch de notify-send)
# ----------------------------------------------------------------------------
info "[6/8] Compilando e configurando serviço TPM-FIDO2..."

FIDO_BUILD_DIR="/tmp/tpm-fido-build-$$"
rm -rf "$FIDO_BUILD_DIR"

# Prioridade híbrida: se o usuário já tiver o repo clonado em ~/drivers, usa como base
if [ -d "$REAL_HOME/drivers/tpm-fido2-thinkpad-linux/.git" ]; then
    info "Utilizando repositório local existente em $REAL_HOME/drivers/tpm-fido2-thinkpad-linux..."
    cp -r "$REAL_HOME/drivers/tpm-fido2-thinkpad-linux" "$FIDO_BUILD_DIR"
else
    info "Clonando tpm-fido2-thinkpad-linux do GitHub..."
    git clone --depth 1 https://github.com/mc256/tpm-fido2-thinkpad-linux.git "$FIDO_BUILD_DIR" >/dev/null 2>&1
fi

# Aplicar o patch para silenciar o popup redundante
cd "$FIDO_BUILD_DIR"
if patch -p1 --dry-run < "$SCRIPT_DIR/patches/tpm-fido-disable-notify.patch" >/dev/null 2>&1; then
    patch -p1 < "$SCRIPT_DIR/patches/tpm-fido-disable-notify.patch" >/dev/null 2>&1
    ok "Patch de notificação silenciosa aplicado com sucesso."
else
    warn "Patch de notificação já aplicado ou modificado previamente."
fi

# Compilar binário Go
if ! go build -o tpm-fido . >/dev/null 2>&1; then
    go build -o tpm-fido . || fail "Falha ao compilar o binário tpm-fido com 'go build'."
fi
ok "Binário tpm-fido compilado com sucesso."

# Instalar binário
cp -a tpm-fido /usr/local/bin/tpm-fido
chmod 755 /usr/local/bin/tpm-fido

# Manter link/cópia em ~/bin/tpm-fido para compatibilidade com configs existentes
mkdir -p "$REAL_HOME/bin"
cp -a tpm-fido "$REAL_HOME/bin/tpm-fido"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/bin"

rm -rf "$FIDO_BUILD_DIR"
cd "$SCRIPT_DIR"

# Instalar serviço systemd de usuário
USER_SYSTEMD_DIR="$REAL_HOME/.config/systemd/user"
mkdir -p "$USER_SYSTEMD_DIR"
cp -a "$SCRIPT_DIR/assets/tpm-fido.service" "$USER_SYSTEMD_DIR/tpm-fido.service"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config"

# Iniciar/Habilitar serviço systemd do usuário caso a sessão esteja ativa
if [ -d "/run/user/$REAL_UID" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" systemctl --user enable --now tpm-fido.service 2>/dev/null || true
    ok "Serviço tpm-fido.service ativado para a sessão do usuário."
else
    warn "Sessão gráfica de usuário não ativa no momento. O serviço tpm-fido será iniciado no próximo login."
fi

# ----------------------------------------------------------------------------
# 7. Interface Gráfica 'cs9711-manager' e Correção do Ícone PNG
# ----------------------------------------------------------------------------
info "[7/8] Instalando gerenciador gráfico e ícone PNG 256x256..."

APP_SHARE="/usr/local/share/cs9711-manager"
mkdir -p "$APP_SHARE"
cp -a "$SCRIPT_DIR/assets/cs9711-manager.py" "$APP_SHARE/cs9711-manager.py"
chmod 755 "$APP_SHARE/cs9711-manager.py"

# Criar wrapper em /usr/local/bin
cat > /usr/local/bin/cs9711-manager <<'EOF'
#!/bin/sh
exec python3 /usr/local/share/cs9711-manager/cs9711-manager.py "$@"
EOF
chmod 755 /usr/local/bin/cs9711-manager

# Instalar ícone PNG transparente 256x256 nos diretórios padrão do sistema
mkdir -p /usr/share/icons/hicolor/256x256/apps /usr/share/pixmaps
cp -a "$SCRIPT_DIR/assets/cs9711-manager.png" /usr/share/icons/hicolor/256x256/apps/cs9711-manager.png
cp -a "$SCRIPT_DIR/assets/cs9711-manager.png" /usr/share/pixmaps/cs9711-manager.png
gtk-update-icon-cache -f -q /usr/share/icons/hicolor 2>/dev/null || true

# Instalar atalho Desktop global
cp -a "$SCRIPT_DIR/assets/cs9711-manager.desktop" /usr/share/applications/cs9711-manager.desktop
chmod 644 /usr/share/applications/cs9711-manager.desktop

# Substituir versão local com caminhos absolutos, se existir
if [ -f "$REAL_HOME/.local/share/applications/cs9711-manager.desktop" ]; then
    cp -a "$SCRIPT_DIR/assets/cs9711-manager.desktop" "$REAL_HOME/.local/share/applications/cs9711-manager.desktop"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/applications/cs9711-manager.desktop"
fi

ok "Atalho e ícone de alta resolução registrados no sistema."

# ----------------------------------------------------------------------------
# 8. Reinicialização de Serviços e Diagnóstico Final
# ----------------------------------------------------------------------------
info "[8/8] Reiniciando serviço fprintd e rodando validação..."

systemctl restart fprintd 2>/dev/null || true
sleep 1

echo ""
# Executar verify.sh
"$SCRIPT_DIR/verify.sh"

echo ""
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}         Instalação concluída com sucesso!                      ${NC}"
echo -e "${GREEN}${BOLD}================================================================${NC}"
echo ""
echo -e "Como cadastrar suas digitais:"
echo -e "  1. Via terminal:   ${BOLD}fprintd-enroll${NC}"
echo -e "  2. Via interface:  Pesquise por '${BOLD}CS9711${NC}' no menu de aplicativos"
echo -e "                     ou execute '${BOLD}cs9711-manager${NC}'"
echo ""
echo -e "Testar autenticação de chave virtual FIDO2 (WebAuthn / Passkeys):"
echo -e "  Acesse: ${BLUE}https://webauthn.io${NC} ou ${BLUE}https://passkeys.io${NC} no seu navegador."
echo ""
