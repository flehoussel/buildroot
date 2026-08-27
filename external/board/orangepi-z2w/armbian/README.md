# Fichiers Armbian de référence — Orange Pi Zero2W

Copie locale (pas un lien symbolique, pas un submodule) des fichiers Armbian
associés à cette carte, extraits de `externals/armbian-build` pour
comparaison avec notre propre config/DTS/patches. **Rien ici n'est utilisé
par notre build buildroot** — c'est uniquement de la référence, voir
`logs/260826-wifi-ble-analyse.md` pour l'analyse qui s'appuie dessus.

Kernel branch Armbian correspondante : `sunxi-6.18` (= `BRANCH=current` sur
la famille `sun50iw9`/`sunxi64`, kernel `linux-6.18.y` upstream de
`git.kernel.org`, pas un fork Armbian).

## config/

| Fichier                        | Source dans `externals/armbian-build`                                                                                                                                                   |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `orangepizero2w.csc`           | `config/boards/orangepizero2w.csc` — config board (BOARDFAMILY, KERNEL_TARGET, extension `uwe5622-allwinner`)                                                                           |
| `sun50iw9.conf`                | `config/sources/families/sun50iw9.conf` — config famille SoC (H616/H618)                                                                                                                |
| `sunxi64_common.inc`           | `config/sources/families/include/sunxi64_common.inc` — mapping `BRANCH=` → version kernel (`current`→6.18)                                                                              |
| `linux-sunxi64-current.config` | `config/kernel/linux-sunxi64-current.config` — `.config` kernel complet utilisé pour toute la famille sunxi64/current (pas spécifique à ce board, mais c'est celui réellement appliqué) |

## patches/

Tous depuis `patch/kernel/archive/sunxi-6.18/patches.armbian/`. **Renumérotés
0001-0009** (leur nom d'origine Armbian est gardé après le préfixe) dans
l'ordre où `series.conf` les applique réellement — Buildroot n'a aucune
notion de `series.conf`, `apply-patches.sh` se contente de trier les
fichiers du dossier par ordre alphabétique, donc l'ordre du nom de fichier
*est* l'ordre d'application. Plusieurs de ces patches dépendent du contexte
laissé par un patch précédent sur le **même fichier** (ex: le patch H616
internal-phy attend une entrée `sun50i-h616-emac` que seul le patch
"second-emac-clock" juste avant ajoute) — les avoir mal ordonnés (ou l'un
d'eux absent) fait échouer l'application avec un hunk `FAILED`, testé et
corrigé en conditions réelles (`patch -F0`, zéro tolérance de fuzz, comme
`apply-patches.sh`) sur le vrai tarball `linux-6.18.46.tar.xz`.

| Fichier                                                                | Rôle                                                                                                                                                                                                       |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0001-arm64-dts-sun50i-h618-orangepi-zero2w-add-emac-sound.patch`      | Équivalent Armbian de notre `.dts` custom : ajoute EMAC, son, HDMI, **wifi_pwrseq + mmc1** (le nœud wifi/BT comparé dans l'analyse)                                                                        |
| `0002-arm64-dts-sun50i-h618-orangepi-zero2w-zero3-cpu-dvfs.dtsi.patch` | Délais de régulateur PMIC (AXP313) — fix de stabilité documenté par Armbian comme lié au chargement du driver uwe5622, absent de notre `.dts` (voir analyse)                                               |
| `0003-arm64-dts-sun50i-h6-h616-add-sunxi-info-nodes.patch`             | Nœud DT pour le driver `sunxi_addr` (chip-id/adresse MAC), famille H6/H616                                                                                                                                 |
| `0004-drv-bluetooth-hci-sprd-broken-park-link-quirk-v6.16-plus.patch`  | Quirk `HCI_QUIRK_BROKEN_PARK_LINK_STATUS` (Paolo Sabatino) — équivalent Armbian de notre `0001-bluetooth-fix-sprd-broken-park-link-status.patch`                                                           |
| `0005-drv-misc-sunxi-add-addr-mgt-driver-uwe5622.patch`                | Driver `sunxi_addr` (expose `/sys/class/addr_mgt/addr_bt`) — équivalent de nos `0003`/`0004`. Hunk `drivers/misc/Makefile` réécrit à la main (contexte d'origine invalide sur le vrai 6.18.46, cf. commit) |
| `0006-drv-net-stmmac-dwmac-sun8i-add-second-emac-clock.patch`          | Ajoute une entrée `allwinner,sun50i-h616-emac` + 2e clock EMAC au driver stmmac — **prérequis** du patch suivant (0008), pas repéré au premier passage (pas de "orangepi"/"zero2w" dans son nom)           |
| `0007-drv-net-phy-ac300-phy-add.patch`                                 | PHY Ethernet AC300 (H618). Hunks `Kconfig`/`Makefile` réécrits à la main (contexte d'origine dépendait d'un patch AC200 non copié, sans rapport avec ce board)                                             |
| `0008-drv-net-stmmac-dwmac-sun8i-add-h616-internal-phy.patch`          | Support PHY interne H616 pour stmmac — dépend de 0006 (même fichier)                                                                                                                                       |
| `0009-drv-nvmem-sunxi-add-chipid-serial-helpers.patch`                 | Fournit `sunxi_get_soc_chipid()`, requis par 0005 au link — pas repéré au premier passage (nom générique H6/H616, pas board-spécifique)                                                                    |

Pas d'équivalent Armbian trouvé pour notre `0002-bluetooth-sprd-skip-broken-link-policy-command.patch`
(skip complet de `HCI_OP_WRITE_DEF_LINK_POLICY`) — voir analyse : Armbian
contourne le bug via son binaire `hciattach_opi` fermé plutôt que par un
patch kernel.

## extension/

| Fichier                    | Source                                        | Rôle                                                                                                                                                                |
| -------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `uwe5622-allwinner.sh`     | `extensions/uwe5622-allwinner.sh`             | Extension du framework de build : ajoute le module `sprdbt_tty`, les paquets `rfkill bluetooth bluez bluez-tools`, installe les services et le blob `hciattach_opi` |
| `aw859a-bluetooth.service` | `packages/bsp/sunxi/aw859a-bluetooth.service` | Service systemd qui lance `hciattach_opi -s 1500000 /dev/ttyBT0 sprd`                                                                                               |
| `aw859a-wifi.service`      | `packages/bsp/sunxi/aw859a-wifi.service`      | Service systemd côté wifi                                                                                                                                           |
| `sprd-bluetooth`           | `packages/bsp/sunxi/sprd-bluetooth`           | Script d'attach historique (référencé dans l'analyse comme lien externe, maintenant en local)                                                                       |

## blobs/

| Fichier               | Source                                            | Rôle                                                                                                                                    |
| --------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `hciattach_opi_arm64` | `packages/blobs/bt/hciattach/hciattach_opi_arm64` | Binaire **propriétaire fermé** installé comme `/usr/bin/hciattach_opi` sur l'image Armbian — celui réellement utilisé (pas `_upstream`) |
