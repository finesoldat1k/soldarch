#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="soldatik-linux"
iso_label="Soldatik_$(date +%Y%m)"
iso_publisher="finesoldatik"
iso_application="Soldatik Linux Live"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
bootmodes=('bios.syslinux' 'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/soldatik-install"]="0:0:755"
  ["/usr/local/bin/lib"]="0:0:755"
)