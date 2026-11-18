#!/usr/bin/env bash
# lib/install.sh — pacstrap, настройка target, загрузчик и проверка

show_summary() {
    ui_title "Параметры установки"
    printf '  Цель              : %s\n' "$( [[ "$TARGET_MODE" == "disk" ]] && printf 'диск %s (полное стирание)' "$TARGET_DISK" || printf 'раздел %s (без изменения других разделов)' "$ROOT_PART" )"
    printf '  Загрузка          : %s\n' "${BOOT_MODE^^}"
    printf '  Разметка          : %s\n' "$( (( PARTITION_MODE == 0 )) && printf 'ESP + / + /home, ext4' || printf 'существующий ESP + /, ext4' )"
    printf '  LUKS шифрование   : %s\n' "$( (( LUKS == 1 )) && printf 'ВКЛ (LUKS2)' || printf 'ВЫКЛ' )"
    printf '  Swap              : %s\n' "${SWAP_SIZE} swap-файл"
    printf '  Профиль           : %s\n' "$PROFILE"
    printf '  Пользователь      : %s\n' "$USERNAME"
    printf '  Хостнейм          : %s\n' "$HOSTNAME"
    printf '  Локаль / время    : %s / %s\n' "$LOCALE" "$TIMEZONE"
    printf '  Раскладка         : us,ru (Alt+Shift)\n'
    printf '  Пакетов в списке  : %s\n' "${#TARGET_PACKAGES[@]}"
    printf '  Throne / zapret   : да / да\n'
    ui_hr
    if (( PARTITION_MODE == 0 )); then
        ui_warn "Все данные на $TARGET_DISK будут уничтожены."
    else
        ui_warn "Раздел $ROOT_PART будет отформатирован. Остальные разделы не затрагиваются."
    fi
}

copy_target_configs() {
    ui_step "Копирование конфигурации"

    [[ -d "$TARGET_CONFIG_DIR/skel" ]] || die "Не найдены skel-конфиги: $TARGET_CONFIG_DIR/skel"
    [[ -d "$MOUNTPOINT/etc/skel" ]] || die "В target нет /etc/skel (pacstrap не завершён?)"

    run_logged cp -a "$TARGET_CONFIG_DIR/skel/." "$MOUNTPOINT/etc/skel/"
    run_logged cp -a "$TARGET_CONFIG_DIR/etc/." "$MOUNTPOINT/etc/"

    # Права: root:root, каталоги 755, файлы 644.
    run_logged chown -R root:root "$MOUNTPOINT/etc/skel"
    find "$MOUNTPOINT/etc/skel" -type d -exec chmod 755 {} \;
    find "$MOUNTPOINT/etc/skel" -type f -exec chmod 644 {} \;

    ui_success "Конфиги Hyprland, SDDM, pacman и сети скопированы"
}

generate_target_fstab() {
    ui_step "Генерация /etc/fstab"
    : >"$MOUNTPOINT/etc/fstab"
    if ! run_logged sh -c "genfstab -U '$MOUNTPOINT' >> '$MOUNTPOINT/etc/fstab'"; then
        die "genfstab завершился с ошибкой"
    fi
    if [[ "$SWAP_SIZE" != "0" ]]; then
        printf '/swapfile none swap defaults 0 0\n' >>"$MOUNTPOINT/etc/fstab"
    fi
    ui_success "fstab создан"
}

filter_packages_by_profile() {
    local profile="$1"
    local -a filtered=()

    case "$profile" in
        minimal)
            # Только базовые пакеты (уже в TARGET_PACKAGES)
            filtered=("${TARGET_PACKAGES[@]}")
            ;;
        developer)
            filtered=("${TARGET_PACKAGES[@]}" base-devel git github-cli docker docker-compose podman buildah code nodejs npm pnpm python python-pip python-poetry rustup go lua luarocks zig cmake meson ninja gdb valgrind strace ltrace perf)
            ;;
        gaming)
            filtered=("${TARGET_PACKAGES[@]}" steam lutris wine winetricks gamemode lib32-gamemode mangohud lib32-mangohud vulkan-tools lib32-vulkan-icd-loader vulkan-validation-layers lib32-vulkan-validation-layers dxvk-bin vkd3d lib32-vkd3d)
            ;;
        full)
            filtered=("${TARGET_PACKAGES[@]}" base-devel git github-cli docker docker-compose podman buildah code nodejs npm pnpm python python-pip python-poetry rustup go lua luarocks zig cmake meson ninja gdb valgrind strace ltrace perf steam lutris wine winetricks gamemode lib32-gamemode mangohud lib32-mangohud vulkan-tools lib32-vulkan-icd-loader vulkan-validation-layers lib32-vulkan-validation-layers dxvk-bin vkd3d lib32-vkd3d)
            ;;
        *)
            die "Неизвестный профиль: $profile"
            ;;
    esac

    # Убираем дубликаты
    local -A seen=()
    local -a unique=()
    local pkg
    for pkg in "${filtered[@]}"; do
        [[ -n "${seen[$pkg]}" ]] || { unique+=("$pkg"); seen[$pkg]=1; }
    done
    TARGET_PACKAGES=("${unique[@]}")
}

