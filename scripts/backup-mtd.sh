#!/bin/sh
# Backup completo do firmware do Xiaomi BE7000.
# Roda NO HOST (como root). Grave num pendrive ext4.
# Uso: ajuste B para o caminho do pendrive e rode como root.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# Onde salvar o backup (pendrive montado no host)
B=/mnt/usb-686f36a2/backup
mkdir -p "$B"

# Layout de referência
cat /proc/mtd > "$B/mtd_layout.txt"

# Dump de todas as partições MTD (mtd0..mtd32)
# Os dispositivos de bloco já existem em /dev/mtdblockN.
i=0
while [ $i -le 32 ]; do
    echo "backup mtd$i ..."
    dd if="/dev/mtdblock$i" of="$B/mtd$i.bin" bs=1048576 2>&1
    echo "mtd$i rc=$?"
    i=$((i+1))
done

# mtd32 ("cfg") fica ligado ao UBI e dá "Resource busy" no dd.
# Leia pelo volume UBI em vez disso:
#   ubiattach -p /dev/mtd32 -d 2
#   dd if=/dev/ubi2_1 of="$B/mtd32_cfg_ubi.bin"

# Verificação
echo "--- tamanhos ---"
ls -l "$B/"
echo "--- hashes (md5) ---"
md5sum "$B"/*.bin 2>/dev/null || sha256sum "$B"/*.bin
