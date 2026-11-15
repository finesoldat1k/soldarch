# ~/.bash_profile — автозапуск установщика в live-ISO Soldarch
#
# На tty1 при обычной загрузке сразу открывается установщик.
# В автоматическом режиме (soldarch.auto=1) установщик запускается
# на serial-консоли, если она включена, иначе на tty1.

if [ -f /usr/share/kbd/consolefonts/ter-v16n.psf.gz ]; then
    setfont ter-v16n 2>/dev/null || true
fi

INSTALLER=/usr/local/bin/soldarch-install

if [ -x "$INSTALLER" ]; then
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
    else
        if [ "$(tty)" = "/dev/tty1" ]; then
            exec "$INSTALLER"
        fi
    fi
fi
