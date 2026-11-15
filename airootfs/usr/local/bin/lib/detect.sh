#!/usr/bin/env bash
# lib/detect.sh — определение железа и проверка требований

# ─── Список дисков (только физические) ───
list_disks_detailed() {
    lsblk -dno NAME,SIZE,TYPE,MODEL | \
        awk '$3=="disk" && $1 !~ /^(loop|sr|zram|ram|dm-)/ {
            model=""
            for (i=4; i<=NF; i++) model = model $i " "
            gsub(/ +$/, "", model)
            if (model == "") model = "(без модели)"
            printf "%s|%s  %s\n", $1, $2, model
        }'
}

# ─── Имя раздела (учёт NVMe, MMC, loop) ───
part_name() {
    local disk="$1" num="$2"
    if [[ "$disk" =~ nvme|mmcblk|loop ]]; then
        echo "${disk}p${num}"
    else
        echo "${disk}${num}"
    fi
}

# ─── Проверка требований Live-окружения ───
check_requirements() {
    local missing=()
    local tools=(
        parted wipefs mkfs.fat mkfs.ext4 mkfs.btrfs mkfs.xfs
        pacstrap genfstab arch-chroot
        openssl
    )

    for t in "${tools[@]}"; do
        command -v "$t" &>/dev/null || missing+=("$t")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        ui_error "Не найдены утилиты: ${missing[*]}"
        ui_error "Похоже, это не Live-ISO Soldatik Linux"
        return 1
    fi

    log "Все требуемые утилиты найдены"
    return 0
}