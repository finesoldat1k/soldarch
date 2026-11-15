#!/usr/bin/env bash
# lib/chroot.sh — настройка системы внутри chroot

# ═══════════════════════════════════════════════════════════
# Системные настройки
# ═══════════════════════════════════════════════════════════

chroot_timezone_locale() {
    ui_step "Часовой пояс и локаль"

    run_chroot_sh "ln -sf /usr/share/zoneinfo/${CONFIG[timezone]} /etc/localtime"
    run_chroot_sh "hwclock --systohc"

    # locale.gen
    run_chroot_sh "cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
EOF"

    run_chroot_sh "locale-gen"
    run_chroot_sh "echo 'LANG=${CONFIG[locale]}' > /etc/locale.conf"

    # Кириллица в консоли
    run_chroot_sh "cat > /etc/vconsole.conf <<'EOF'
KEYMAP=us
FONT=ter-v16n
EOF"

    ui_success "TZ / локаль настроены"
}

chroot_hostname_hosts() {
    ui_step "Хостнейм"

    run_chroot_sh "echo '${CONFIG[hostname]}' > /etc/hostname"

    run_chroot_sh "cat > /etc/hosts <<'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${CONFIG[hostname]}.localdomain ${CONFIG[hostname]}
EOF"

    ui_success "Хостнейм: ${CONFIG[hostname]}"
}

chroot_users() {
    ui_step "Пользователи и пароли"

    local root_hash user_hash
    root_hash=$(openssl passwd -6 "${CONFIG[rootpass]}")
    user_hash=$(openssl passwd -6 "${CONFIG[userpass]}")

    # Root пароль
    run_chroot_sh "echo 'root:${root_hash}' | chpasswd -e"

    # Пользователь
    run_chroot_sh "useradd -m -G wheel,audio,video,storage,optical,network,rfkill,input -s /usr/bin/fish '${CONFIG[username]}'"

    run_chroot_sh "echo '${CONFIG[username]}:${user_hash}' | chpasswd -e"

    # sudo для wheel
    run_chroot_sh "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel"
    run_chroot_sh "chmod 440 /etc/sudoers.d/10-wheel"

    ui_success "Пользователь ${CONFIG[username]} создан"
}

chroot_network() {
    ui_step "Настройка сети (${CONFIG[network]})"

    case "${CONFIG[network]}" in
        networkmanager)
            # iwd backend
            run_chroot_sh "mkdir -p /etc/NetworkManager/conf.d"
            run_chroot_sh "cat > /etc/NetworkManager/conf.d/wifi-backend.conf <<'EOF'
[device]
wifi.backend=iwd
EOF"
            run_chroot_sh "systemctl enable NetworkManager"
            run_chroot_sh "systemctl enable bluetooth"
            ;;
        systemd-networkd)
            run_chroot_sh "systemctl enable systemd-networkd"
            run_chroot_sh "systemctl enable systemd-resolved"
            run_chroot_sh "systemctl enable iwd"
            ;;
    esac

    run_chroot_sh "systemctl enable systemd-timesyncd"
    ui_success "Сеть настроена"
}

chroot_mkinitcpio() {
    ui_step "Генерация initramfs"

    # Устанавливаем корректные хуки для установленной системы
    run_chroot_sh "sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/' /etc/mkinitcpio.conf"

    # Ускоренное сжатие
    run_chroot_sh "sed -i 's/^#COMPRESSION=\"zstd\"/COMPRESSION=\"zstd\"/' /etc/mkinitcpio.conf"

    if ! run_chroot mkinitcpio -P; then
        ui_error "mkinitcpio упал"
        return 1
    fi

    ui_success "initramfs сгенерирован"
}

# ═══════════════════════════════════════════════════════════
# Общая функция
# ═══════════════════════════════════════════════════════════

run_chroot_setup() {
    chroot_timezone_locale
    chroot_hostname_hosts
    chroot_users
    chroot_network
    chroot_mkinitcpio
}