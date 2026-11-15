#!/usr/bin/env bash
# lib/mount.sh — монтирование разделов и swap

# ─── Монтирование root ───
mount_root() {
    local root="${CONFIG[root_part]}"

    [[ -z "$root" ]] && {
        ui_error "Root-раздел не задан"
        return 1
    }

    ui_step "Монтирование $root → $MOUNTPOINT"
    run_cmd mkdir -p "$MOUNTPOINT"
    run_cmd mount "$root" "$MOUNTPOINT"
}

# ─── Монтирование home ───
mount_home() {
    local home="${CONFIG[home_part]:-}"
    [[ -z "$home" ]] && return 0

    ui_step "Монтирование $home → $MOUNTPOINT/home"
    run_cmd mkdir -p "$MOUNTPOINT/home" || return 1
    if ! run_cmd mount "$home" "$MOUNTPOINT/home"; then
        ui_error "Не удалось примонтировать /home"
        return 1
    fi
}

# ─── Монтирование EFI ───
mount_efi() {
    local efi="${CONFIG[efi_part]}"

    [[ -z "$efi" ]] && return 0

    ui_step "Монтирование $efi → $MOUNTPOINT/boot/efi"
    run_cmd mkdir -p "$MOUNTPOINT/boot/efi"
    run_cmd mount "$efi" "$MOUNTPOINT/boot/efi"
}

# ─── Swap-файл ───
setup_swap() {
    if [[ "${CONFIG[swap]}" == "none" ]]; then
        ui_info "Swap отключён в настройках"
        return 0
    fi

    local size="${CONFIG[swap_size]}"
    local fs="${CONFIG[fs]}"
    local swapfile="$MOUNTPOINT/swapfile"

    ui_step "Создание swap-файла ${size}"

    if [[ "$fs" == "btrfs" ]]; then
        # btrfs требует chattr +C до создания файла
        run_cmd touch "$swapfile"
        run_cmd chattr +C "$swapfile" 2>/dev/null || true
    fi

    # Размер в мегабайтах
    local mb
    mb=$(( ${size%G} * 1024 ))

    if ! run_cmd fallocate -l "$size" "$swapfile" 2>/dev/null; then
        log "fallocate не сработал, используем dd"
        run_cmd dd if=/dev/zero of="$swapfile" bs=1M count="$mb" status=none
    fi

    run_cmd chmod 600 "$swapfile"
    run_cmd mkswap "$swapfile"

    ui_success "Swap-файл ${size} создан"
}

# ─── Размонтирование ───
umount_all() {
    ui_step "Размонтирование $MOUNTPOINT"

    # Сначала swapoff на swapfile, если он есть
    if [[ -f "$MOUNTPOINT/swapfile" ]]; then
        run_cmd swapoff "$MOUNTPOINT/swapfile" 2>/dev/null || true
    fi

    run_cmd umount -R "$MOUNTPOINT" 2>/dev/null || true
    run_cmd swapoff -a 2>/dev/null || true
}
