#!/usr/bin/env bash
# lib/common.sh — общие настройки, логирование и проверки установщика Soldarch

readonly INSTALLER_VERSION="1.0.0"
readonly LOGFILE="/tmp/soldarch-install.log"
readonly MOUNTPOINT="/mnt"
readonly SOLDARCH_DIR="/opt/soldarch"
readonly OFFLINE_REPO="$SOLDARCH_DIR/repo"
readonly PACKAGES_FILE="$SOLDARCH_DIR/packages-target.txt"
readonly TARGET_CONFIG_DIR="$SOLDARCH_DIR/configs"
readonly OFFLINE_PACMAN_CONF="/etc/soldarch/pacman-offline.conf"

# Цвета. В serial-консоли они тоже работают, поэтому не отключаем.
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_CYAN=$'\033[36m'
C_ORANGE=$'\033[38;2;230;126;34m'

# Настройки установки
AUTO=0
ASSUME_YES=0
ACTION=""
TARGET_MODE=""          # disk | partition
TARGET_DISK=""
ROOT_PART=""
EFI_PART=""
HOME_PART=""
PASSWORD=""
AUTOLOGIN=0
SERIAL_CONSOLE=0

BOOT_MODE=""            # uefi | bios
ESP_DISK=""
ESP_NUM=""
PARTITION_MODE=0
MOUNTED=0
INSTALL_SUCCESS=0

HOSTNAME="arch"
USERNAME="iam"
TIMEZONE="Europe/Moscow"
LOCALE="en_US.UTF-8"
KEYMAP="us"
SWAP_SIZE="4G"
ROOT_MIN_MB=$((24 * 1024))
HOME_MIN_MB=$((6 * 1024))

declare -a TARGET_PACKAGES=()

# ─────────────────────────────────────────────────────────────
# Логирование
# ─────────────────────────────────────────────────────────────
init_log() {
    : >"$LOGFILE"
    log "=== Soldarch installer v${INSTALLER_VERSION} ==="
    log "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    log "Kernel: $(uname -r)"
    log "Cmdline: $(cat /proc/cmdline)"
}

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOGFILE"
}

log_tail() {
    local lines="${1:-40}"
    if [[ -s "$LOGFILE" ]]; then
        tail -n "$lines" "$LOGFILE" | while IFS= read -r line; do
            printf '%s\n' "${C_DIM}${line}${C_RESET}" >&2
        done
    fi
}

die() {
    log "FATAL: $*"
    ui_error "$*"
    log_tail 25
    exit 1
}

run_logged() {
    log "RUN: $*"
    local rc=0
    "$@" >>"$LOGFILE" 2>&1 || rc=$?
    if (( rc == 0 )); then
        log "OK: $*"
    else
        log "FAIL($rc): $*"
    fi
    return "$rc"
}

