#!/usr/bin/env python3
"""
Set GNOME Login Keyring password to empty via D-Bus Secret Service API.
This enables auto-unlock on fingerprint login.

Usage: python3 set-empty-keyring-password.py
"""

import dbus
import getpass
import os
import sys

# Language detection (consistent with project standard)
LANG = os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or "en"
IS_PT = LANG.startswith("pt")

def _t(en_msg, pt_msg):
    return pt_msg if IS_PT else en_msg

# ANSI colors
GREEN = "\033[0;32m"
RED = "\033[0;31m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
BOLD = "\033[1m"
NC = "\033[0m"

SERVICE_NAME = "org.freedesktop.secrets"
SERVICE_PATH = "/org/freedesktop/secrets"
SERVICE_IFACE = "org.freedesktop.Secret.Service"
INTERNAL_IFACE = "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface"
COLLECTION_PATH = "/org/freedesktop/secrets/collection/login"

def wait_exit(code=0):
    print()
    try:
        input(_t("Press Enter to close this window...", "Pressione Enter para fechar esta janela..."))
    except (KeyboardInterrupt, EOFError):
        pass
    sys.exit(code)

def main():
    print(f"{BOLD}================================================================{NC}")
    print(f"{BOLD}  {_t('GNOME Keyring — Set Empty Password', 'Chaveiro GNOME — Configurar Senha Vazia')}           {NC}")
    print(f"{BOLD}================================================================{NC}")
    print(_t("This configures your 'login' keyring to unlock automatically",
             "Isto configura o chaveiro 'login' para desbloquear automaticamente"))
    print(_t("without asking for a password when logging in with your fingerprint.",
             "sem solicitar senha ao fazer login com a sua impressão digital."))
    print()

    # Connect to session bus
    try:
        bus = dbus.SessionBus()
        service_obj = bus.get_object(SERVICE_NAME, SERVICE_PATH)
    except Exception as e:
        print(f"{RED}[✗] {_t('ERROR: Could not connect to D-Bus session:', 'ERRO: Não foi possível conectar à sessão D-Bus:')} {e}{NC}")
        wait_exit(1)

    # Open a plain-text session (no encryption needed for local D-Bus)
    service_iface = dbus.Interface(service_obj, SERVICE_IFACE)
    try:
        output, session_path = service_iface.OpenSession(
            "plain",                          # algorithm
            dbus.String("", variant_level=1)  # input (empty for plain)
        )
    except Exception as e:
        print(f"{RED}[✗] {_t('ERROR: Could not open Secret Service session:', 'ERRO: Não foi possível abrir a sessão do Secret Service:')} {e}{NC}")
        wait_exit(1)

    # Get current password
    try:
        current_pw = getpass.getpass(_t("Enter your CURRENT keyring password: ", "Digite a sua senha ATUAL do chaveiro: "))
    except (KeyboardInterrupt, EOFError):
        print("\n" + _t("Operation canceled.", "Operação cancelada."))
        sys.exit(1)

    if not current_pw:
        print(f"{YELLOW}[!] {_t('Empty password entered. Attempting to apply blank password...', 'Senha atual vazia inserida. Tentando aplicar senha em branco...')}{NC}")

    # Build Secret structs: (session_path, params, value, content_type)
    # For "plain" algorithm, params is empty byte array
    old_secret = dbus.Struct([
        dbus.ObjectPath(session_path),
        dbus.ByteArray(b""),                         # params (empty for plain)
        dbus.ByteArray(current_pw.encode("utf-8")),  # the password
        dbus.String("text/plain"),                   # content type
    ], signature="oayays")

    new_secret = dbus.Struct([
        dbus.ObjectPath(session_path),
        dbus.ByteArray(b""),                         # params
        dbus.ByteArray(b""),                         # empty password
        dbus.String("text/plain"),
    ], signature="oayays")

    # Call ChangeWithMasterPassword
    internal_iface = dbus.Interface(service_obj, INTERNAL_IFACE)
    try:
        internal_iface.ChangeWithMasterPassword(
            dbus.ObjectPath(COLLECTION_PATH),
            old_secret,
            new_secret,
        )
        print()
        print(f"{GREEN}{BOLD}[✓ OK] {_t('SUCCESS: Login keyring password is now empty!', 'SUCESSO: A senha do chaveiro agora está vazia!')}{NC}")
        print(f"  {_t('• It will auto-unlock on fingerprint login.', '• O chaveiro será desbloqueado automaticamente no login por digital.')}")
        print(f"  {_t('• No more password prompts will appear.', '• Nenhum aviso de solicitação de senha será exibido.')}")
        wait_exit(0)
    except dbus.exceptions.DBusException as e:
        print()
        print(f"{RED}[✗] {_t('FAILED:', 'FALHA:')} {e.get_dbus_message()}{NC}")
        if "password" in str(e).lower() or "denied" in str(e).lower():
            print(f"{YELLOW}[!] {_t('The current password was incorrect. Please try again.', 'A senha informada estava incorreta. Por favor, tente novamente.')}{NC}")
        wait_exit(1)

if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\n" + _t("Operation aborted by user.", "Operação cancelada pelo usuário."))
        sys.exit(0)
