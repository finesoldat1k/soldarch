#!/usr/bin/env bash
# lib/ui.sh — интерфейс пользователя (чистый TTY, без внешних зависимостей)

# ─── Заголовки и разделители ───
ui_hr() {
    printf '%s\n' "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"
}

ui_title() {
    echo
    printf '%s\n' "${C_ORANGE}${C_BOLD}═══ $* ═══${C_RESET}"
}

ui_section() {
    echo
    printf '%s\n' "${C_ORANGE}${C_BOLD}▸ $*${C_RESET}"
}

# ─── Сообщения ───
ui_info()    { printf '%s\n' "${C_BLUE}[INFO]${C_RESET} $*"; }
ui_success() { printf '%s\n' "${C_GREEN}[ OK ]${C_RESET} $*"; }
ui_warn()    { printf '%s\n' "${C_YELLOW}[WARN]${C_RESET} $*" >&2; }
ui_error()   { printf '%s\n' "${C_RED}[FAIL]${C_RESET} $*" >&2; }
ui_step()    { printf '%s\n' "${C_CYAN}[ >> ]${C_RESET} ${C_BOLD}$*${C_RESET}"; }

# ─── Пауза ───
ui_pause() {
    echo
    read -rp "Нажмите Enter для продолжения..." _ </dev/tty || true
    return 0
}

# ─── Ввод строки с дефолтом ───
ui_prompt() {
    local prompt="$1"
    local default="${2:-}"
    local var
    local suffix=""

    [[ -n "$default" ]] && suffix=" ${C_DIM}[${default}]${C_RESET}"

    printf '%s%s: ' "$prompt" "$suffix" >&2
    IFS= read -r var </dev/tty
    [[ -z "$var" ]] && var="$default"
    echo "$var"
}

# ─── Ввод пароля ───
ui_password() {
    local prompt="$1"
    local pass pass2

    while true; do
        printf '%s: ' "$prompt" >&2
        IFS= read -rs pass </dev/tty
        echo >&2

        if [[ -z "$pass" ]]; then
            ui_error "Пароль не может быть пустым"
            continue
        fi

        if [[ ${#pass} -lt 4 ]]; then
            ui_warn "Пароль слишком короткий (< 4 символов)."
            if ! ui_confirm "Использовать всё равно?" "n"; then
                continue
            fi
        fi

        printf 'Повторите: ' >&2
        IFS= read -rs pass2 </dev/tty
        echo >&2

        if [[ "$pass" != "$pass2" ]]; then
            ui_error "Пароли не совпадают"
            continue
        fi

        echo "$pass"
        return 0
    done
}

# ─── Да/Нет ───
ui_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local hint answer

    if [[ "$default" == "y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi

    printf '%s %s: ' "$prompt" "$hint" >&2     # ← >&2 обязательно
    IFS= read -r answer </dev/tty
    [[ -z "$answer" ]] && answer="$default"

    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" || "${answer,,}" == "д" ]]
}

# ─── Меню с числовым выбором ───
# Отображает список в stderr, возвращает номер в stdout
ui_menu() {
    local title="$1"; shift
    local items=("$@")
    local i n

    {
        echo
        printf '%s\n' "${C_ORANGE}${C_BOLD}▸ ${title}${C_RESET}"
        echo
        for i in "${!items[@]}"; do
            printf '  %2d) %s\n' "$((i+1))" "${items[$i]}"
        done
        echo
    } >&2

    while true; do
        printf 'Выберите [1-%d]: ' "${#items[@]}" >&2
        IFS= read -r n </dev/tty
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#items[@]} )); then
            echo "$n"
            return 0
        fi
        ui_error "Введите число от 1 до ${#items[@]}"
    done
}

# ─── Выбор из списка с описанием ───
# Возвращает значение (до |) в stdout
ui_choose() {
    local title="$1"; shift
    local items=("$@")
    local i n

    {
        echo
        printf '%s\n' "${C_ORANGE}${C_BOLD}▸ ${title}${C_RESET}"
        echo
        for i in "${!items[@]}"; do
            local value="${items[$i]%%|*}"
            local desc="${items[$i]#*|}"
            [[ "$desc" == "$items[$i]" ]] && desc=""
            printf '  %2d) %-10s %s\n' "$((i+1))" "$value" "$desc"
        done
        echo
    } >&2

    while true; do
        printf 'Выберите [1-%d]: ' "${#items[@]}" >&2
        IFS= read -r n </dev/tty
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#items[@]} )); then
            local chosen="${items[$((n-1))]}"
            echo "${chosen%%|*}"
            return 0
        fi
        ui_error "Введите число от 1 до ${#items[@]}"
    done
}

# ─── Прогресс-бар для долгих операций ───
# Использование: ui_progress "Скачивание" 42 100
ui_progress() {
    local label="$1"
    local current="$2"
    local total="$3"
    local width=40

    [[ "$total" -eq 0 ]] && return

    local percent=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    printf '\r%s[%s%s] %3d%%%s' \
        "$label " \
        "$(printf '#%.0s' $(seq 1 $filled 2>/dev/null))" \
        "$(printf '.%.0s' $(seq 1 $empty 2>/dev/null))" \
        "$percent" \
        " "
}