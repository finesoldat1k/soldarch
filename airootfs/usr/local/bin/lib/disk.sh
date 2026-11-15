#!/usr/bin/env bash
# lib/disk.sh — выбор диска, разметка, форматирование

# ═══════════════════════════════════════════════════════════
# Меню
# ═══════════════════════════════════════════════════════════

menu_select_disk() {
    local disks=() display=()

    while IFS='|' read -r name info; do
        [[ -z "$name" ]] && continue
        disks+=("/dev/$name")
        display+=("$info")
    done < <(list_disks_detailed)

    if [[ ${#disks[@]} -eq 0 ]]; then
        ui_error "Диски не найдены"
        ui_pause
        return 1
    fi

    display+=("Отмена")

    local n
    n=$(ui_menu "Выберите диск для установки:" "${display[@]}")

    # Отмена
    (( n == ${#disks[@]} + 1 )) && return 1

    local disk="${disks[$((n-1))]}"
    local bytes
    bytes=$(blockdev --getsize64 "$disk")
    local gb=$(( bytes / 1024 / 1024 / 1024 ))

    if (( gb < 8 )); then
        ui_error "Диск слишком мал: ${gb} ГБ (минимум 8 ГБ)"
        ui_pause
        return 1
    fi

    CONFIG[disk]="$disk"
    CONFIG[disk_size]=$(numfmt --to=iec --suffix=B "$bytes")

    ui_success "Выбран: $disk (${CONFIG[disk_size]})"
    sleep 1
}

menu_select_partitioning() {
    local n
    n=$(ui_menu "Способ разметки:" \
        "Автоматическая (рекомендуется)" \
        "Ручная (cfdisk)")

    case "$n" in
        1) CONFIG[partitioning]="auto" ;;
        2) CONFIG[partitioning]="manual" ;;
    esac
}

menu_select_fs() {
    CONFIG[fs]=$(ui_choose "Файловая система для корня:" \
        "ext4|Классика, надёжно (рекомендуется)" \
        "btrfs|Снапшоты, сжатие" \
        "xfs|Для больших файлов")
}

menu_select_swap() {
    local n
    n=$(ui_menu "Swap:" \
        "Без swap" \
        "Swap-файл 2 ГБ" \
        "Swap-файл 4 ГБ" \
        "Swap-файл 8 ГБ")

    case "$n" in
        1) CONFIG[swap]="none"; CONFIG[swap_size]="0" ;;
        2) CONFIG[swap]="file"; CONFIG[swap_size]="2G" ;;
        3) CONFIG[swap]="file"; CONFIG[swap_size]="4G" ;;
        4) CONFIG[swap]="file"; CONFIG[swap_size]="8G" ;;
    esac
}

# ═══════════════════════════════════════════════════════════
# Автоматическая разметка
# ═══════════════════════════════════════════════════════════

