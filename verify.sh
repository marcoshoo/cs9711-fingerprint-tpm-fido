#!/usr/bin/env bash
# ============================================================================
# CS9711 Fingerprint & TPM-FIDO2 Health Check / Verifier
# ============================================================================
# Checks all hardware, kernel modules, drivers, PAM rules, udev permissions,
# systemd services and desktop integration.
# ============================================================================

set -u

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

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

check_ok() {
    echo -e "  [${GREEN}✓ OK${NC}] $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

check_warn() {
    echo -e "  [${YELLOW}! $(_t "WARNING" "AVISO")${NC}] $1"
    [ -n "${2:-}" ] && echo -e "         ${YELLOW}↳ $2${NC}"
    WARN_COUNT=$((WARN_COUNT + 1))
}

check_fail() {
    echo -e "  [${RED}✗ $(_t "FAIL" "FALHA")${NC}] $1"
    [ -n "${2:-}" ] && echo -e "         ${RED}↳ $2${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

TARGET_USER="${SUDO_USER:-${USER}}"
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || id -u)

echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}   $(_t "CS9711 & TPM-FIDO2 Diagnostics (Ubuntu 26.04)" "Diagnóstico de Suporte CS9711 & TPM-FIDO2 (Ubuntu 26.04)")${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "$(_t "Target user" "Usuário verificado"): ${BLUE}$TARGET_USER${NC} (UID $TARGET_UID)"
echo ""

# 1. Hardware USB
echo -e "${BOLD}[1/8] $(_t "USB Hardware Verification" "Verificação do Hardware USB")${NC}"
USB_FOUND=0
for f in /sys/bus/usb/devices/*/idVendor; do
    [ -r "$f" ] || continue
    if [ "$(cat "$f" 2>/dev/null)" = "2541" ] && [ "$(cat "${f%idVendor}idProduct" 2>/dev/null)" = "0236" ]; then
        USB_FOUND=1
        break
    fi
done
if [ "$USB_FOUND" -eq 1 ] || (command -v lsusb >/dev/null 2>&1 && lsusb | grep -qi "2541:0236"); then
    check_ok "$(_t "Chipsailing CS9711 biometric scanner detected on USB bus (2541:0236)" "Leitor biométrico Chipsailing CS9711 detectado no barramento USB (2541:0236)")"
else
    check_fail "$(_t "Chipsailing CS9711 scanner not found on USB" "Leitor Chipsailing CS9711 não encontrado no USB")" "$(_t "Ensure the device is connected." "Certifique-se de que o dispositivo está conectado.")"
fi

# 2. Kernel e Módulos
echo -e "${BOLD}[2/8] $(_t "Kernel & UHID Module" "Kernel e Módulo UHID")${NC}"
if lsmod | grep -qw "uhid"; then
    check_ok "$(_t "Kernel module 'uhid' is loaded" "Módulo de kernel 'uhid' está carregado")"
else
    check_fail "$(_t "Kernel module 'uhid' is NOT loaded" "Módulo de kernel 'uhid' NÃO está carregado")" "$(_t "Run: sudo modprobe uhid" "Execute: sudo modprobe uhid")"
fi

if [ -f /etc/modules-load.d/uhid.conf ] && grep -qw "uhid" /etc/modules-load.d/uhid.conf; then
    check_ok "$(_t "Auto-loading of 'uhid' configured in /etc/modules-load.d/uhid.conf" "Carregamento automático de 'uhid' configurado em /etc/modules-load.d/uhid.conf")"
else
    check_warn "$(_t "Persistent configuration in /etc/modules-load.d/uhid.conf missing" "Configuração persistente em /etc/modules-load.d/uhid.conf ausente")"
fi

# 3. Dispositivos e Permissões (UDEV & Grupos)
echo -e "${BOLD}[3/8] $(_t "Devices & UDEV Rules" "Dispositivos e Regras UDEV")${NC}"
if [ -c /dev/tpmrm0 ]; then
    TPM_GRP=$(stat -c '%G' /dev/tpmrm0 2>/dev/null || echo "")
    TPM_MOD=$(stat -c '%a' /dev/tpmrm0 2>/dev/null || echo "")
    if [ "$TPM_GRP" = "tss" ] && [ "$TPM_MOD" = "660" ]; then
        check_ok "$(_t "Permissions for /dev/tpmrm0 correct (tss:0660)" "Permissões de /dev/tpmrm0 corretas (tss:0660)")"
    else
        check_warn "$(_t "Permissions for /dev/tpmrm0: group=$TPM_GRP, mode=$TPM_MOD (expected tss:660)" "Permissões de /dev/tpmrm0: grupo=$TPM_GRP, mode=$TPM_MOD (esperado tss:660)")"
    fi
else
    check_warn "$(_t "/dev/tpmrm0 not found (physical TPM may be disabled in BIOS)" "/dev/tpmrm0 não encontrado (TPM físico pode estar desabilitado na BIOS)")"
fi

if [ -c /dev/uhid ]; then
    UHID_GRP=$(stat -c '%G' /dev/uhid 2>/dev/null || echo "")
    UHID_MOD=$(stat -c '%a' /dev/uhid 2>/dev/null || echo "")
    if [ "$UHID_GRP" = "plugdev" ] && [ "$UHID_MOD" = "660" ]; then
        check_ok "$(_t "Permissions for /dev/uhid correct (plugdev:0660)" "Permissões de /dev/uhid corretas (plugdev:0660)")"
    else
        check_warn "$(_t "Permissions for /dev/uhid: group=$UHID_GRP, mode=$UHID_MOD (expected plugdev:660)" "Permissões de /dev/uhid: grupo=$UHID_GRP, mode=$UHID_MOD (esperado plugdev:660)")"
    fi
else
    check_fail "$(_t "/dev/uhid does not exist on the system" "/dev/uhid não existe no sistema")"
fi

# Grupos do usuário
USER_GROUPS=$(id -Gn "$TARGET_USER" 2>/dev/null || echo "")
if echo "$USER_GROUPS" | grep -qw "tss"; then
    check_ok "$(_t "User '$TARGET_USER' belongs to 'tss' group" "Usuário '$TARGET_USER' pertence ao grupo 'tss'")"
else
    check_fail "$(_t "User '$TARGET_USER' does NOT belong to 'tss' group" "Usuário '$TARGET_USER' NÃO pertence ao grupo 'tss'")" "$(_t "Run: sudo usermod -aG tss $TARGET_USER" "Execute: sudo usermod -aG tss $TARGET_USER")"
fi

if echo "$USER_GROUPS" | grep -qw "plugdev"; then
    check_ok "$(_t "User '$TARGET_USER' belongs to 'plugdev' group" "Usuário '$TARGET_USER' pertence ao grupo 'plugdev'")"
else
    check_fail "$(_t "User '$TARGET_USER' does NOT belong to 'plugdev' group" "Usuário '$TARGET_USER' NÃO pertence ao grupo 'plugdev'")" "$(_t "Run: sudo usermod -aG plugdev $TARGET_USER" "Execute: sudo usermod -aG plugdev $TARGET_USER")"
fi

# 4. Biblioteca libfprint e Driver CS9711
echo -e "${BOLD}[4/8] $(_t "libfprint Driver CS9711" "Driver libfprint CS9711")${NC}"
ACTIVE_LIB=$(ldconfig -p 2>/dev/null | awk '/libfprint-2\.so\.2 /{print $NF; exit}')
if [ -n "$ACTIVE_LIB" ] && [ -f "$ACTIVE_LIB" ]; then
    if strings "$ACTIVE_LIB" 2>/dev/null | grep -qi "cs9711"; then
        check_ok "$(_t "Active libfprint library contains cs9711 driver ($ACTIVE_LIB)" "Biblioteca libfprint ativa contém o driver cs9711 ($ACTIVE_LIB)")"
    else
        check_fail "$(_t "Active libfprint library ($ACTIVE_LIB) does NOT contain cs9711 driver" "Biblioteca libfprint ativa ($ACTIVE_LIB) NÃO contém o driver cs9711")" "$(_t "Stock system library is shadowing patched version." "A biblioteca padrão do sistema está sobrepondo a versão customizada.")"
    fi
else
    check_fail "$(_t "libfprint-2.so.2 not found by ldconfig" "libfprint-2.so.2 não encontrada pelo ldconfig")"
fi

# 5. Daemon fprintd e Biometria
echo -e "${BOLD}[5/8] $(_t "fprintd Daemon & Recognition" "Daemon fprintd e Reconhecimento")${NC}"
if systemctl is-active --quiet fprintd 2>/dev/null; then
    check_ok "$(_t "Service fprintd.service is active" "Serviço fprintd.service está ativo")"
else
    check_ok "$(_t "Service fprintd.service available (D-Bus on-demand activation)" "Serviço fprintd.service disponível (ativação sob demanda via D-Bus)")"
fi

FPRINT_DEV=$(fprintd-list "$TARGET_USER" 2>&1 || true)
if echo "$FPRINT_DEV" | grep -qi "CS9711\|9711\|chipsailing"; then
    check_ok "$(_t "fprintd recognizes Chipsailing CS9711 fingerprint reader" "fprintd reconhece o leitor biométrico Chipsailing CS9711")"
    if echo "$FPRINT_DEV" | grep -qE '^\s*-\s*#[0-9]+:'; then
        ENROLLED_FINGERS=$(echo "$FPRINT_DEV" | grep -E '^\s*-\s*#[0-9]+:' | sed 's/^[ \t]*//' | tr '\n' ', ' | sed 's/,$//')
        check_ok "$(_t "Enrolled fingerprints for $TARGET_USER: $ENROLLED_FINGERS" "Digitais cadastradas para $TARGET_USER: $ENROLLED_FINGERS")"
    else
        check_warn "$(_t "No fingerprints enrolled for user $TARGET_USER" "Nenhuma digital cadastrada para o usuário $TARGET_USER")" "$(_t "Enroll with: fprintd-enroll" "Cadastre com: fprintd-enroll")"
    fi
else
    check_fail "$(_t "fprintd does not list CS9711 scanner" "fprintd não lista o sensor CS9711")" "$(_t "Output: $FPRINT_DEV" "Saída: $FPRINT_DEV")"
fi

# 6. Autenticação PAM
echo -e "${BOLD}[6/8] $(_t "PAM Configuration (sudo, polkit, gdm)" "Configuração PAM (sudo, polkit, gdm)")${NC}"
GDM_PAM="/etc/pam.d/gdm-password"
[ -f /etc/pam.d/gdm-fingerprint ] && GDM_PAM="/etc/pam.d/gdm-fingerprint"
PAM_FILES=("/etc/pam.d/sudo" "/etc/pam.d/polkit-1" "$GDM_PAM")
for pf in "${PAM_FILES[@]}"; do
    if [ -f "$pf" ] && grep -q "pam_fprintd.so" "$pf"; then
        check_ok "$(_t "Biometric authentication configured in $pf" "Autenticação biométrica configurada em $pf")"
    else
        check_warn "$(_t "Biometrics not configured in $pf" "Biometria não configurada em $pf")"
    fi
done

# 7. Proteção contra Atualizações do APT
echo -e "${BOLD}[7/8] $(_t "Driver Protection against 'apt upgrade'" "Proteção do Driver contra 'apt upgrade'")${NC}"
if [ -x /usr/local/bin/cs9711-update-guard ]; then
    check_ok "$(_t "Guard script installed (/usr/local/bin/cs9711-update-guard)" "Script de guarda instalado (/usr/local/bin/cs9711-update-guard)")"
else
    check_warn "$(_t "Guard script /usr/local/bin/cs9711-update-guard missing or not executable" "Guarda /usr/local/bin/cs9711-update-guard ausente ou sem permissão de execução")"
fi

if [ -f /etc/apt/apt.conf.d/99-cs9711-guard ]; then
    check_ok "$(_t "APT hook configured (/etc/apt/apt.conf.d/99-cs9711-guard)" "Hook do APT configurado (/etc/apt/apt.conf.d/99-cs9711-guard)")"
else
    check_warn "$(_t "APT hook /etc/apt/apt.conf.d/99-cs9711-guard missing" "Hook do APT /etc/apt/apt.conf.d/99-cs9711-guard ausente")"
fi

if [ -d /var/lib/cs9711-fingerprint ] && [ -f /var/lib/cs9711-fingerprint/install-dir ]; then
    check_ok "$(_t "Driver restore cache present in /var/lib/cs9711-fingerprint" "Cache de restauração da biblioteca presente em /var/lib/cs9711-fingerprint")"
else
    check_warn "$(_t "Driver cache in /var/lib/cs9711-fingerprint incomplete" "Cache do driver em /var/lib/cs9711-fingerprint incompleto")"
fi

# 8. TPM-FIDO2 e Atalho Desktop
echo -e "${BOLD}[8/8] $(_t "TPM-FIDO2 Service & Desktop Shortcut" "Serviço TPM-FIDO2 e Atalho Desktop")${NC}"
if command -v tpm-fido >/dev/null 2>&1 || [ -x "$HOME/.local/bin/tpm-fido" ] || [ -x "/usr/local/bin/tpm-fido" ] || [ -x "$HOME/bin/tpm-fido" ]; then
    check_ok "$(_t "'tpm-fido' binary installed on the system" "Binário 'tpm-fido' instalado no sistema")"
else
    check_fail "$(_t "'tpm-fido' binary not found in PATH, ~/.local/bin or /usr/local/bin" "Binário 'tpm-fido' não encontrado em PATH, ~/.local/bin ou /usr/local/bin")"
fi

# Systemd user check
XDG_DIR="/run/user/$TARGET_UID"
if [ -d "$XDG_DIR" ]; then
    if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$XDG_DIR" systemctl --user is-active --quiet tpm-fido.service 2>/dev/null; then
        check_ok "$(_t "Systemd user service 'tpm-fido.service' active and running" "Serviço systemd de usuário 'tpm-fido.service' ativo e em execução")"
    else
        check_warn "$(_t "Systemd service 'tpm-fido.service' inactive or not loaded" "Serviço systemd 'tpm-fido.service' inativo ou não carregado")" "$(_t "Start with: systemctl --user start tpm-fido.service" "Inicie com: systemctl --user start tpm-fido.service")"
    fi
else
    check_warn "$(_t "Active user session not detected in /run/user/$TARGET_UID for service test" "Sessão de usuário ativa não detectada em /run/user/$TARGET_UID para teste do serviço")"
fi

# Desktop & Icon
DESK_EXISTS=0
[ -f /usr/share/applications/cs9711-manager.desktop ] || [ -f "$HOME/.local/share/applications/cs9711-manager.desktop" ] && DESK_EXISTS=1
ICON_EXISTS=0
[ -f /usr/share/icons/hicolor/256x256/apps/cs9711-manager.png ] || [ -f /usr/share/pixmaps/cs9711-manager.png ] && ICON_EXISTS=1

if [ "$DESK_EXISTS" -eq 1 ]; then
    check_ok "$(_t "Application menu shortcut 'cs9711-manager.desktop' installed" "Atalho do menu de aplicativos 'cs9711-manager.desktop' instalado")"
else
    check_warn "$(_t "Shortcut 'cs9711-manager.desktop' not found" "Atalho 'cs9711-manager.desktop' não encontrado")"
fi

if [ "$ICON_EXISTS" -eq 1 ]; then
    check_ok "$(_t "Transparent 256x256 PNG icon installed in system XDG directories" "Ícone PNG transparente 256x256 instalado nos diretórios XDG do sistema")"
else
    check_warn "$(_t "PNG icon not found in /usr/share/icons or /usr/share/pixmaps" "Ícone PNG não encontrado em /usr/share/icons ou /usr/share/pixmaps")"
fi

# Resumo
echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "$(_t "Result: ${GREEN}$PASS_COUNT passed${NC} | ${YELLOW}$WARN_COUNT warnings${NC} | ${RED}$FAIL_COUNT failed${NC}" "Resultado: ${GREEN}$PASS_COUNT aprovados${NC} | ${YELLOW}$WARN_COUNT avisos${NC} | ${RED}$FAIL_COUNT falhas${NC}")"
echo -e "${BOLD}================================================================${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
