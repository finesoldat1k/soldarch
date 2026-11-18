#!/usr/bin/env bash
# target-setup.sh — выполняется внутри установленной системы через arch-chroot
set -Eeuo pipefail

# shellcheck disable=SC1091
source /root/soldarch-setup.env

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

log() { printf '[target] %s\n' "$*"; }
die() { printf '[target] ERROR: %s\n' "$*" >&2; exit 1; }

# ── Время и локаль ────────────────────────────────────────────
ln -sf "/usr/share/zoneinfo/${SOLDARCH_TIMEZONE}" /etc/localtime
hwclock --systohc 2>/dev/null || true

cat >/etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
EOF
locale-gen

printf 'LANG=%s\n' "$SOLDARCH_LOCALE" >/etc/locale.conf
cat >/etc/vconsole.conf <<EOF
KEYMAP=${SOLDARCH_KEYMAP}
FONT=ter-v16n
EOF

# ── Имя компьютера ────────────────────────────────────────────
printf '%s\n' "$SOLDARCH_HOSTNAME" >/etc/hostname
cat >/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${SOLDARCH_HOSTNAME}.localdomain ${SOLDARCH_HOSTNAME}
EOF

# ── Пользователь ─────────────────────────────────────────────
# В свежем pacstrap /etc/group содержит только root. Группы из
# systemd-sysusers создаём до useradd, иначе useradd -G завершится ошибкой.
systemd-sysusers 2>/dev/null || true
for _group in wheel video render audio input storage optical network rfkill; do
    getent group "$_group" >/dev/null 2>&1 || groupadd "$_group"
done
unset _group

if ! id "$SOLDARCH_USER" >/dev/null 2>&1; then
    useradd -m \
        -G wheel,video,render,audio,input,storage,optical,network,rfkill \
        -s /usr/bin/fish \
        "$SOLDARCH_USER"
else
    usermod -aG wheel,video,render,audio,input,storage,optical,network,rfkill "$SOLDARCH_USER"
fi

printf '%s:%s\n' "$SOLDARCH_USER" "$SOLDARCH_USER_HASH" | chpasswd -e
passwd -l root >/dev/null

# Проверяем, что все группы действительно назначены.
for _group in wheel video render audio input storage optical network rfkill; do
    id -nG "$SOLDARCH_USER" | tr ' ' '\n' | grep -qx "$_group" || \
        die "Пользователь ${SOLDARCH_USER} не добавлен в группу ${_group}"
done
unset _group

cat >/etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
chmod 440 /etc/sudoers.d/10-wheel

# ── Ключи pacman ─────────────────────────────────────────────
# Пакеты ставились из локального репозитория с SigLevel=Optional TrustAll,
# но у установленной системы должен быть рабочий keyring для обычного Arch.
pacman-key --init
pacman-key --populate archlinux

# ── Сеть ─────────────────────────────────────────────────────
mkdir -p /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/wifi-backend.conf <<'EOF'
[device]
wifi.backend=iwd
EOF

systemctl enable NetworkManager.service
systemctl enable iwd.service
systemctl enable bluetooth.service
systemctl enable systemd-timesyncd.service
systemctl enable fstrim.timer
systemctl set-default graphical.target

# ── Звук PipeWire (глобальные user-юниты) ────────────────────
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service || true
mkdir -p /etc/systemd/user/sockets.target.wants /etc/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/pipewire.socket /etc/systemd/user/sockets.target.wants/pipewire.socket
ln -sf /usr/lib/systemd/user/pipewire-pulse.socket /etc/systemd/user/sockets.target.wants/pipewire-pulse.socket
ln -sf /usr/lib/systemd/user/wireplumber.service /etc/systemd/user/default.target.wants/wireplumber.service

# ── SDDM ─────────────────────────────────────────────────────
mkdir -p /etc/sddm.conf.d
systemctl enable sddm.service

if [[ "${SOLDARCH_AUTOLOGIN}" == "1" ]]; then
    cat >/etc/sddm.conf.d/20-test-autologin.conf <<EOF
[Autologin]
User=${SOLDARCH_USER}
Session=hyprland.desktop
EOF
fi

# ── Пост-установка (один раз при первой загрузке) ────────────
if [[ -f /usr/lib/systemd/system/soldarch-postinstall.service ]]; then
    mkdir -p /etc/soldarch
    systemctl enable soldarch-postinstall.service
fi

# ── zapret ───────────────────────────────────────────────────
if [[ -f /usr/lib/systemd/system/zapret.service ]]; then
    systemctl enable zapret.service
fi
if [[ -f /usr/lib/systemd/system/zapret-list-update.timer ]]; then
    systemctl enable zapret-list-update.timer
fi

# ── LUKS: crypttab, initcpio, GRUB ───────────────────────────
if [[ "${SOLDARCH_LUKS:-0}" == "1" ]]; then
    log "Настройка LUKS2..."

    root_src=""
    home_src=""
    for dev in /dev/disk/by-partlabel/root_crypt /dev/disk/by-partlabel/root; do
        if [[ -b "$dev" ]]; then root_src="$dev"; break; fi
    done
    for dev in /dev/disk/by-partlabel/home_crypt /dev/disk/by-partlabel/home; do
        if [[ -b "$dev" ]]; then home_src="$dev"; break; fi
    done
    [[ -n "$root_src" ]] || die "LUKS: не найден контейнер root"
    [[ -n "$home_src" ]] || die "LUKS: не найден контейнер home"

    root_luks_uuid=$(blkid -s UUID -o value "$root_src")
    home_luks_uuid=$(blkid -s UUID -o value "$home_src")
    [[ -n "$root_luks_uuid" && -n "$home_luks_uuid" ]] || die "LUKS: не удалось прочитать UUID"

    cat >/etc/crypttab <<EOF
cryptroot UUID=${root_luks_uuid} none luks,discard
crypthome UUID=${home_luks_uuid} none luks,discard
EOF

    # encrypt должен идти до filesystems, иначе корень не откроется.
    if ! grep -qE '^HOOKS=.*(^|[[:space:]])encrypt([[:space:]]|\))' /etc/mkinitcpio.conf; then
        sed -i -E 's/^(HOOKS=\([^)]*)[[:space:]]filesystems/\1 encrypt filesystems/' /etc/mkinitcpio.conf
        grep -qE '^HOOKS=.*encrypt' /etc/mkinitcpio.conf || \
            sed -i -E 's/^(HOOKS=\()/\1encrypt /' /etc/mkinitcpio.conf
    fi

    # GRUB передаёт ядру LUKS-устройство и корень на mapper.
    if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
        sed -i -E "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${root_luks_uuid}:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub
    else
        printf 'GRUB_CMDLINE_LINUX="cryptdevice=UUID=%s:cryptroot root=/dev/mapper/cryptroot"\n' \
            "$root_luks_uuid" >>/etc/default/grub
    fi
fi

# ── Журнал ───────────────────────────────────────────────────
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true

# ── initramfs ────────────────────────────────────────────────
mkinitcpio -P

log "target setup complete"
