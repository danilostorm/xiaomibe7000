#!/bin/sh
# Script de exemplo executado NO HOST (via escape modprobe_path) para habilitar SSH.
# Coloque-o num caminho acessível pelo host (ex.: $UPPERDIR do contêiner) e aponte
# o modprobe para ele (veja o README, seção 2).

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

nvram set ssh_en=1
nvram commit

# Desbloqueia o dropbear (remove o guard que bloqueia SSH no canal "release").
# A linha abaixo remove apenas o "return 0" standalone dentro do start_service().
sed -i '/^[[:space:]]*return 0[[:space:]]*$/d' /etc/init.d/dropbear

/etc/init.d/dropbear start
/etc/init.d/dropbear enable

echo "SSH habilitado. Conecte: ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa root@IP_DO_ROTEADOR"
