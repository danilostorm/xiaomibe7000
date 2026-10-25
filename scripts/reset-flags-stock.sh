#!/bin/sh
# Volta o boot para o slot 0 (stock). Roda NO HOST (como root).

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

nvram set flag_boot_rootfs=0
nvram set flag_last_success=0
nvram set flag_boot_success=1
nvram set flag_try_sys1_failed=0
nvram set flag_try_sys2_failed=0
nvram set flag_ota_reboot=0
nvram commit

echo "flag_boot_rootfs=$(nvram get flag_boot_rootfs)"
echo "Reinicie com: reboot"
