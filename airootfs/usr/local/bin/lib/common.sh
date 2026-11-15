#!/usr/bin/env bash
# lib/common.sh — конфигурация, логирование, утилиты

# ─── Константы ───
readonly LOGFILE="/tmp/soldatik-install.log"
readonly MOUNTPOINT="/mnt"
readonly INSTALLER_VERSION="0.1.0"

# ─── Цвета (ANSI, отключаются, если не TTY) ───
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_ORANGE=$'\033[38;2;230;126;34m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""
    C_RED=""; C_GREEN=""; C_YELLOW=""
    C_BLUE=""; C_CYAN=""; C_ORANGE=""
fi

# ─── CONFIG: ассоциативный массив со всеми настройками ───
declare -A CONFIG

init_config() {
    CONFIG[disk]=""
    CONFIG[disk_size]=""
    CONFIG[partitioning]="auto"           # auto | manual
    CONFIG[fs]="ext4"                     # ext4 | btrfs | xfs
    CONFIG[swap]="file"                   # file | none
    CONFIG[swap_size]="2G"
    CONFIG[hostname]="soldatik"
    CONFIG[locale]="en_US.UTF-8"
    CONFIG[timezone]="Europe/Moscow"
    CONFIG[username]="user"
    CONFIG[userpass]=""
    CONFIG[rootpass]=""
    CONFIG[network]="networkmanager"      # networkmanager | systemd-networkd
    CONFIG[extras]=""                     # список пакетов через пробел
    CONFIG[boot_mode]=""                  # uefi | bios (определяется автоматически)
    CONFIG[efi_part]=""
    CONFIG[root_part]=""
    CONFIG[home_part]=""
    CONFIG[disk_formatted]="n"            # флаг для trap (если что-то пошло не так)
    CONFIG[extras_free]=""
}

# ─── Логирование ───
init_log() {
    : > "$LOGFILE"
    log "=== Soldatik Linux Installer v${INSTALLER_VERSION} ==="
    log "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    log "Kernel: $(uname -r)"
    log "Args: $*"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

# ─── Выполнение команд: вывод на экран + запись в лог ───
# Использование: run_cmd mkfs.ext4 -F /dev/sda3

run_cmd() {
    log "RUN: $*"
    local rc=0
    "$@" || rc=$?
    if [[ $rc -eq 0 ]]; then log "OK: $*"; else log "FAIL($rc): $*"; fi
    return $rc
}

run_chroot() {
    log "CHROOT: $*"
    local rc=0
    arch-chroot "$MOUNTPOINT" "$@" || rc=$?
    if [[ $rc -eq 0 ]]; then log "OK chroot: $*"; else log "FAIL($rc) chroot: $*"; fi
    return $rc
}

run_chroot_sh() {
    log "CHROOT-SH: $*"
    local rc=0
    arch-chroot "$MOUNTPOINT" /bin/bash -c "$*" || rc=$?
    if [[ $rc -eq 0 ]]; then log "OK chroot-sh"; else log "FAIL($rc) chroot-sh"; fi
    return $rc
}

# ─── Обработка ошибок ───
on_error() {
    local code=$1 line=$2 cmd=$3

    echo "" >&2
    ui_error "Установка прервана (код $code)"
    ui_error "Строка $line в скрипте"
    [[ -n "$cmd" ]] && ui_error "Команда: $cmd"
    ui_error "Полный лог: $LOGFILE"

    if [[ "${CONFIG[disk_formatted]:-n}" == "y" ]]; then
        echo "" >&2
        ui_warn "Диск ${CONFIG[disk]} уже размечен. Откат невозможен."
        ui_warn "Загрузитесь с ISO заново и запустите установщик снова."
    fi

    exit "$code"
}

setup_trap() {
    trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
    log "Trap установлен"
}

# ─── Проверки ───
require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Запустите от root: sudo soldatik-install" >&2
        exit 1
    fi
}

# Определяем UEFI или BIOS
detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        CONFIG[boot_mode]="uefi"
    else
        CONFIG[boot_mode]="bios"
    fi
    log "Boot mode: ${CONFIG[boot_mode]}"
}

# Проверка интернета с подтверждением
require_internet() {
    if ! ping -c1 -W3 archlinux.org &>/dev/null; then
        ui_warn "Нет доступа к archlinux.org"
        if ! ui_confirm "Продолжить всё равно?" "n"; then
            exit 1
        fi
    fi
}

# ─── Утилиты ───
human_size() {
    numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"
}

disk_size_gb() {
    local bytes
    bytes=$(blockdev --getsize64 "$1")
    echo $(( bytes / 1024 / 1024 / 1024 ))
}

# Проверить, содержит ли массив элемент
in_array() {
    local needle="$1"; shift
    local x
    for x in "$@"; do
        [[ "$x" == "$needle" ]] && return 0
    done
    return 1
}