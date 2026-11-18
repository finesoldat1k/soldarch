#!/usr/bin/env bash
# test-qemu.sh — установка Soldarch в QEMU (UEFI по умолчанию).
#   ./scripts/test-qemu.sh          UEFI
#   ./scripts/test-qemu.sh bios     BIOS
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-uefi}"
TEST_DIR="$ROOT/test"
ISO="$ROOT/out/soldarch-test.iso"
DISK="$TEST_DIR/disk.qcow2"
SERIAL_INSTALL="$TEST_DIR/serial-install.log"
SERIAL_BOOT="$TEST_DIR/serial-boot.log"

if [[ ! -f "$ISO" ]]; then
    # На случай, если стабильный symlink не создан.
    ISO=$(ls -1t "$ROOT/out"/soldarch-test-*.iso 2>/dev/null | head -n1 || true)
fi
[[ -n "$ISO" && -f "$ISO" ]] || {
    echo "Нет тестовой ISO. Соберите: ./scripts/build-iso.sh test-auto" >&2
    exit 1
}

mkdir -p "$TEST_DIR"
rm -f "$SERIAL_INSTALL" "$SERIAL_BOOT"
rm -f "$DISK"
qemu-img create -f qcow2 "$DISK" 100G >/dev/null

COMMON=(
    -machine q35 -m 8192 -smp 8
    -drive file="$DISK",if=virtio,format=qcow2
    -device virtio-vga
    -display none
    -nic none
    -no-reboot
)
if [[ -r /dev/kvm ]]; then
    COMMON+=(-enable-kvm -cpu host)
else
    COMMON+=(-cpu max)
fi

if [[ "$MODE" == "uefi" ]]; then
    OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
    OVMF_VARS_SRC=/usr/share/edk2/x64/OVMF_VARS.4m.fd
    VARS="$TEST_DIR/OVMF_VARS.fd"
    [[ -f "$OVMF_CODE" && -f "$OVMF_VARS_SRC" ]] || {
        echo "Не найден OVMF: $OVMF_CODE / $OVMF_VARS_SRC" >&2
        exit 1
    }
    cp -f "$OVMF_VARS_SRC" "$VARS"
    FIRMWARE=(
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
        -drive if=pflash,format=raw,file="$VARS"
    )
else
    FIRMWARE=()
fi

echo "==> ISO: $ISO"
echo "==> Установка ($MODE). Лог: $SERIAL_INSTALL"
# Автоустановка завершается poweroff; -no-reboot завершает QEMU.
# Таймаут страхует от зависания при ошибке установщика.
timeout 3600 qemu-system-x86_64 "${COMMON[@]}" "${FIRMWARE[@]}" \
    -cdrom "$ISO" -boot d -serial "file:$SERIAL_INSTALL" || true

if ! grep -q 'Soldarch установлен' "$SERIAL_INSTALL"; then
    echo "!! Установка не подтверждена. Последние строки:" >&2
    tail -80 "$SERIAL_INSTALL" >&2
    exit 1
fi
echo "==> Установка завершена. Загружаю диск."

# Загрузка установленной системы. Ждём приглашение входа на serial,
# затем завершаем QEMU, не дожидаясь полного таймаута.
qemu-system-x86_64 "${COMMON[@]}" "${FIRMWARE[@]}" \
    -boot c -serial "file:$SERIAL_BOOT" &
BOOT_PID=$!
for _ in $(seq 1 600); do
    grep -q 'arch login:' "$SERIAL_BOOT" 2>/dev/null && break
    kill -0 "$BOOT_PID" 2>/dev/null || break
    sleep 1
done
kill "$BOOT_PID" 2>/dev/null || true
wait "$BOOT_PID" 2>/dev/null || true

echo "==> Лог загрузки: $SERIAL_BOOT"
grep -E 'Reached target|Started|Failed|sddm|Hyprland|login|Arch Linux' \
    "$SERIAL_BOOT" | tail -100 || true

if grep -qE 'emergency mode|Failed to mount|Failed to start.*(systemd|local-fs|NetworkManager)' \
    "$SERIAL_BOOT"; then
    echo "!! В загрузке установленной системы есть критические ошибки" >&2
    exit 1
fi

# С installed GRUB включён serial console: agetty пишет приглашение
# входа, даже если quiet скрывает сообщения systemd.
if ! grep -qE 'arch login:|Reached target.*[Gg]raphical|sddm' "$SERIAL_BOOT"; then
    echo "!! Не найдено признаков успешной загрузки (login prompt/sddm)" >&2
    tail -120 "$SERIAL_BOOT" >&2
    exit 1
fi
echo "==> Тест завершён"
