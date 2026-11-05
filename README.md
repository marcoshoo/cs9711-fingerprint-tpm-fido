# Chipsailing CS9711 Fingerprint & TPM-FIDO2 on Ubuntu 26.04

[![Language: Portuguese](https://img.shields.io/badge/Language-Portugu%C3%AAs%20(Brasil)-green.svg)](README.pt_BR.md)
> 🇧🇷 **Versão em Português**: Para a documentação em português do Brasil, consulte [README.pt_BR.md](README.pt_BR.md).

An automated, resilient, and modular solution to install and configure complete biometric authentication for the **Chipsailing CS9711 USB fingerprint scanner** (USB ID `2541:0236`) integrated with a **TPM 2.0-backed virtual FIDO2 / WebAuthn security key**.

Specifically developed, tested, and optimized for **Ubuntu 26.04 LTS (Resolute)** and **Ubuntu 24.04 LTS (Noble)**.

---

## 🚀 Key Features

1. **Patched Biometric Driver (`libfprint` CS9711)**:
   - Patched `libfprint` library adding native support for the `2541:0236` sensor.
   - 1500ms human-friendly retry delay patch preventing timeout errors during multi-touch capture.
   - Driver backup cache (`/var/lib/cs9711-fingerprint`) and APT post-invoke hook (`/etc/apt/apt.conf.d/99-cs9711-guard`) to **prevent upstream `apt upgrade` transactions from breaking the driver**.

2. **System Authentication (PAM Integration)**:
   - Biometric authentication configured for `sudo`, `sudo -i`, `polkit-1`, and display manager login/lock screens (`gdm-password` / `gdm-fingerprint`).
   - Strict `sufficient` PAM placement preserving 100% password fallback (zero risk of lockouts).
   - **Smart Remote Session Detection**: Automatically bypasses fingerprint prompts during remote desktop sessions (GNOME Remote Desktop / RDP / VNC / Wayland headless) and SSH connections via `cs9711-check-is-remote`, prompting directly for the password instead of hanging waiting for a physical sensor touch.

3. **TPM 2.0-Backed Virtual FIDO2 Key (`tpm-fido2`)**:
   - Automatic kernel module loading for `uhid` (`/etc/modules-load.d/uhid.conf`).
   - UDEV rules granting user access to `/dev/tpmrm0` (`tss` group) and `/dev/uhid` (`plugdev` group), with **Snap-confined browser support** (Chromium and Firefox).
   - Upstream patch applied to Go code (`userpresence/userpresence.go`) silencing redundant desktop notifications (`notify-send`), delivering seamless fingerprint prompts.
   - Systemd user service `tpm-fido.service` enabled and started automatically.

4. **Modern GTK4/Adwaita GUI Manager**:
   - Graphical management app installed as `/usr/local/bin/cs9711-manager`.
   - Internationalization (i18n) support (`en` and `pt_BR`) with modular dictionary catalog in `translations.json`.
   - Crisp transparent 256x256 PNG icon installed to standard XDG directories (`/usr/share/icons/hicolor/256x256/apps` and `/usr/share/pixmaps`).
   - Validated desktop launcher (`cs9711-manager.desktop`) with localized metadata.

---

## 📁 Repository Structure

```text
install-fingerprint/
├── install.sh                     # Non-interactive master installation script
├── reinstall.sh                   # Driver recompilation script with configurable delay
├── uninstall.sh                   # Complete rollback and uninstallation script
├── verify.sh                      # Diagnostic and system health verification script
├── patches/
│   └── tpm-fido-disable-notify.patch  # Go patch silencing redundant notify-send popups
├── rules/
│   ├── 70-tpm-permissions.rules   # TPM access permissions (/dev/tpmrm0)
│   └── 90-tpm-fido-uhid.rules     # UHID access and Snap browser sandbox permissions
├── helpers/
│   ├── cs9711-check-is-remote     # Session detection helper (remote vs local PAM bypass)
│   ├── cs9711-update-guard        # Driver restore script triggered on APT upgrades
│   └── 99-cs9711-guard            # APT DPkg::Post-Invoke hook configuration
├── assets/
│   ├── cs9711-manager.png         # High-resolution 256x256 transparent icon
│   ├── cs9711-manager.py          # GTK4/Adwaita GUI application
│   ├── cs9711-manager.desktop     # Desktop launcher shortcut (XDG)
│   ├── translations.json          # Translation catalogs (i18n)
│   └── tpm-fido.service           # Systemd user service template
├── packages/
│   └── cs9711-fingerprint_2.2.5_amd64.deb # Pre-compiled multi-release base package
├── README.md                      # Main documentation in English
└── README.pt_BR.md                # Brazilian Portuguese documentation
```

---

## 🛠️ Getting Started

### 1. Full Installation (Silent & Non-Interactive)

Run the installer with root privileges:

```bash
sudo ./install.sh
```

Or explicitly with non-interactive flag:
```bash
./install.sh -y
```

The script automatically detects system language (`en` or `pt_BR`), identifies the target non-root user (`$SUDO_USER`), sets up dependencies, configures permissions and groups (`tss`, `plugdev`), registers launchers, enables systemd services, and executes diagnostic validation.

---

### 2. Diagnostics & System Verification

Verify the operational health of all components at any time:

```bash
./verify.sh
```
*(or `./install.sh --verify`)*

The validator inspects 21 individual checkpoints:
- USB hardware presence (2541:0236)
- Kernel module `uhid` loaded and auto-loading configured
- Device permissions for `/dev/tpmrm0` and `/dev/uhid`
- User membership in `tss` and `plugdev`
- Dynamic linker precedence in `ldconfig`
- `fprintd` daemon recognition and enrolled fingerprints
- PAM rules (`sudo`, `polkit`, `gdm`)
- APT update guard cache and hook registration
- `tpm-fido.service` user daemon status
- Desktop menu shortcut and PNG icon health

---

### 3. Fingerprint Enrollment

After installation, enroll your fingerprints:

- **Via Terminal**:
  ```bash
  fprintd-enroll
  ```
  *(Touch the sensor repeatedly until 100% completion is reached)*

- **Via Graphical Manager**:
  Launch **CS9711** or **Fingerprint Manager** from your application menu (or run `cs9711-manager` in the terminal).

---

### 4. Testing WebAuthn / FIDO2 Passkeys

Open any browser (Chrome, Edge, Firefox, Brave) and test hardware key authentication at:
- [https://webauthn.io](https://webauthn.io)
- [https://passkeys.io](https://passkeys.io)

When creating or authenticating a physical security key or Passkey, the browser will invoke **TPM-FIDO2** and prompt you to touch the CS9711 scanner.

---

### 5. Recompiling the Driver (Custom Retry Delay)

To fine-tune scanner sensitivity and inter-touch retry delays (default 1500ms):
- Open `cs9711-manager`, adjust the retry delay slider under Settings, and click **Rebuild Now**; or
- Execute via terminal:
  ```bash
  sudo ./reinstall.sh 1200
  ```

---

### 6. Uninstallation & Rollback

To cleanly remove all components and restore stock system configuration:

```bash
sudo ./uninstall.sh
```
*(or `./install.sh --uninstall`)*

---

## 🔒 Security & Reliability

- **No Lockouts**: All PAM entries use `sufficient` control, ensuring standard password authentication remains fully functional even if the sensor is disconnected.
- **Remote Session Bypass**: Dynamically skips fingerprint prompts when operating over SSH or remote desktop (GNOME Remote Desktop / RDP), avoiding biometric timeouts when you are not physically at the machine.
- **APT Upgrade Survival**: The `cs9711-update-guard` monitors APT operations and automatically restores the patched driver whenever an upstream Ubuntu upgrade replaces `libfprint`.
- **Snap Sandbox Compatibility**: Custom UDEV tags include `snap-device-helper` directives allowing sandboxed browsers to communicate directly with the virtual FIDO2 token.
