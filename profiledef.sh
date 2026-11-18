#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="${SOLDARCH_ISO_NAME:-soldarch}"
iso_label="${SOLDARCH_ISO_LABEL:-SOLDARCH_$(date +%Y%m)}"
iso_publisher="Soldarch"
iso_application="Soldarch Linux Live Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
bootmodes=('bios.syslinux' 'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' "${SOLDARCH_SQUASHFS_LEVEL:-15}" '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
kernel_params_x86_64="${SOLDARCH_KERNEL_PARAMS:-console=tty0}"
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.bash_profile"]="0:0:644"
  ["/usr/local/bin/soldarch-install"]="0:0:755"
  ["/usr/local/bin/soldarch-gui-installer"]="0:0:755"
  ["/usr/local/bin/lib"]="0:0:755"
  ["/usr/local/lib/soldarch/gui"]="0:0:755"
  ["/usr/local/lib/soldarch/gui/main.py"]="0:0:644"
  ["/usr/share/soldarch/gui/theme.css"]="0:0:644"
  ["/usr/share/soldarch/video/soldarch-intro.mp4"]="0:0:644"
  ["/opt/soldarch"]="0:0:755"
  ["/opt/soldarch/configs"]="0:0:755"
  ["/opt/soldarch/postinstall"]="0:0:755"
  ["/opt/soldarch/postinstall/soldarch-postinstall.sh"]="0:0:755"
  ["/opt/soldarch/postinstall/soldarch-postinstall.service"]="0:0:644"
  ["/etc/soldarch"]="0:0:755"
)
