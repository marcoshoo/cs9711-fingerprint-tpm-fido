# Suporte ao Leitor de Digitais Chipsailing CS9711 & TPM-FIDO2 no Ubuntu 26.04

Este projeto fornece uma solução automatizada, robusta e modular para instalar e gerenciar o suporte completo ao leitor biométrico **Chipsailing CS9711** (USB ID `2541:0236`) e integrá-lo a uma **chave de segurança virtual FIDO2 / WebAuthn baseada em TPM 2.0**.

Desenvolvido e testado especificamente para **Ubuntu 26.04 LTS (Resolute)**.

---

## 🚀 O que este projeto faz

1. **Driver Biométrico Customizado (libfprint CS9711)**:
   - Instala a versão modificada do `libfprint` com suporte ao sensor `2541:0236`.
   - Aplica ajuste de *retry delay* (1500ms) para melhorar a precisão da leitura.
   - Configura o cache do driver em `/var/lib/cs9711-fingerprint` e o hook do APT (`/etc/apt/apt.conf.d/99-cs9711-guard`) para **proteger o driver contra substituições acidentais durante `apt upgrade`**.

2. **Integração com PAM (Autenticação do Sistema)**:
   - Configura biometria para `sudo`, `sudo -i`, `polkit-1` e tela de bloqueio/login (`gdm-fingerprint`).
   - Mantém o fallback de senha 100% preservado (sem risco de lockout).

3. **Chave Virtual FIDO2 com TPM (`tpm-fido2`)**:
   - Carrega o módulo de kernel `uhid` (`/etc/modules-load.d/uhid.conf`).
   - Define regras UDEV para `/dev/tpmrm0` (grupo `tss`) e `/dev/uhid` (grupo `plugdev`), com suporte a navegadores empacotados em **Snap** (Chromium e Firefox).
   - Aplica patch automático no código Go (`userpresence/userpresence.go`) para **silenciar o popup redundante de notificação do sistema (`notify-send`)**, mantendo a solicitação biométrica limpa e direta.
   - Configura e inicializa o serviço de usuário systemd `tpm-fido.service`.

4. **Gerenciador Gráfico & Ícone em Alta Resolução**:
   - Instala o aplicativo gráfico `cs9711-manager` em `/usr/local/bin/cs9711-manager`.
   - Corrige o problema comum de ícone SVG não renderizado no GNOME: instala o ícone transparente PNG 256x256 em `/usr/share/icons/hicolor/256x256/apps/cs9711-manager.png` e `/usr/share/pixmaps/cs9711-manager.png`.
   - Disponibiliza o atalho portátil `cs9711-manager.desktop` sem amarras a caminhos locais de diretório pessoal.

---

## 📁 Estrutura de Arquivos

```text
install-fingerprint/
├── install.sh                     # Script mestre de instalação não-interativa
├── reinstall.sh                   # Script de recompilação do driver com delay configurável
├── uninstall.sh                   # Script de rollback e desinstalação completa
├── verify.sh                      # Validador de saúde do sistema e hardware
├── patches/
│   └── tpm-fido-disable-notify.patch  # Patch Go que silencia o notify-send redundante
├── rules/
│   ├── 70-tpm-permissions.rules   # Acesso ao TPM (/dev/tpmrm0)
│   └── 90-tpm-fido-uhid.rules     # Acesso ao UHID e suporte a navegadores Snap
├── helpers/
│   ├── cs9711-update-guard        # Script de restauração acionado após transações do APT
│   └── 99-cs9711-guard            # Configuração DPkg::Post-Invoke do APT
├── assets/
│   ├── cs9711-manager.png         # Ícone 256x256 com fundo transparente
│   ├── cs9711-manager.py          # Interface gráfica do gerenciador
│   ├── cs9711-manager.desktop     # Atalho para o menu de aplicativos (XDG)
│   ├── translations.json          # Dicionário de internacionalização e traduções (i18n)
│   └── tpm-fido.service           # Template do serviço de usuário systemd
├── packages/
│   └── cs9711-fingerprint_2.2.5_amd64.deb # Pacote base pré-compilado
└── README.md                      # Esta documentação
```

---

## 🛠️ Como Utilizar

### 1. Instalação Completa (Silenciosa / Não-interativa)

Basta executar o script com privilégios de superusuário:

```bash
sudo ./install.sh
```

Ou de forma explícita com flag não-interativa:
```bash
./install.sh -y
```

O script detecta automaticamente o usuário real (`$SUDO_USER`), compila e instala os componentes, configura os grupos de permissão (`tss`, `plugdev`), registra os atalhos gráficos, ativa os daemons e roda o diagnóstico final.

---

### 2. Diagnóstico e Verificação de Saúde

Para verificar o status completo de todos os componentes a qualquer momento, execute:

```bash
./verify.sh
```
*(ou `./install.sh --verify`)*

O verificador testará:
- Conexão do hardware USB (2541:0236)
- Carregamento do módulo `uhid`
- Permissões de `/dev/tpmrm0` e `/dev/uhid`
- Associação do usuário aos grupos necessários
- Precedência da biblioteca `libfprint` no `ldconfig`
- Daemon `fprintd` e digitais cadastradas
- Regras do PAM (`sudo`, `polkit`, `gdm`)
- Proteção de atualizações do APT
- Serviço `tpm-fido.service` no systemd
- Integridade do atalho de aplicativo e ícone PNG

---

### 3. Cadastrando Digitais

Após a instalação, cadastre seu dedo usando qualquer um dos métodos:

- **Via Terminal**:
  ```bash
  fprintd-enroll
  ```
  *(Toque o leitor repetidamente até atingir 100% da leitura)*

- **Via Interface Gráfica**:
  Pesquise por **CS9711** ou **Fingerprint Manager** no lançador de aplicativos do Ubuntu (ou execute `cs9711-manager` no terminal).

---

### 4. Testando WebAuthn / Passkeys com Biometria

Abra o seu navegador (Chrome, Edge, Firefox, Brave) e faça um teste em:
- [https://webauthn.io](https://webauthn.io)
- [https://passkeys.io](https://passkeys.io)

Ao criar ou autenticar uma chave de segurança física/Passkey, o navegador reconhecerá o **TPM-FIDO2** e solicitará o toque no sensor biométrico CS9711 para liberar a autenticação.

---

### 5. Desinstalação e Rollback

Caso queira remover todo o suporte e restaurar as configurações padrão do sistema:

```bash
sudo ./uninstall.sh
```
*(ou `./install.sh --uninstall`)*

---

## 🔒 Segurança e Resiliência

- **Sem lockouts**: As regras de PAM são inseridas como `sufficient`, garantindo que você nunca seja bloqueado caso o leitor não esteja conectado.
- **Sobrevivência ao `apt upgrade`**: O `cs9711-update-guard` detecta quando um update do Ubuntu instala um pacote upstream do `libfprint` e restaura instantaneamente o driver compilado.
- **Compatibilidade com Snap**: As regras de UDEV incluem diretivas `snap-device-helper` para garantir que navegadores empacotados em sandbox Snap consigam se comunicar com a chave FIDO2 virtual.
