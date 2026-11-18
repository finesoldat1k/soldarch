#!/usr/bin/env bash
# lib/disk.sh — выбор цели, разметка, форматирование и монтирование

# ─────────────────────────────────────────────────────────────
# Списки устройств
# ─────────────────────────────────────────────────────────────
# lsblk -P печатает NAME="..." SIZE="..." ...; обычный read с пустым
# FSTYPE сдвигал бы поля, поэтому разбираем пары ключ=значение.
lsblk_field() {
    local line="$1" key="$2"
    if [[ "$line" =~ (^|[[:space:]])${key}=\"([^\"]*)\" ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
    fi
}

list_target_disks() {
    local live line name size type model
    live=$(live_disk || true)
    while IFS= read -r line; do
        name=$(lsblk_field "$line" NAME)
        size=$(lsblk_field "$line" SIZE)
        type=$(lsblk_field "$line" TYPE)
        model=$(lsblk_field "$line" MODEL)
        [[ "$type" == "disk" ]] || continue
        case "$name" in
            /dev/loop*|/dev/sr*|/dev/zram*|/dev/ram*|/dev/dm-*|/dev/md*) continue ;;
        esac
        [[ -n "$live" && "$name" == "$live" ]] && continue
        model="${model:-без модели}"
        printf '%s|%s  %s\n' "$name" "$size" "$model"
    done < <(lsblk -dpno NAME,SIZE,TYPE,MODEL -P 2>/dev/null)
}

list_all_partitions() {
    local live line name size fstype type
    live=$(live_disk || true)
    while IFS= read -r line; do
        name=$(lsblk_field "$line" NAME)
        size=$(lsblk_field "$line" SIZE)
        fstype=$(lsblk_field "$line" FSTYPE)
        type=$(lsblk_field "$line" TYPE)
        [[ "$type" == "part" ]] || continue
        [[ -n "$live" && "$name" == "$live"* ]] && continue
        printf '%s|%s  %s  %s\n' "$name" "$size" "${fstype:-нет ФС}" "${name##*/}"
    done < <(lsblk -pno NAME,SIZE,FSTYPE,TYPE -P 2>/dev/null)
}

list_esp_candidates() {
    local live line name size fstype parttype type
    live=$(live_disk || true)
    while IFS= read -r line; do
        name=$(lsblk_field "$line" NAME)
        size=$(lsblk_field "$line" SIZE)
        fstype=$(lsblk_field "$line" FSTYPE)
        parttype=$(lsblk_field "$line" PARTTYPE)
        type=$(lsblk_field "$line" TYPE)
        [[ -n "$name" && "$type" == "part" ]] || continue
        [[ -n "$live" && "$name" == "$live"* ]] && continue
        if [[ "${parttype,,}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" || "$fstype" == "vfat" ]]; then
            printf '%s|%s  %s  ESP\n' "$name" "$size" "${fstype:-?}"
        fi
    done < <(lsblk -pno NAME,SIZE,FSTYPE,PARTTYPE,TYPE -P 2>/dev/null)
}

partition_number_from_path() {
    lsblk -no PARTN "$1" 2>/dev/null | head -n1 | tr -d ' '
}

# ─────────────────────────────────────────────────────────────
# Выбор цели
# ─────────────────────────────────────────────────────────────
select_target_interactive() {
    while true; do
        local -a disks=() items=()
        local name info
        while IFS='|' read -r name info; do
            [[ -n "$name" ]] || continue
            disks+=("$name")
            items+=("$info")
        done < <(list_target_disks)

        items+=("Установить в существующий раздел (dual-boot)")

        ui_title "Куда установить Soldarch?"
        ui_info "Режим загрузки: ${BOOT_MODE^^}"
        ui_info "Данные на выбранном диске будут полностью уничтожены."
        printf '\n'

        local choice
        choice=$(ui_menu "Выберите диск или раздел:" "${items[@]}") || return 1
        (( choice == 0 )) && return 1

        if (( choice == ${#items[@]} )); then
            select_existing_partition || continue
            return 0
        fi

        local disk="${disks[$((choice - 1))]}"
        local gb
        gb=$(( $(blockdev --getsize64 "$disk") / 1024 / 1024 / 1024 ))
        if (( gb < 32 )); then
            ui_error "Диск слишком мал: ${gb} ГБ. Нужно минимум 32 ГБ."
            ui_pause
            continue
        fi

        TARGET_MODE="disk"
        TARGET_DISK="$disk"
        PARTITION_MODE=0
        ui_warn "Весь диск $disk (${gb} ГБ) будет размечен заново."
        if (( gb < 48 )); then
            ui_warn "Для полного набора приложений рекомендуется диск от 48 ГБ."
        fi
        if ! ui_confirm "Стереть $disk и продолжить?" "n"; then
            continue
        fi
        local typed
        typed=$(ui_prompt "Для подтверждения введите YES" "")
        if [[ "${typed^^}" != "YES" ]]; then
            ui_error "Подтверждение не получено"
            ui_pause
            continue
        fi
        return 0
    done
}

select_existing_partition() {
    if [[ "$BOOT_MODE" == "bios" ]]; then
        ui_error "Установка в существующий раздел поддерживается только в UEFI-режиме."
        ui_error "В BIOS нужен отдельный BIOS boot раздел; используйте установку на весь диск."
        ui_pause
        return 1
    fi

    local -a parts=() items=()
    local name info
    while IFS='|' read -r name info; do
        [[ -n "$name" ]] || continue
        parts+=("$name")
        items+=("$info")
    done < <(list_all_partitions)

    if (( ${#parts[@]} == 0 )); then
        ui_error "Разделы не найдены"
        ui_pause
        return 1
    fi

    local choice
    choice=$(ui_menu "Какой раздел использовать как корень /? Он будет отформатирован в ext4:" "${items[@]}") || return 1
    (( choice == 0 )) && return 1
    local root="${parts[$((choice - 1))]}"

    local size_mb
    size_mb=$(( $(blockdev --getsize64 "$root") / 1024 / 1024 ))
    if (( size_mb < 24 * 1024 )); then
        ui_error "Раздел слишком мал: $((size_mb / 1024)) ГБ. Нужно минимум 24 ГБ."
        ui_pause
        return 1
    fi

    ROOT_PART="$root"
    TARGET_MODE="partition"
    PARTITION_MODE=1
    HOME_PART=""
    EFI_PART=""

    select_esp_interactive || return 1
    return 0
}

select_esp_interactive() {
    local -a esps=() items=()
    local name info
    while IFS='|' read -r name info; do
        [[ -n "$name" ]] || continue
        esps+=("$name")
        items+=("$info")
    done < <(list_esp_candidates)

    if (( ${#esps[@]} == 0 )); then
        ui_error "Не найден EFI-раздел (ESP, vfat). Для UEFI-установки он обязателен."
        ui_pause
        return 1
    fi

    if (( ${#esps[@]} == 1 )); then
        EFI_PART="${esps[0]}"
        ui_info "Используется существующий ESP: $EFI_PART"
    else
        local choice
        choice=$(ui_menu "Какой раздел использовать как ESP (монтируется в /boot)? Он НЕ будет форматироваться:" "${items[@]}") || return 1
        (( choice == 0 )) && return 1
        EFI_PART="${esps[$((choice - 1))]}"
    fi

    ESP_DISK="/dev/$(disk_of_part "$EFI_PART")"
    ESP_NUM=$(partition_number_from_path "$EFI_PART")
    if [[ -z "$ESP_NUM" || ! -b "$ESP_DISK" ]]; then
        ui_error "Не удалось определить диск ESP: $EFI_PART"
        return 1
    fi
    return 0
}

select_target_auto() {
    if [[ "$TARGET_MODE" == "disk" ]]; then
        [[ -b "$TARGET_DISK" ]] || die "Диск не найден: $TARGET_DISK"
        [[ "$(lsblk -dno TYPE "$TARGET_DISK" 2>/dev/null)" == "disk" ]] || \
            die "Это не целый диск: $TARGET_DISK"
        local live
        live=$(live_disk || true)
        [[ -n "$live" && "$TARGET_DISK" == "$live" ]] && die "Нельзя установить на диск, с которого загружен live-ISO"
        PARTITION_MODE=0
        TARGET_DISK="$(readlink -f "$TARGET_DISK")"
        return 0
    fi

    if [[ "$TARGET_MODE" == "partition" ]]; then
        [[ -b "$ROOT_PART" ]] || die "Раздел не найден: $ROOT_PART"
        [[ "$(lsblk -dno TYPE "$ROOT_PART" 2>/dev/null)" == "part" ]] || \
            die "Это не раздел: $ROOT_PART"
        PARTITION_MODE=1
        TARGET_MODE="partition"
        HOME_PART=""
        ROOT_PART="$(readlink -f "$ROOT_PART")"

        if [[ "$BOOT_MODE" == "bios" ]]; then
            die "Установка в раздел в BIOS не поддерживается. Используйте --disk."
        fi

        if [[ -n "$EFI_PART" ]]; then
            [[ -b "$EFI_PART" ]] || die "ESP не найден: $EFI_PART"
            [[ "$(blkid -s TYPE -o value "$EFI_PART" 2>/dev/null)" == "vfat" ]] || \
                die "ESP должен быть vfat: $EFI_PART"
        else
            local -a esps=()
            local n
            while IFS='|' read -r n _; do
                [[ -n "$n" ]] && esps+=("$n")
            done < <(list_esp_candidates)
            (( ${#esps[@]} > 0 )) || die "Не найден ESP. Укажите --efi /dev/... вручную."
            EFI_PART="${esps[0]}"
        fi

        ESP_DISK="/dev/$(disk_of_part "$EFI_PART")"
        ESP_NUM=$(partition_number_from_path "$EFI_PART")
        [[ -n "$ESP_NUM" && -b "$ESP_DISK" ]] || die "Не удалось определить ESP-диск"
        return 0
    fi

    die "Не задан диск или раздел"
}

# ─────────────────────────────────────────────────────────────
# Разметка и форматирование
# ─────────────────────────────────────────────────────────────
wipe_disk() {
    local disk="$1"
    local p
    while read -r p; do
        [[ -n "$p" ]] || continue
        umount -R "$p" 2>/dev/null || true
        swapoff "$p" 2>/dev/null || true
    done < <(lsblk -lpno NAME "$disk" | tac)

    run_logged sgdisk --zap-all "$disk" || wipefs -a "$disk" >/dev/null 2>&1 || true
    run_logged wipefs -a "$disk"

    local size_mb
    size_mb=$(( $(blockdev --getsize64 "$disk") / 1024 / 1024 ))
    run_logged dd if=/dev/zero of="$disk" bs=1M count=1 conv=fsync status=none
    run_logged dd if=/dev/zero of="$disk" bs=1M count=1 seek=$((size_mb - 1)) conv=fsync status=none

    run_logged partprobe "$disk" || true
    udevadm settle || true
}

luks_format_partition() {
    local part="$1" password="$2" label="$3"
    ui_step "LUKS2 форматирование $part ($label)"
    echo -n "$password" | run_logged cryptsetup luksFormat --type luks2 --label "$label" "$part" -
    echo -n "$password" | run_logged cryptsetup open "$part" "$label" -
    sleep 1
    ui_success "LUKS контейнер $label создан и открыт"
}

partition_disk() {
    local disk="$1"
    local total_mb usable_mb root_start_mb root_mb home_start_mb
    local esp_start_mb=1 esp_end_mb=1025

    total_mb=$(( $(blockdev --getsize64 "$disk") / 1024 / 1024 ))
    if (( total_mb < 32 * 1024 )); then
        die "Диск слишком мал: $((total_mb / 1024)) ГБ (минимум 32 ГБ)"
    fi

    ui_step "Разметка $disk (${total_mb} МиБ)"
    wipe_disk "$disk"

    run_logged parted -s "$disk" mklabel gpt

    if [[ "$BOOT_MODE" == "uefi" ]]; then
        run_logged parted -s "$disk" mkpart ESP fat32 "${esp_start_mb}MiB" "${esp_end_mb}MiB"
        run_logged parted -s "$disk" set 1 esp on
        root_start_mb="$esp_end_mb"
    else
        run_logged parted -s "$disk" mkpart bios_grub 1MiB 2MiB
        run_logged parted -s "$disk" set 1 bios_grub on
        root_start_mb=2
    fi

    usable_mb=$(( total_mb - root_start_mb ))
    root_mb=$(( usable_mb / 2 ))
    (( root_mb > 60 * 1024 )) && root_mb=$((60 * 1024))
    (( root_mb < ROOT_MIN_MB )) && root_mb="$ROOT_MIN_MB"
    if (( root_mb > usable_mb - HOME_MIN_MB )); then
        root_mb=$(( usable_mb - HOME_MIN_MB ))
    fi
    if (( root_mb < 24 * 1024 )); then
        die "После ESP и /home для корня остаётся слишком мало места"
    fi
    home_start_mb=$(( root_start_mb + root_mb ))

    if (( LUKS == 1 )); then
        # LUKS: создаём один раздел для root и один для home (оба зашифрованы)
        run_logged parted -s "$disk" mkpart root_crypt ext4 "${root_start_mb}MiB" "${home_start_mb}MiB"
        run_logged parted -s "$disk" mkpart home_crypt ext4 "${home_start_mb}MiB" 100%
    else
        run_logged parted -s "$disk" mkpart root ext4 "${root_start_mb}MiB" "${home_start_mb}MiB"
        run_logged parted -s "$disk" mkpart home ext4 "${home_start_mb}MiB" 100%
    fi

    run_logged partprobe "$disk" || true
    udevadm settle || true
    sleep 1

    if [[ "$BOOT_MODE" == "uefi" ]]; then
        EFI_PART=$(part_path "$disk" 1)
        if (( LUKS == 1 )); then
            ROOT_PART=$(part_path "$disk" 2)
            HOME_PART=$(part_path "$disk" 3)
        else
            ROOT_PART=$(part_path "$disk" 2)
            HOME_PART=$(part_path "$disk" 3)
        fi
        ESP_DISK="$disk"
        ESP_NUM=1
    else
        EFI_PART=""
        if (( LUKS == 1 )); then
            ROOT_PART=$(part_path "$disk" 2)
            HOME_PART=$(part_path "$disk" 3)
        else
            ROOT_PART=$(part_path "$disk" 2)
            HOME_PART=$(part_path "$disk" 3)
        fi
        ESP_DISK=""
        ESP_NUM=""
    fi

    local p
    for p in "$ROOT_PART" "$HOME_PART" ${EFI_PART:+"$EFI_PART"}; do
        [[ -b "$p" ]] || die "Раздел не появился после разметки: $p"
    done

    if (( LUKS == 1 )); then
        # Форматируем LUKS контейнеры
        luks_format_partition "$ROOT_PART" "$LUKS_PASSWORD" "cryptroot"
        luks_format_partition "$HOME_PART" "$LUKS_PASSWORD" "crypthome"
        ROOT_PART="/dev/mapper/cryptroot"
        HOME_PART="/dev/mapper/crypthome"
    fi

    ui_success "Разметка создана: root ${root_mb} МиБ, home — остальное"
    log "Partitions: EFI=$EFI_PART ROOT=$ROOT_PART HOME=$HOME_PART LUKS=$LUKS"
}

format_partitions() {
    if [[ -n "$EFI_PART" && "$PARTITION_MODE" == "0" ]]; then
        ui_step "Форматирование ESP: $EFI_PART"
        run_logged wipefs -a "$EFI_PART"
        run_logged mkfs.fat -F32 -n EFI "$EFI_PART"
    fi

    if (( LUKS == 1 )); then
        ui_step "Форматирование корня (ext4 внутри LUKS): $ROOT_PART"
        run_logged mkfs.ext4 -F -L root -m 1 "$ROOT_PART"

        if [[ -n "$HOME_PART" && "$PARTITION_MODE" == "0" ]]; then
            ui_step "Форматирование /home (ext4 внутри LUKS): $HOME_PART"
            run_logged mkfs.ext4 -F -L home -m 1 "$HOME_PART"
        fi
    else
        ui_step "Форматирование корня: $ROOT_PART (ext4)"
        run_logged wipefs -a "$ROOT_PART"
        run_logged mkfs.ext4 -F -L root -m 1 "$ROOT_PART"

        if [[ -n "$HOME_PART" && "$PARTITION_MODE" == "0" ]]; then
            ui_step "Форматирование /home: $HOME_PART (ext4)"
            run_logged wipefs -a "$HOME_PART"
            run_logged mkfs.ext4 -F -L home -m 1 "$HOME_PART"
        fi
    fi

    ui_success "Файловые системы готовы"
}

mount_target() {
    ui_step "Монтирование целевой системы"
    run_logged mkdir -p "$MOUNTPOINT"
    run_logged mount "$ROOT_PART" "$MOUNTPOINT"
    MOUNTED=1

    if [[ -n "$HOME_PART" ]]; then
        run_logged mkdir -p "$MOUNTPOINT/home"
        run_logged mount "$HOME_PART" "$MOUNTPOINT/home"
    fi

    if [[ -n "$EFI_PART" ]]; then
        # ESP монтируется в /boot: ядро и initramfs остаются на незашифрованном
        # разделе, поэтому GRUB может загрузить их и при LUKS-корне.
        run_logged mkdir -p "$MOUNTPOINT/boot"
        run_logged mount "$EFI_PART" "$MOUNTPOINT/boot"
    fi

    ui_success "Разделы смонтированы в $MOUNTPOINT"
}

create_swapfile() {
    local free_mb size="4G" count=4096
    free_mb=$(df -m "$MOUNTPOINT" | awk 'NR==2 {print $4}')
    if (( free_mb < 6144 )); then
        size="2G"; count=2048
        ui_warn "Мало свободного места, swap-файл будет 2 ГБ"
    fi
    if (( free_mb < 3072 )); then
        ui_warn "Свободного места меньше 3 ГБ — swap-файл пропущен"
        SWAP_SIZE="0"
        return 0
    fi

    ui_step "Создание swap-файла ${size}"
    if ! run_logged fallocate -l "$size" "$MOUNTPOINT/swapfile"; then
        run_logged dd if=/dev/zero of="$MOUNTPOINT/swapfile" bs=1M count="$count" status=none
    fi
    run_logged chmod 600 "$MOUNTPOINT/swapfile"
    run_logged mkswap "$MOUNTPOINT/swapfile"
    SWAP_SIZE="$size"
}

unmount_target() {
    ui_step "Размонтирование"
    if [[ -f "$MOUNTPOINT/swapfile" ]]; then
        swapoff "$MOUNTPOINT/swapfile" 2>/dev/null || true
    fi
    umount -R "$MOUNTPOINT" 2>/dev/null || true
    MOUNTED=0
    ui_success "Разделы размонтированы"
}
