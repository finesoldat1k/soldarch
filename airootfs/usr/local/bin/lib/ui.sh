#!/usr/bin/env bash
# lib/ui.sh — простой TUI для live-консоли и serial

ui_hr() {
    printf '%s\n' "${C_DIM}────────────────────────────────────────────────────────────${C_RESET}"
}

ui_title() {
    printf '\n%s\n' "${C_ORANGE}${C_BOLD}  $*  ${C_RESET}"
    ui_hr
}

ui_step() {
    printf '\n%s %s\n' "${C_CYAN}${C_BOLD}▸${C_RESET}" "${C_BOLD}$*${C_RESET}"
}

ui_info()    { printf '%s %s\n' "${C_BLUE}[i]${C_RESET}" "$*"; }
ui_success() { printf '%s %s\n' "${C_GREEN}[ok]${C_RESET}" "$*"; }
ui_warn()    { printf '%s %s\n' "${C_YELLOW}[!]${C_RESET}" "$*" >&2; }
ui_error()   { printf '%s %s\n' "${C_RED}[x]${C_RESET}" "$*" >&2; }

ui_pause() {
    if (( AUTO == 1 )) || [[ ! -t 0 ]]; then
        return 0
    fi
    printf '\n%s' "Нажмите Enter для продолжения..." >&2
    read -r _ </dev/tty || true
    return 0
}

ui_confirm() {
    local prompt="$1" default="${2:-n}" hint answer
    if (( ASSUME_YES == 1 )) || [[ ! -t 0 ]]; then
        return 0
    fi
    if [[ "$default" == "y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
    printf '%s %s: ' "$prompt" "$hint" >&2
    read -r answer </dev/tty || answer=""
    [[ -z "$answer" ]] && answer="$default"
    case "${answer,,}" in
        y|yes|д|да) return 0 ;;
        *) return 1 ;;
    esac
}

ui_prompt() {
    local prompt="$1" default="${2:-}" answer suffix=""
    [[ -n "$default" ]] && suffix=" ${C_DIM}[$default]${C_RESET}"
    printf '%s%s: ' "$prompt" "$suffix" >&2
    read -r answer </dev/tty || answer=""
    [[ -z "$answer" ]] && answer="$default"
    printf '%s\n' "$answer"
}

ui_password() {
    local prompt="$1" pass pass2
    while true; do
        printf '%s: ' "$prompt" >&2
        read -rs pass </dev/tty || pass=""
        printf '\n' >&2
        if [[ -z "$pass" ]]; then
            ui_error "Пароль не может быть пустым"
            continue
        fi
        if (( ${#pass} < 4 )); then
            ui_warn "Пароль короче 4 символов."
            if ! ui_confirm "Использовать всё равно?" "n"; then
                continue
            fi
        fi
        printf 'Повторите пароль: ' >&2
        read -rs pass2 </dev/tty || pass2=""
        printf '\n' >&2
        if [[ "$pass" != "$pass2" ]]; then
            ui_error "Пароли не совпадают"
            continue
        fi
        printf '%s\n' "$pass"
        return 0
    done
}

# Меню. Возвращает номер (1..N), 0 — отмена.
ui_menu() {
    local title="$1"; shift
    local -a items=("$@")
    local i n

    {
        printf '\n%s\n\n' "${C_ORANGE}${C_BOLD}$title${C_RESET}"
        for i in "${!items[@]}"; do
            printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}"
        done
        printf '   0) Отмена\n\n'
    } >&2

    while true; do
        printf 'Выбор [0-%d]: ' "${#items[@]}" >&2
        read -r n </dev/tty || return 0
        if [[ "$n" == "0" ]]; then
            return 0
        fi
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#items[@]} )); then
            printf '%s\n' "$n"
            return 0
        fi
        ui_error "Введите число от 0 до ${#items[@]}"
    done
}

# Прокручиваемый просмотр лога.
ui_show_log() {
    local lines="${1:-60}"
    ui_hr
    log_tail "$lines"
    ui_hr
}