# Запускает долгую команду с индикатором и пишет вывод в лог.
run_with_spinner() {
    local label="$1"; shift
    log "RUN: $*"

    if [[ ! -t 2 ]]; then
        ui_info "$label"
        local rc=0
        "$@" >>"$LOGFILE" 2>&1 || rc=$?
        log "rc=$rc: $*"
        return "$rc"
    fi

    "$@" >>"$LOGFILE" 2>&1 &
    local pid=$!
    local start=$SECONDS
    local frames=('|' '/' '-' '\')
    local i=0
    local rc=0

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%s %s  %ss ' "$label" "${frames[$((i % 4))]}" "$((SECONDS - start))" >&2
        i=$((i + 1))
        sleep 0.2
    done
    wait "$pid" || rc=$?
    printf '\r\033[K' >&2

    if (( rc == 0 )); then
        log "OK: $*"
    else
        log "FAIL($rc): $*"
    fi
    return "$rc"
}

run_chroot() {
    log "CHROOT: $*"
    local rc=0
    arch-chroot "$MOUNTPOINT" "$@" >>"$LOGFILE" 2>&1 || rc=$?
    log "chroot rc=$rc: $*"
    return "$rc"
}

run_chroot_sh() {
    run_chroot /bin/bash -c "$*"
}

# ─────────────────────────────────────────────────────────────
# Ошибки и очистка
# ─────────────────────────────────────────────────────────────
on_error() {
    local rc="$1" line="$2" cmd="$3"
    trap - ERR
    log "ERROR rc=$rc line=$line cmd=$cmd"
    printf '\n' >&2
    ui_error "Установка прервана (код $rc, строка $line)"
    [[ -n "$cmd" ]] && ui_error "Команда: $cmd"
    ui_error "Лог: $LOGFILE"
    log_tail 20
    cleanup_mounts
    exit "$rc"
}

setup_traps() {
    trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
    trap 'cleanup_mounts' EXIT
}

cleanup_mounts() {
    if (( MOUNTED == 1 )); then
        log "Cleanup: unmounting $MOUNTPOINT"
        if [[ -f "$MOUNTPOINT/swapfile" ]]; then
            swapoff "$MOUNTPOINT/swapfile" 2>/dev/null || true
        fi
        umount -R "$MOUNTPOINT" 2>/dev/null || true
        MOUNTED=0
    fi
}

# ─────────────────────────────────────────────────────────────
# Проверки и определение окружения
# ─────────────────────────────────────────────────────────────
require_root() {
    if (( EUID != 0 )); then
        echo "Запустите установщик от root." >&2
        exit 1
    fi
}

acquire_lock() {
    exec 9>/run/soldarch-installer.lock
    if ! flock -n 9; then
        echo "Установщик уже запущен в другом терминале." >&2
        exit 0
    fi
}

detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="uefi"
    else
        BOOT_MODE="bios"
    fi
    log "Boot mode: $BOOT_MODE"
}

check_requirements() {
    local -a tools=(
        parted sgdisk wipefs mkfs.fat mkfs.ext4
        pacstrap genfstab arch-chroot
        openssl lsblk findmnt blockdev udevadm
        mount umount swapoff mkswap fallocate
        grub-install efibootmgr
    )
    local -a missing=()
    local t
    for t in "${tools[@]}"; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done

    if (( ${#missing[@]} > 0 )); then
        die "В live-окружении не хватает утилит: ${missing[*]}"
    fi

    [[ -f "$PACKAGES_FILE" ]] || die "Не найден список пакетов: $PACKAGES_FILE"
    [[ -f "$OFFLINE_PACMAN_CONF" ]] || die "Не найден конфиг pacman: $OFFLINE_PACMAN_CONF"
    [[ -f "$OFFLINE_REPO/soldarch.db.tar.gz" ]] || \
        die "Не найден офлайн-репозиторий: $OFFLINE_REPO/soldarch.db.tar.gz"

    log "Все требования выполнены"
}

load_packages() {
    TARGET_PACKAGES=()
    local line
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | xargs)"
        [[ -n "$line" ]] && TARGET_PACKAGES+=("$line")
    done <"$PACKAGES_FILE"

    if (( ${#TARGET_PACKAGES[@]} == 0 )); then
        die "Список целевых пакетов пуст: $PACKAGES_FILE"
    fi
    log "Target packages (${#TARGET_PACKAGES[@]}): ${TARGET_PACKAGES[*]}"
}

# ─────────────────────────────────────────────────────────────
# Аргументы и kernel cmdline
# ─────────────────────────────────────────────────────────────
parse_cmdline() {
    local tok key value
    for tok in $(cat /proc/cmdline); do
        case "$tok" in
            soldarch.auto=*)      AUTO=1; ASSUME_YES=1 ;;
            soldarch.disk=*)      TARGET_MODE="disk"; TARGET_DISK="${tok#*=}" ;;
            soldarch.partition=*) TARGET_MODE="partition"; ROOT_PART="${tok#*=}" ;;
            soldarch.efi=*)       EFI_PART="${tok#*=}" ;;
            soldarch.password=*)  PASSWORD="${tok#*=}" ;;
            soldarch.reboot=1)    ACTION="reboot" ;;
            soldarch.reboot=0)    ACTION="poweroff" ;;
            soldarch.autologin=1) AUTOLOGIN=1 ;;
            soldarch.serial=1)    SERIAL_CONSOLE=1 ;;
            soldarch.username=*)  USERNAME="${tok#*=}" ;;
        esac
    done
    if (( AUTO == 1 )); then
        log "Auto mode from kernel cmdline"
    fi
}

