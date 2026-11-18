#!/usr/bin/env bash
# soldarch-postinstall.sh — запускается один раз после первой загрузки
set -Eeuo pipefail

LOG="/var/log/soldarch-postinstall.log"
exec > >(tee -a "$LOG") 2>&1

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "=== Soldarch post-install started ==="

# 1. Обновление mirrorlist через reflector (если есть интернет)
if command -v reflector &>/dev/null; then
    log "Updating mirrorlist with reflector..."
    reflector --country Russia,Germany,Poland --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || true
fi

# 2. Создание пользовательских директорий (xdg-user-dirs)
if command -v xdg-user-dirs-update &>/dev/null; then
    log "Creating XDG user directories..."
    runuser -u iam -- xdg-user-dirs-update || true
fi

# 3. Обновление fwupd (прошивки)
if command -v fwupdmgr &>/dev/null; then
    log "Refreshing fwupd metadata..."
    fwupdmgr refresh --force || true
    fwupdmgr get-updates || true
fi

# 4. Включение fstrim.timer (если не включён)
systemctl enable fstrim.timer || true

# 5. Очистка pacman кэша (оставляем последние 3 версии)
if command -v paccache &>/dev/null; then
    log "Cleaning pacman cache..."
    paccache -rk3 || true
fi

# 6. Генерация MOTD с информацией о системе
cat >/etc/motd <<EOF

   ███████╗ ██████╗ ██████╗ ███████╗███████╗
   ██╔════╝██╔═══██╗██╔═══██╗██╔════╝██╔════╝
   ███████╗██║   ██║██║   ██║█████╗  █████╗
   ╚════██║██║   ██║██║   ██║██╔══╝  ██╔══╝
   ███████║╚██████╔╝╚██████╔╝███████╗███████╗
   ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝╚══════╝

   Soldarch Linux — Arch + Hyprland + Throne + zapret

   Hostname: $(hostname)
   Kernel: $(uname -r)
   Uptime: $(uptime -p)
   IP: $(ip -brief address | awk '$2=="UP" {print $3}' | head -1)

   User: iam
   Shell: fish
   DE: Hyprland (SUPER+Enter = terminal)

   Update system: sudo pacman -Syu
   Check updates: checkupdates

EOF

# 7. Помечаем как выполненное
touch /etc/soldarch/post-install.done
log "=== Soldarch post-install completed ==="