partition_disk_auto() {
    local disk="${CONFIG[disk]}"
    local mode="${CONFIG[boot_mode]}"
    local root_start_mb root_end_mb

    ui_step "Разметка $disk (режим: $mode, схема: ESP + root + /home)"
    log "Auto partition: disk=$disk mode=$mode fs=${CONFIG[fs]}"

    # ─── Полная очистка диска ───
    ui_step "Очистка $disk от старых разделов и ФС"

    # 1. Размонтировать всё, что относится к этому диску
    local part
    while read -r part; do
        [[ -z "$part" ]] && continue
        run_cmd umount -f "$part" 2>/dev/null || true
    done < <(lsblk -lpno NAME "$disk" | tac)

    run_cmd umount -R "$MOUNTPOINT" 2>/dev/null || true
    run_cmd swapoff -a || true

    # 2. Удалить все существующие разделы
    if command -v sgdisk &>/dev/null; then
        run_cmd sgdisk --zap-all "$disk" || {
            ui_warn "sgdisk --zap-all не сработал, продолжаем"
        }
    fi

    # 3. Стереть сигнатуры файловых систем
    run_cmd wipefs -a "$disk" || {
        ui_error "wipefs $disk не удался"
        return 1
    }

    # 4. Затереть начало и конец диска (первые/последние 10 МБ)
    #    Это удаляет остатки GPT backup и MBR bootstrap
    ui_step "Затирание первые и последние 10 МБ диска"
    run_cmd dd if=/dev/zero of="$disk" bs=1M count=10 conv=fsync status=none || {
        ui_error "dd (начало) не удался"
        return 1
    }
    local disk_size_mb=$(( $(blockdev --getsize64 "$disk") / 1024 / 1024 ))
    run_cmd dd if=/dev/zero of="$disk" bs=1M count=10 seek=$(( disk_size_mb - 10 )) \
        conv=fsync status=none || {
        ui_error "dd (конец) не удался"
        return 1
    }

    # 5. Синхронизировать и перечитать таблицу
    run_cmd sync
    run_cmd partprobe "$disk" 2>/dev/null || true
    sleep 1

    # ─── Считаем размер root ───
    local total_mb
    total_mb=$(( $(blockdev --getsize64 "$disk") / 1024 / 1024 ))

    local root_mb
    if (( total_mb >= 100 * 1024 )); then
        root_mb=$(( 40 * 1024 ))         # 40 GiB для больших дисков
    else
        root_mb=$(( total_mb / 2 ))      # 50% для маленьких
    fi

    run_cmd parted -s "$disk" mklabel gpt || return 1

    if [[ "$mode" == "uefi" ]]; then
        # ESP + root
        run_cmd parted -s "$disk" mkpart ESP fat32 1MiB 513MiB || return 1
        run_cmd parted -s "$disk" set 1 esp on                 || return 1

        root_start_mb=513
        root_end_mb=$(( 513 + root_mb ))

        run_cmd parted -s "$disk" mkpart root "${CONFIG[fs]}" "${root_start_mb}MiB" "${root_end_mb}MiB" || return 1
        run_cmd parted -s "$disk" mkpart home "${CONFIG[fs]}" "${root_end_mb}MiB" 100%                  || return 1

        CONFIG[efi_part]=$(part_name "$disk" 1)
        CONFIG[root_part]=$(part_name "$disk" 2)
        CONFIG[home_part]=$(part_name "$disk" 3)
    else
        run_cmd parted -s "$disk" mkpart bios_grub 1MiB 2MiB         || return 1
        run_cmd parted -s "$disk" set 1 bios_grub on                 || return 1

        root_start_mb=2
        root_end_mb=$(( 2 + root_mb ))

        run_cmd parted -s "$disk" mkpart root "${CONFIG[fs]}" "${root_start_mb}MiB" "${root_end_mb}MiB" || return 1
        run_cmd parted -s "$disk" mkpart home "${CONFIG[fs]}" "${root_end_mb}MiB" 100%                        || return 1

        CONFIG[efi_part]=""
        CONFIG[root_part]=$(part_name "$disk" 2)
        CONFIG[home_part]=$(part_name "$disk" 3)
    fi

    run_cmd partprobe "$disk" || {
        ui_error "partprobe $disk не удался"
        return 1
    }
    sleep 2

    CONFIG[disk_formatted]="y"
    ui_success "Диск размечен: root=${root_mb}MiB, home=остаток"
    log "EFI=${CONFIG[efi_part]} ROOT=${CONFIG[root_part]} HOME=${CONFIG[home_part]}"
}

# ═══════════════════════════════════════════════════════════
# Ручная разметка (cfdisk)
# ═══════════════════════════════════════════════════════════