run_pacstrap() {
    ui_step "Установка пакетов (офлайн-репозиторий)"

    # Фильтруем пакеты по профилю
    filter_packages_by_profile "$PROFILE"

    ui_info "Пакетов: ${#TARGET_PACKAGES[@]}. Это самый долгий этап."

    if ! run_with_spinner "Установка системы" \
        pacstrap -C "$OFFLINE_PACMAN_CONF" -K -M "$MOUNTPOINT" "${TARGET_PACKAGES[@]}"; then
        ui_error "pacstrap завершился с ошибкой. Последние строки лога:"
        log_tail 30
        die "Не удалось установить пакеты"
    fi

    if [[ -d "$MOUNTPOINT/var/cache/pacman/pkg" ]]; then
        find "$MOUNTPOINT/var/cache/pacman/pkg" -mindepth 1 -delete 2>/dev/null || true
    fi

    ui_success "Пакеты установлены"
}

run_target_setup() {
    ui_step "Настройка системы"

    local setup_env="$MOUNTPOINT/root/soldarch-setup.env"
    local user_hash
    user_hash=$(openssl passwd -6 "$PASSWORD") || die "Не удалось захэшировать пароль"

    umask 077
    cat >"$setup_env" <<EOF
SOLDARCH_HOSTNAME='$HOSTNAME'
SOLDARCH_USER='$USERNAME'
SOLDARCH_USER_HASH='$user_hash'
SOLDARCH_TIMEZONE='$TIMEZONE'
SOLDARCH_LOCALE='$LOCALE'
SOLDARCH_KEYMAP='$KEYMAP'
SOLDARCH_AUTOLOGIN='$AUTOLOGIN'
SOLDARCH_SERIAL_CONSOLE='$SERIAL_CONSOLE'
SOLDARCH_LUKS='$LUKS'
SOLDARCH_LUKS_PASSWORD='$LUKS_PASSWORD'
SOLDARCH_PROFILE='$PROFILE'
EOF
    chmod 600 "$setup_env"
    umask 022

    cp "$SOLDARCH_DIR/target-setup.sh" "$MOUNTPOINT/root/soldarch-setup.sh"
    chmod 755 "$MOUNTPOINT/root/soldarch-setup.sh"

    if ! run_chroot /bin/bash /root/soldarch-setup.sh; then
        ui_error "Настройка target завершилась с ошибкой"
        log_tail 30
        die "Ошибка настройки системы"
    fi

    rm -f "$setup_env" "$MOUNTPOINT/root/soldarch-setup.sh"
    ui_success "Система настроена"
}

install_bootloader() {
    ui_step "Установка загрузчика GRUB"

    local serial_cmd=""
    if (( SERIAL_CONSOLE == 1 )); then
        serial_cmd=' console=tty0 console=ttyS0,115200'
    fi

    if [[ "$BOOT_MODE" == "uefi" ]]; then
        [[ -n "$EFI_PART" && -n "$ESP_DISK" && -n "$ESP_NUM" ]] || die "Не определены параметры ESP"

        if ! run_chroot grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot/efi \
            --bootloader-id=Arch \
            --no-nvram \
            --recheck; then
            die "grub-install (UEFI) завершился с ошибкой"
        fi

        # Fallback для прошивок, которые не видят NVRAM-запись.
        run_logged mkdir -p "$MOUNTPOINT/boot/efi/EFI/BOOT"
        run_logged cp "$MOUNTPOINT/boot/efi/EFI/Arch/grubx64.efi" \
            "$MOUNTPOINT/boot/efi/EFI/BOOT/BOOTX64.EFI"

        # efibootmgr должен работать в live-окружении: в chroot нет
        # смонтированного efivarfs, и запись NVRAM молча не создаётся.
        if ! efibootmgr --create --disk "$ESP_DISK" --part "$ESP_NUM" \
            --label "Arch Linux" --loader '\EFI\Arch\grubx64.efi'; then
            ui_warn "Не удалось создать NVRAM-запись; останется fallback BOOTX64.EFI"
        fi
    else
        if ! run_chroot grub-install --target=i386-pc --recheck "$TARGET_DISK"; then
            die "grub-install (BIOS) завершился с ошибкой"
        fi
    fi

    cat >"$MOUNTPOINT/etc/default/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="Arch"
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet${serial_cmd}"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
GRUB_PRELOAD_MODULES="part_gpt part_msdos"
EOF
    if (( SERIAL_CONSOLE == 1 )); then
        cat >>"$MOUNTPOINT/etc/default/grub" <<'EOF'
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"
EOF
    fi

    if ! run_chroot grub-mkconfig -o /boot/grub/grub.cfg; then
        die "grub-mkconfig завершился с ошибкой"
    fi

    ui_success "GRUB установлен"
}

