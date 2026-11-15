#!/usr/bin/env bash
# lib/boot.sh — установка GRUB

# ═══════════════════════════════════════════════════════════
# GRUB для UEFI
# ═══════════════════════════════════════════════════════════

install_grub_uefi() {
    [[ "${CONFIG[boot_mode]}" != "uefi" ]] && return 0

    ui_step "Установка GRUB (UEFI)"

    if ! run_chroot grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot/efi \
            --bootloader-id=SOLDATIK \
            --recheck; then
        ui_error "grub-install (UEFI) упал"
        return 1
    fi

    # ─── Fallback-загрузчик для капризных прошивок ───
    # Некоторые UEFI (HP, Lenovo, ASUS) игнорируют кастомный --bootloader-id
    # и ищут только /EFI/BOOT/BOOTX64.EFI
    ui_step "Создание fallback-загрузчика"
    run_chroot_sh "mkdir -p /boot/efi/EFI/BOOT"
    run_chroot_sh "cp /boot/efi/EFI/SOLDATIK/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI" || \
        ui_warn "Не удалось создать fallback BOOTX64.EFI"

    # ─── Явное создание NVRAM-записи ───
    # grub-install в chroot часто не может записать в NVRAM, поэтому делаем это вручную
    ui_step "Проверка NVRAM-записи"
    if run_chroot_sh "efibootmgr | grep -q SOLDATIK"; then
        ui_success "NVRAM-запись SOLDATIK уже существует"
    else
        ui_info "Создание NVRAM-записи SOLDATIK"
        if ! run_chroot efibootmgr \
                --create \
                --disk "${CONFIG[disk]}" \
                --part 1 \
                --label "SOLDATIK" \
                --loader '\EFI\SOLDATIK\grubx64.efi'; then
            ui_warn "Не удалось создать NVRAM-запись через efibootmgr"
            ui_warn "Fallback-загрузчик /EFI/BOOT/BOOTX64.EFI всё равно создан"
            ui_warn "Система загрузится через него"
        else
            ui_success "NVRAM-запись SOLDATIK создана"
        fi
    fi

    ui_success "GRUB установлен в UEFI"
}

# ═══════════════════════════════════════════════════════════
# GRUB для BIOS
# ═══════════════════════════════════════════════════════════

install_grub_bios() {
    [[ "${CONFIG[boot_mode]}" != "bios" ]] && return 0

    ui_step "Установка GRUB (BIOS)"

    if ! run_chroot grub-install \
            --target=i386-pc \
            --recheck \
            "${CONFIG[disk]}"; then
        ui_error "grub-install (BIOS) упал"
        return 1
    fi

    ui_success "GRUB установлен в BIOS"
}

# ═══════════════════════════════════════════════════════════
# Генерация grub.cfg
# ═══════════════════════════════════════════════════════════

generate_grub_config() {
    ui_step "Генерация grub.cfg"

    # Имя дистрибутива в меню
    run_chroot_sh "sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR=\"Soldatik\"/' /etc/default/grub"

    # Таймаут и дефолт
    run_chroot_sh "sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub"

    # Отключаем os-prober (мы не поддерживаем dual-boot)
    run_chroot_sh "echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub"

    if ! run_chroot grub-mkconfig -o /boot/grub/grub.cfg; then
        ui_error "grub-mkconfig упал"
        return 1
    fi

    ui_success "grub.cfg создан"
}

# ═══════════════════════════════════════════════════════════
# Общая функция
# ═══════════════════════════════════════════════════════════

run_boot_setup() {
    install_grub_uefi
    install_grub_bios
    generate_grub_config
}