partition_disk_manual() {
    local disk="${CONFIG[disk]}"

    clear
    ui_title "Ручная разметка $disk"

    echo
    ui_info "Сейчас запустится cfdisk — интерактивный редактор разделов."
    ui_info "Разметьте диск вручную, затем выйдите (Quit)."
    echo
    ui_info "Рекомендуемая схема для UEFI:"
    ui_info "  1) 512 МБ, тип: EFI System"
    ui_info "  2) Остальное, тип: Linux filesystem"
    echo
    ui_info "Рекомендуемая схема для BIOS:"
    ui_info "  1) 1 МБ, тип: BIOS boot"
    ui_info "  2) Остальное, тип: Linux filesystem"
    echo
    ui_info "⚠  Не форматируйте разделы внутри cfdisk — это сделает установщик."
    echo
    ui_pause

    run_cmd umount -R "$MOUNTPOINT" || true
    run_cmd swapoff -a || true

    # cfdisk интерактивный — без run_cmd, без редиректов
    cfdisk "$disk" || {
        ui_error "cfdisk завершился с ошибкой"
        ui_pause
        return 1
    }

    run_cmd partprobe "$disk" || {
        ui_error "partprobe $disk не удался"
        return 1
    }
    sleep 2

    # Собираем разделы
    local parts=() display=()
    while read -r name size fstype; do
        [[ -z "$name" ]] && continue
        parts+=("/dev/$name")
        display+=("$name   $size   ${fstype:-—}")
    done < <(lsblk -lno NAME,SIZE,FSTYPE "$disk" | tail -n +2)

    if [[ ${#parts[@]} -eq 0 ]]; then
        ui_error "На диске нет разделов"
        ui_pause
        return 1
    fi

    # Выбор root
    local n
    n=$(ui_menu "Какой раздел использовать как / (root)?" "${display[@]}")
    CONFIG[root_part]="${parts[$((n-1))]}"

    # Выбор EFI (только для UEFI)
    if [[ "${CONFIG[boot_mode]}" == "uefi" ]]; then
        n=$(ui_menu "Какой раздел использовать как /boot/efi?" "${display[@]}")
        CONFIG[efi_part]="${parts[$((n-1))]}"
    else
        CONFIG[efi_part]=""
    fi

    # ─── Опционально: /home ───
    CONFIG[home_part]=""
    if ui_confirm "Использовать отдельный раздел для /home?" "n"; then
        n=$(ui_menu "Какой раздел использовать как /home?" "${display[@]}")
        CONFIG[home_part]="${parts[$((n-1))]}"
        log "Manual: HOME=${CONFIG[home_part]}"
    fi

    CONFIG[disk_formatted]="y"
    ui_success "Разделы выбраны"
    log "Manual: EFI=${CONFIG[efi_part]} ROOT=${CONFIG[root_part]}"
}

# ═══════════════════════════════════════════════════════════
# Форматирование
# ═══════════════════════════════════════════════════════════

format_partitions() {
    local root="${CONFIG[root_part]}"
    local efi="${CONFIG[efi_part]}"
    local home="${CONFIG[home_part]}"
    local fs="${CONFIG[fs]}"

    [[ -z "$root" ]] && {
        ui_error "Root-раздел не задан"
        return 1
    }

    # ─── EFI ───
    if [[ -n "$efi" ]]; then
        ui_step "Форматирование EFI: $efi"

        if mountpoint -q "$efi" 2>/dev/null; then
            ui_warn "$efi уже смонтирован — размонтируем"
            run_cmd umount "$efi" || true
        fi

        run_cmd wipefs -a "$efi" || { ui_error "wipefs $efi не удался"; return 1; }
        run_cmd mkfs.fat -F32 -I "$efi" || { ui_error "mkfs.fat $efi не удался"; return 1; }

        local efi_type
        efi_type=$(blkid -s TYPE -o value "$efi" 2>/dev/null)
        [[ "$efi_type" != "vfat" ]] && {
            ui_error "$efi не vfat (получено: ${efi_type:-пусто})"
            return 1
        }
        ui_success "EFI отформатирован (vfat)"
    fi

    # ─── Root ───
    _format_one "$root" "$fs" "root" || return 1

    # ─── Home ───
    if [[ -n "$home" ]]; then
        _format_one "$home" "$fs" "home" || return 1
    fi

    ui_success "Разделы отформатированы"
}

# ─── Вспомогательная: форматирование одного раздела ───
_format_one() {
    local part="$1" fs="$2" label="$3"

    ui_step "Форматирование /$label: $part"

    if mountpoint -q "$part" 2>/dev/null; then
        ui_warn "$part уже смонтирован — размонтируем"
        run_cmd umount "$part" || true
    fi

    run_cmd wipefs -a "$part" || {
        ui_error "wipefs $part не удался"
        return 1
    }

    case "$fs" in
        ext4)  run_cmd mkfs.ext4  -F "$part" || { ui_error "mkfs.ext4 $part не удался";  return 1; } ;;
        btrfs) run_cmd mkfs.btrfs -f "$part" || { ui_error "mkfs.btrfs $part не удался"; return 1; } ;;
        xfs)   run_cmd mkfs.xfs   -f "$part" || { ui_error "mkfs.xfs $part не удался";   return 1; } ;;
        *)     ui_error "Неизвестная ФС: $fs"; return 1 ;;
    esac

    local part_type
    part_type=$(blkid -s TYPE -o value "$part" 2>/dev/null)

    if [[ "$part_type" != "$fs" ]]; then
        ui_error "$part не $fs после форматирования (получено: ${part_type:-пусто})"
        return 1
    fi

    ui_success "/$label отформатирован ($fs)"
    return 0
}