verify_install() {
    ui_step "Проверка установки"
    local errors=0

    check_file() {
        if [[ ! -e "$1" ]]; then
            ui_error "Нет: $1"
            errors=$((errors + 1))
        fi
    }

    check_link() {
        if [[ ! -L "$1" ]]; then
            ui_error "Не включён (нет symlink): $1"
            errors=$((errors + 1))
        fi
    }

    check_file "$MOUNTPOINT/etc/skel/.config/hypr/hyprland.lua"
    check_file "$MOUNTPOINT/etc/skel/.config/waybar/config.jsonc"
    check_file "$MOUNTPOINT/etc/sddm.conf.d/10-soldarch.conf"
    check_file "$MOUNTPOINT/boot/grub/grub.cfg"
    check_link "$MOUNTPOINT/etc/systemd/system/display-manager.service"

    if ! grep -q "^${USERNAME}:" "$MOUNTPOINT/etc/passwd"; then
        ui_error "Пользователь ${USERNAME} не создан"
        errors=$((errors + 1))
    fi

    if ! grep -q '^root:!' "$MOUNTPOINT/etc/shadow"; then
        ui_error "Root не заблокирован"
        errors=$((errors + 1))
    fi

    local -a required_pkgs=(hyprland sddm throne-bin soldarch-zapret firefox foot)
    local pkg
    for pkg in "${required_pkgs[@]}"; do
        if ! run_chroot pacman -Q "$pkg" >/dev/null 2>&1; then
            ui_error "Не установлен пакет: $pkg"
            errors=$((errors + 1))
        fi
    done

    if ! run_chroot systemctl is-enabled sddm >/dev/null 2>&1; then
        ui_error "SDDM не включён"
        errors=$((errors + 1))
    fi
    check_link "$MOUNTPOINT/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
    check_link "$MOUNTPOINT/etc/systemd/system/multi-user.target.wants/iwd.service"
    check_link "$MOUNTPOINT/etc/systemd/system/bluetooth.target.wants/bluetooth.service"
    if [[ -f "$MOUNTPOINT/usr/lib/systemd/system/zapret.service" ]]; then
        check_link "$MOUNTPOINT/etc/systemd/system/multi-user.target.wants/zapret.service"
    else
        ui_error "Нет unit-файла zapret.service"
        errors=$((errors + 1))
    fi
    if [[ -f "$MOUNTPOINT/usr/lib/systemd/system/zapret-list-update.timer" ]]; then
        check_link "$MOUNTPOINT/etc/systemd/system/timers.target.wants/zapret-list-update.timer"
    fi

    local group
    for group in wheel video render audio input storage optical network rfkill; do
        if ! grep -q "^${group}:" "$MOUNTPOINT/etc/group"; then
            ui_error "Нет группы: ${group}"
            errors=$((errors + 1))
        fi
    done

    if (( errors > 0 )); then
        die "Проверка установки нашла $errors ошибок"
    fi
    ui_success "Все проверки пройдены"
}

run_installation() {
    show_summary
    if (( ASSUME_YES == 0 )); then
        if ! ui_confirm "Начать установку?" "n"; then
            ui_info "Отменено"
            return 1
        fi
    fi

    log "=== Installation started ==="
    log "mode=$TARGET_MODE disk=$TARGET_DISK root=$ROOT_PART efi=$EFI_PART boot=$BOOT_MODE"

    if (( PARTITION_MODE == 0 )); then
        partition_disk "$TARGET_DISK"
    else
        ui_step "Используется существующий раздел $ROOT_PART"
        HOME_PART=""
        if [[ -z "$EFI_PART" ]]; then
            select_esp_interactive || return 1
        fi
    fi

    format_partitions
    mount_target
    create_swapfile
    run_pacstrap
    copy_target_configs
    generate_target_fstab
    run_target_setup
    install_bootloader
    verify_install
    unmount_target

    INSTALL_SUCCESS=1
    log "=== Installation completed successfully ==="

    clear
    ui_title "Soldarch установлен"
    ui_success "Система установлена на $TARGET_DISK${ROOT_PART:+ / $ROOT_PART}"
    printf '\n'
    printf '  Пользователь : %s\n' "$USERNAME"
    printf '  Пароль       : задан при установке\n'
    printf '  Хостнейм     : %s\n' "$HOSTNAME"
    printf '  Графика      : Hyprland + SDDM\n'
    printf '  Throne       : установлен\n'
    printf '  Zapret       : установлен и включён\n'
    printf '  Лог          : %s\n' "$LOGFILE"
    printf '\n'

    if (( AUTO == 1 )); then
        case "$ACTION" in
            reboot) log "Auto reboot"; sync; reboot ;;
            poweroff) log "Auto poweroff"; sync; poweroff -f ;;
            *) log "Auto: no reboot" ;;
        esac
        exit 0
    fi

    if ui_confirm "Перезагрузить сейчас?" "y"; then
        log "User reboot"
        sync
        reboot
    else
        ui_info "Извлеките ISO и перезагрузитесь вручную."
        ui_pause
    fi
    exit 0
}
