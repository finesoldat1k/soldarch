#!/usr/bin/env bash
# lib/extras.sh — дополнительные пакеты и разные меню

# ─── Наборы пакетов ───
readonly EXTRA_DEV="git base-devel neovim python nodejs npm go rust"
readonly EXTRA_MULTIMEDIA="mpv ffmpeg gimp imagemagick obs-studio"
readonly EXTRA_NETWORK="curl wget rsync openssh nmap tcpdump"

# ═══════════════════════════════════════════════════════════
# Меню доп. пакетов
# ═══════════════════════════════════════════════════════════

menu_select_extras() {
    while true; do
        clear
        ui_title "Дополнительные пакеты"

        local dev_mark="[ ]"; [[ "${CONFIG[extras]:-}" == *"$EXTRA_DEV"* ]] && dev_mark="[✓]"
        local mm_mark="[ ]";  [[ "${CONFIG[extras]:-}" == *"$EXTRA_MULTIMEDIA"* ]] && mm_mark="[✓]"
        local net_mark="[ ]"; [[ "${CONFIG[extras]:-}" == *"$EXTRA_NETWORK"* ]] && net_mark="[✓]"

        ui_hr
        printf '  1) %s Dev            — git, base-devel, neovim, python, nodejs, go, rust\n' "$dev_mark"
        printf '  2) %s Multimedia     — mpv, ffmpeg, gimp, imagemagick, obs-studio\n' "$mm_mark"
        printf '  3) %s Network        — curl, wget, rsync, openssh, nmap, tcpdump\n' "$net_mark"
        ui_hr
        printf '  4) Ввести список пакетов вручную\n'
        printf '  5) Очистить все доп. пакеты\n'
        printf '  0) Готово\n'
        ui_hr
        echo

        local choice
        read -rp "Выберите: " choice </dev/tty

        case "$choice" in
            1) toggle_extra "$EXTRA_DEV" ;;
            2) toggle_extra "$EXTRA_MULTIMEDIA" ;;
            3) toggle_extra "$EXTRA_NETWORK" ;;
            4)
                local free
                free=$(ui_prompt "Пакеты через пробел" "${CONFIG[extras_free]:-}")
                CONFIG[extras_free]="$free"
                ;;
            5)
                CONFIG[extras]=""
                CONFIG[extras_free]=""
                ;;
            0) return 0 ;;
            *) ui_error "Неверный выбор" ;;
        esac
    done
}

# ─── Включить/выключить набор ───
toggle_extra() {
    local set="$1"

    if [[ "${CONFIG[extras]:-}" == *"$set"* ]]; then
        # Убираем
        CONFIG[extras]="${CONFIG[extras]/$set/}"
        # Схлопываем пробелы
        CONFIG[extras]=$(echo "${CONFIG[extras]}" | tr -s ' ' | sed 's/^ //;s/ $//')
        log "Removed set: $set"
    else
        # Добавляем
        CONFIG[extras]="${CONFIG[extras]:-} $set"
        CONFIG[extras]=$(echo "${CONFIG[extras]}" | tr -s ' ' | sed 's/^ //;s/ $//')
        log "Added set: $set"
    fi
}

# ═══════════════════════════════════════════════════════════
# Меню сети
# ═══════════════════════════════════════════════════════════

menu_select_network() {
    local n
    n=$(ui_menu "Сетевой стек:" \
        "NetworkManager + iwd  (рекомендуется)" \
        "systemd-networkd + iwd  (минимализм)")

    case "$n" in
        1) CONFIG[network]="networkmanager" ;;
        2) CONFIG[network]="systemd-networkd" ;;
    esac
}

# ═══════════════════════════════════════════════════════════
# Меню пользователя
# ═══════════════════════════════════════════════════════════

menu_select_username() {
    local v
    v=$(ui_prompt "Имя пользователя" "${CONFIG[username]}")

    # Валидация
    if ! [[ "$v" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        ui_error "Некорректное имя. Разрешены: a-z, 0-9, _, - (строчные)"
        return 1
    fi

    if (( ${#v} > 32 )); then
        ui_error "Имя длиннее 32 символов"
        return 1
    fi

    CONFIG[username]="$v"
}

# ═══════════════════════════════════════════════════════════
# Меню локали
# ═══════════════════════════════════════════════════════════

menu_select_locale() {
    CONFIG[locale]=$(ui_choose "Системная локализация:" \
        "en_US.UTF-8|Английский (рекомендуется)" \
        "ru_RU.UTF-8|Русский" \
        "C.UTF-8|Без локализации")
}

# ═══════════════════════════════════════════════════════════
# Меню часового пояса (упрощённое)
# ═══════════════════════════════════════════════════════════

menu_select_timezone() {
    CONFIG[timezone]=$(ui_choose "Часовой пояс:" \
        "Europe/Moscow|Москва (UTC+3)" \
        "Europe/Kaliningrad|Калининград (UTC+2)" \
        "Europe/Samara|Самара (UTC+4)" \
        "Asia/Yekaterinburg|Екатеринбург (UTC+5)" \
        "Asia/Omsk|Омск (UTC+6)" \
        "Asia/Krasnoyarsk|Красноярск (UTC+7)" \
        "Asia/Irkutsk|Иркутск (UTC+8)" \
        "Asia/Yakutsk|Якутск (UTC+9)" \
        "Asia/Vladivostok|Владивосток (UTC+10)" \
        "Europe/Kiev|Киев (UTC+2)" \
        "Europe/Minsk|Минск (UTC+3)" \
        "Asia/Almaty|Алматы (UTC+5)" \
        "UTC|UTC")
}