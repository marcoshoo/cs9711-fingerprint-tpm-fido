#!/usr/bin/env bash
# ============================================================================
# CS9711 & TPM-FIDO2 — Uninstallation & Rollback Script
# ============================================================================
# Removes all configurations, udev rules, APT hooks, user services,
# and drivers installed by the CS9711 package.
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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "  [${BLUE}>>${NC}] $1"; }
ok()   { echo -e "  [${GREEN}✓ OK${NC}] $1"; }
warn() { echo -e "  [${YELLOW}! $(_t "WARNING" "AVISO")${NC}] $1"; }

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}$(_t "This script must be run as root." "Este script precisa ser executado como root.")${NC}"
    echo -e "$(_t "Re-running with sudo..." "Reexecutando com sudo...")"
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
echo -e "${BOLD}       $(_t "CS9711 & TPM-FIDO2 Uninstallation & Rollback" "Desinstalação e Rollback CS9711 & TPM-FIDO2")              ${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "$(_t "Target user" "Usuário alvo"): ${BLUE}$REAL_USER${NC}"
echo ""

# 1. Parar e remover serviço TPM-FIDO2
info "$(_t "Stopping and disabling TPM-FIDO2 service..." "Parando e desabilitando serviço TPM-FIDO2...")"
if [ -d "/run/user/$REAL_UID" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" systemctl --user stop tpm-fido.service 2>/dev/null || true
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" systemctl --user disable tpm-fido.service 2>/dev/null || true
fi
rm -f "$REAL_HOME/.config/systemd/user/tpm-fido.service"
if [ -d "/run/user/$REAL_UID" ]; then
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" systemctl --user daemon-reload 2>/dev/null || true
fi
rm -f /usr/local/bin/tpm-fido "$REAL_HOME/.local/bin/tpm-fido" "$REAL_HOME/bin/tpm-fido"
rmdir "$REAL_HOME/bin" 2>/dev/null || true
ok "$(_t "TPM-FIDO2 service and binaries removed" "Serviço e binários TPM-FIDO2 removidos")"

# 2. Reverter configurações PAM
info "$(_t "Reverting biometric PAM rules (/etc/pam.d)..." "Revertendo regras biométricas no PAM (/etc/pam.d)...")"
for f in /etc/pam.d/*; do
    [ -f "$f" ] || continue
    if grep -q "# cs9711-managed" "$f"; then
        sed -i '/# cs9711-managed/d' "$f"
        ok "$(_t "Rules removed from $f" "Regras removidas de $f")"
    fi
done

# 3. Remover regras UDEV e módulos
info "$(_t "Removing UDEV rules and reloading..." "Removendo regras UDEV e recarregando...")"
rm -f /etc/udev/rules.d/70-tpm-permissions.rules
rm -f /etc/udev/rules.d/90-tpm-fido-uhid.rules
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true
ok "$(_t "UDEV rules removed" "Regras UDEV removidas")"

# 4. Remover APT Guard
info "$(_t "Removing APT update guard..." "Removendo guarda de atualizações do APT...")"
rm -f /etc/apt/apt.conf.d/99-cs9711-guard
rm -f /usr/local/bin/cs9711-update-guard
rm -rf /var/lib/cs9711-fingerprint
ok "$(_t "APT guard hook and cache removed" "Hook e cache do APT guard removidos")"

# 5. Remover GUI Manager e Atalhos Desktop
info "$(_t "Removing GUI manager and desktop shortcuts..." "Removendo aplicativo gráfico e atalhos...")"
rm -f /usr/local/bin/cs9711-manager
rm -rf /usr/local/share/cs9711-manager
rm -f /usr/share/applications/cs9711-manager.desktop
rm -f "$REAL_HOME/.local/share/applications/cs9711-manager.desktop"
rm -f /usr/share/icons/hicolor/256x256/apps/cs9711-manager.png
rm -f /usr/share/pixmaps/cs9711-manager.png
gtk-update-icon-cache -f -q /usr/share/icons/hicolor 2>/dev/null || true
ok "$(_t "Shortcuts and icons removed" "Atalhos e ícones removidos")"

# 6. Remover Driver customizado e restaurar fprintd
info "$(_t "Removing custom driver from /usr/local/lib..." "Removendo driver customizado de /usr/local/lib...")"
rm -f /etc/ld.so.conf.d/99-cs9711-local.conf /etc/ld.so.conf.d/00-cs9711-local.conf
rm -f /usr/local/lib/x86_64-linux-gnu/libfprint-2.so*
rm -f /usr/local/lib/libfprint-2.so*
ldconfig 2>/dev/null || true

if dpkg -s cs9711-fingerprint >/dev/null 2>&1; then
    info "$(_t "Removing 'cs9711-fingerprint' package registration from APT/dpkg..." "Removendo registro do pacote 'cs9711-fingerprint' do APT/dpkg...")"
    dpkg -P cs9711-fingerprint >/dev/null 2>&1 || true
fi

info "$(_t "Restarting fprintd service..." "Reiniciando serviço fprintd...")"
systemctl restart fprintd 2>/dev/null || true
ok "$(_t "Custom driver uninstalled and fprintd restarted" "Driver customizado desinstalado e fprintd reiniciado")"

echo ""
echo -e "${GREEN}${BOLD}$(_t "Uninstallation completed successfully!" "Desinstalação concluída com sucesso!")${NC}"
echo ""
