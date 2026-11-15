#!/usr/bin/env bash
# lib/base.sh — pacstrap, fstab, копирование брендинга

# ─── Список базовых пакетов (зашит) ───
readonly BASE_PACKAGES=(
    base linux linux-firmware amd-ucode intel-ucode
    mkinitcpio grub efibootmgr dosfstools
    networkmanager wpa_supplicant iwd iw wireless-regdb ethtool
    bluez bluez-utils sof-firmware alsa-ucm-conf alsa-utils
    nano vim sudo fastfetch man-db man-pages
    btrfs-progs xfsprogs exfatprogs ntfs-3g f2fs-tools
    parted gptfdisk smartmontools nvme-cli hdparm dmidecode
    usbutils pciutils rsync pv openssl cryptsetup lvm2
    terminus-font
)

# ═══════════════════════════════════════════════════════════
# Установка пакетов
# ═══════════════════════════════════════════════════════════

install_base() {
    ui_step "Установка базовой системы (pacstrap)"
    log "Pacstrap base packages: ${BASE_PACKAGES[*]}"

    if ! run_cmd pacstrap -K "$MOUNTPOINT" "${BASE_PACKAGES[@]}"; then
        ui_error "pacstrap упал. Проверьте $LOGFILE"
        return 1
    fi

    ui_success "Базовые пакеты установлены"
}

# ─── Установка доп. пакетов ───
install_extra_packages() {
    local -a pkgs=()

    # Из выбранных наборов
    if [[ -n "${CONFIG[extras]}" ]]; then
        read -ra pkgs <<< "${CONFIG[extras]}"
    fi

    # Свободный ввод
    if [[ -n "${CONFIG[extras_free]:-}" ]]; then
        read -ra more <<< "${CONFIG[extras_free]}"
        pkgs+=("${more[@]}")
    fi

    [[ ${#pkgs[@]} -eq 0 ]] && return 0

    ui_step "Установка дополнительных пакетов: ${pkgs[*]}"
    log "Extra packages: ${pkgs[*]}"

    if ! run_cmd pacstrap -K "$MOUNTPOINT" "${pkgs[@]}"; then
        ui_warn "Не удалось установить некоторые доп. пакеты. Проверьте лог."
        ui_warn "Установка продолжится без них."
        # Не падаем — это некритично
        return 0
    fi

    ui_success "Доп. пакеты установлены"
}

# ═══════════════════════════════════════════════════════════
# fstab
# ═══════════════════════════════════════════════════════════

generate_fstab() {
    ui_step "Генерация /etc/fstab"

    # Очищаем старый fstab (его создал pacstrap пустым)
    run_cmd sh -c ": > $MOUNTPOINT/etc/fstab"

    if ! run_cmd sh -c "genfstab -U $MOUNTPOINT >> $MOUNTPOINT/etc/fstab"; then
        ui_error "genfstab упал"
        return 1
    fi

    # Добавляем swap-файл
    if [[ "${CONFIG[swap]}" == "file" ]]; then
        run_cmd sh -c "echo '/swapfile none swap defaults 0 0' >> $MOUNTPOINT/etc/fstab"
        log "Added swapfile to fstab"
    fi

    ui_success "fstab создан"
}

# ═══════════════════════════════════════════════════════════
# Копирование брендинга из Live в установленную систему
# ═══════════════════════════════════════════════════════════

copy_branding() {
    ui_step "Копирование брендинга Soldatik"

    # os-release
    run_cmd cp /etc/os-release "$MOUNTPOINT/etc/os-release"

    # motd
    run_cmd cp /etc/motd "$MOUNTPOINT/etc/motd"

    # issue (приглашение логина)
    run_cmd cp /etc/issue "$MOUNTPOINT/etc/issue"

    # fastfetch config
    run_cmd mkdir -p "$MOUNTPOINT/etc/fastfetch"
    run_cmd cp -r /etc/fastfetch/. "$MOUNTPOINT/etc/fastfetch/"

    ui_success "Брендинг скопирован"
}

# ═══════════════════════════════════════════════════════════
# Общая функция шага установки
# ═══════════════════════════════════════════════════════════

run_base_install() {
    install_base        || return 1
    install_extra_packages
    generate_fstab      || return 1
    copy_branding
}