usage() {
    cat <<'EOF'
Soldarch installer

Использование:
  soldarch-install                         интерактивная установка
  soldarch-install --disk /dev/nvme0n1     установка на весь диск
  soldarch-install --partition /dev/sda5   установка в существующий раздел
  soldarch-install --auto --disk /dev/vda --password secret --yes

Параметры:
  --disk <устройство>       установить на весь диск (диск будет стёрт)
  --partition <устройство>  установить в существующий раздел
  --efi <устройство>        ESP для режима раздела (иначе ищется автоматически)
  --password <пароль>       пароль пользователя iam
  --auto                    без вопросов (требует --disk/--partition и --password)
  --yes                     не спрашивать подтверждение
  --reboot                  перезагрузиться после установки
  --poweroff                выключить после установки
  --no-reboot               не перезагружаться
  --autologin               включить автологин в SDDM (для тестов)
  --serial-console          добавить console=ttyS0 в GRUB (для тестов)
  -h, --help                эта справка
EOF
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --disk)
                [[ $# -ge 2 ]] || die "--disk требует путь"
                TARGET_MODE="disk"; TARGET_DISK="$2"; shift 2 ;;
            --partition)
                [[ $# -ge 2 ]] || die "--partition требует путь"
                TARGET_MODE="partition"; ROOT_PART="$2"; shift 2 ;;
            --efi)
                [[ $# -ge 2 ]] || die "--efi требует путь"
                EFI_PART="$2"; shift 2 ;;
            --password)
                [[ $# -ge 2 ]] || die "--password требует значение"
                PASSWORD="$2"; shift 2 ;;
            --auto) AUTO=1; ASSUME_YES=1; shift ;;
            --yes) ASSUME_YES=1; shift ;;
            --reboot) ACTION="reboot"; shift ;;
            --poweroff) ACTION="poweroff"; shift ;;
            --no-reboot) ACTION="none"; shift ;;
            --autologin) AUTOLOGIN=1; shift ;;
            --serial-console) SERIAL_CONSOLE=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Неизвестный параметр: $1" ;;
        esac
    done

    if (( AUTO == 1 )); then
        [[ -n "$TARGET_MODE" ]] || die "Авторежиму нужен --disk или --partition"
        [[ -n "$PASSWORD" ]] || die "Авторежиму нужен --password"
        [[ -n "$ACTION" ]] || ACTION="poweroff"
        ASSUME_YES=1
    fi
}

# ─────────────────────────────────────────────────────────────
# Утилиты
# ─────────────────────────────────────────────────────────────
human_size() {
    numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%sB' "$1"
}

part_path() {
    local disk="$1" num="$2"
    case "$disk" in
        *nvme*|*mmcblk*|*loop*) printf '%sp%s\n' "$disk" "$num" ;;
        *) printf '%s%s\n' "$disk" "$num" ;;
    esac
}

part_num() {
    lsblk -no PARTN "$1" 2>/dev/null | head -n1 | tr -d ' '
}

disk_of_part() {
    lsblk -no PKNAME "$1" 2>/dev/null | head -n1 | tr -d ' '
}

live_disk() {
    local src
    src=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
    [[ -n "$src" ]] || return 0
    local parent
    parent=$(disk_of_part "$src")
    if [[ -n "$parent" ]]; then
        printf '/dev/%s\n' "$parent"
    else
        printf '%s\n' "$src"
    fi
}
