Por favor, verifique e sincronize as dependências upstream deste projeto:

1. Inspecione os seguintes repositórios upstream:
   - https://github.com/archeYR/libfprint-CS9711.git (branch cs9711-rebase / HEAD)
   - https://github.com/mc256/tpm-fido2-thinkpad-linux.git (branch main / HEAD)
   - https://github.com/mmhfarooque/chipsailing-cs9711-fingerprint-linux.git (Releases e tags)

2. Se houver novas atualizações:
   - Analise se o patch `patches/tpm-fido-disable-notify.patch` continua aplicando de forma limpa no código atualizado de `tpm-fido2-thinkpad-linux` (ou se o upstream introduziu opções nativas para desativar popups).
   - Verifique se os ajustes no `install.sh` (parâmetros meson, delay de 1500ms no `cs9711.c`, bypass de sessões remotas PAM e helpers em `helpers/`) ainda são necessários ou se exigem compatibilização.
   - Caso um novo `.deb` oficial de libfprint tenha sido lançado em `chipsailing-cs9711-fingerprint-linux`, atualize o pacote dentro de `packages/` e valide o script de instalação.
   - Execute uma verificação de integridade rodando `bash -n install.sh` e `bash -n verify.sh`.