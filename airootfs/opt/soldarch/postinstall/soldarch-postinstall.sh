#!/usr/bin/env bash
# soldarch-postinstall.sh — один раз при первой загрузке установленной системы.
set -Eeuo pipefail

LOG=/var/log/soldarch-postinstall.log
mkdir -p /var/log /etc/soldarch
touch "$LOG"
exec >>"$LOG" 2>&1

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "=== Soldarch post-install started ==="

USER_NAME=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
USER_NAME=${USER_NAME:-iam}
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_HOME=${USER_HOME:-/home/$USER_NAME}

# 1. Зеркала pacman (нужен интернет; при его отсутствии шаг пропускается).
if command -v reflector >/dev/null 2>&1; then
    log "Обновление mirrorlist через reflector"
    timeout 90 reflector --country Russia,Germany,Poland --age 12 \
        --protocol https --sort rate --save /etc/pacman.d/mirrorlist || \
        log "reflector не смог обновить mirrorlist"
fi

# 2. Пользовательские каталоги.
if command -v xdg-user-dirs-update >/dev/null 2>&1 && [[ -d "$USER_HOME" ]]; then
    log "Создание XDG-каталогов для $USER_NAME"
    runuser -u "$USER_NAME" -- env HOME="$USER_HOME" xdg-user-dirs-update || true
fi

# 3. Прошивки (не критично для работы системы).
if command -v fwupdmgr >/dev/null 2>&1; then
    log "Проверка обновлений прошивок"
    timeout 60 fwupdmgr refresh --force >/dev/null 2>&1 || true
fi

# 4. Еженедельная TRIM-обрезка.
systemctl enable --now fstrim.timer >/dev/null 2>&1 || true

# 5. Чистка кэша pacman: оставляем три последние версии.
if command -v paccache >/dev/null 2>&1; then
    log "Очистка кэша pacman"
    paccache -rk3 >/dev/null 2>&1 || true
fi

# 6. MOTD.
cat >/etc/motd <<EOF

   ███████╗ ██████╗ ██╗     ██████╗  █████╗ ██████╗  ██████╗██╗  ██╗
   ██╔════╝██╔═══██╗██║     ██╔══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║
   ███████╗██║   ██║██║     ██║  ██║███████║██████╔╝██║     ███████║
   ╚════██║██║   ██║██║     ██║  ██║██╔══██║██╔══██╗██║     ██╔══██║
   ███████║╚██████╔╝███████╗██████╔╝██║  ██║██║  ██║╚██████╗██║  ██║
   ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝

   Arch Linux + Hyprland + Throne + zapret

   Пользователь : $USER_NAME
   Хостнейм     : $(hostname)
   Ядро         : $(uname -r)
   Адрес        : $(ip -brief address 2>/dev/null | awk '$2=="UP" {print $3; exit}')
   Оболочка     : fish
   Терминал     : SUPER+Enter
   Лаунчер      : SUPER+R

   Обновление   : sudo pacman -Syu
   Логи         : /var/log/soldarch-postinstall.log

EOF

# 7. Отметка о выполнении (условие в systemd-юните).
touch /etc/soldarch/post-install.done
log "=== Soldarch post-install completed ==="
