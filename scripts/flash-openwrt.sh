#!/bin/sh
# Grava o OpenWrt (Beam WRT) no slot 1 (rootfs_1 / mtd24) e troca os flags de boot.
# Roda NO HOST (como root).
# Uso: flash-openwrt.sh /caminho/para/factory.ubi

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

IMG="$1"
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "Uso: $0 /caminho/para/factory.ubi"
    exit 1
fi

# 1) Confirme o hash antes de gravar (compare com o sha256sums.txt da release).
echo "--- sha256 da imagem ---"
sha256sum "$IMG" 2>/dev/null || md5sum "$IMG"

# 2) Certifique-se de que o slot atual é o 0 (stock em mtd23).
#    Se flag_boot_rootfs != 0, PARE e investigue.
CUR=$(nvram get flag_boot_rootfs)
echo "flag_boot_rootfs atual: $CUR"
if [ "$CUR" != "0" ]; then
    echo "ERRO: o roteador NÃO está bootando do slot 0 (stock). Abortando."
    exit 1
fi

# 3) Solte o mtd24 caso ele esteja preso a um UBI (ex.: inspeção anterior).
umount /tmp/sq 2>/dev/null
ubiblock -r /dev/ubi5_1 2>/dev/null
ubidetach -p /dev/mtd24 2>/dev/null
sleep 1

# 4) Grava no slot 1 (rootfs_1).
echo "--- ubiformat /dev/mtd24 ---"
ubiformat /dev/mtd24 -y -f "$IMG"
echo "ubiformat rc=$?"
[ $? -ne 0 ] && { echo "Falha na gravação."; exit 1; }

# 5) Troca os flags para bootar o slot 1.
nvram set flag_boot_rootfs=1
nvram set flag_last_success=1
nvram set flag_boot_success=1
nvram set flag_try_sys1_failed=0
nvram set flag_try_sys2_failed=0
nvram set flag_ota_reboot=0
nvram commit
echo "flag_boot_rootfs=$(nvram get flag_boot_rootfs)"

echo "Pronto. Reinicie com: reboot"
