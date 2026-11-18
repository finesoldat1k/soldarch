#!/usr/bin/env bash
# ~/.bash_profile — автозапуск установщика в live-ISO Soldarch.
#
# Обычная загрузка: на tty1 запускается графический установщик внутри
# kiosk-композитора cage. Если GUI недоступен — TUI-установщик.
# Авторежим (soldarch.auto=1) всегда использует TUI на serial/tty1.

if [ -f /usr/share/kbd/consolefonts/ter-v16n.psf.gz ]; then
    setfont ter-v16n 2>/dev/null || true
fi

INSTALLER=/usr/local/bin/soldarch-install
GUI=/usr/local/bin/soldarch-gui-installer
GUI_MARKER=/run/soldarch-gui-started
GUI_LOG=/tmp/soldarch-gui.log

if [ ! -x "$INSTALLER" ]; then
    return 0 2>/dev/null || exit 0
fi

if grep -q 'soldarch.auto=1' /proc/cmdline; then
    if grep -q 'console=ttyS0' /proc/cmdline; then
        if [ "$(tty)" = "/dev/ttyS0" ]; then
            exec "$INSTALLER" --auto
        fi
    else
        if [ "$(tty)" = "/dev/tty1" ]; then
            exec "$INSTALLER" --auto
        fi
    fi
    return 0 2>/dev/null || exit 0
fi

if [ "$(tty)" = "/dev/tty1" ]; then
    rm -f "$GUI_MARKER"

    if [ -x "$GUI" ] && command -v cage >/dev/null 2>&1 \
        && ! grep -q 'soldarch.gui=0' /proc/cmdline; then
        export XDG_RUNTIME_DIR=/run/user/0
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
        # cage — kiosk-композитор: GUI занимает весь экран. Вывод пишем в лог,
        # чтобы после аварийного выхода можно было увидеть причину.
        cage -- "$GUI" >"$GUI_LOG" 2>&1
    fi

    if [ -f "$GUI_MARKER" ]; then
        # GUI стартовал и завершился (успех, ошибка или закрытие окна).
        # Повторно TUI не запускаем: установка могла уже изменить диск.
        clear
        printf '\n  Графический установщик завершён.\n'
        printf '  Лог: %s\n' "$GUI_LOG"
        if [ -s "$GUI_LOG" ]; then
            printf '\n  Последние строки лога:\n\n'
            tail -n 20 "$GUI_LOG"
        fi
        printf '\n  Для повторного запуска: soldarch-gui-installer (GUI) или soldarch-install (TUI).\n\n'
        exec /bin/bash --norc -i
    fi

    exec "$INSTALLER"
fi
