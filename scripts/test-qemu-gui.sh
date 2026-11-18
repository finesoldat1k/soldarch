#!/usr/bin/env bash
# test-qemu-gui.sh — QEMU с графическим установщиком для ручной проверки.
#
# Загружает release ISO в UEFI-виртуалку с GTK-окном. Первая загрузка — с ISO
# (за счёт -boot once=d), после установки и перезагрузки QEMU грузится с диска.
#
# Переменные окружения:
#   SOLDARCH_DISK_SIZE=48G   размер виртуального диска
#   SOLDARCH_RAM=8192        оперативная память, МиБ
#   SOLDARCH_CPUS=8          количество vCPU
#   SOLDARCH_AUDIO=pipewire  аудиодрайвер QEMU (none — отключить звук)
#   SOLDARCH_KEEP_DISK=1     не пересоздавать диск и NVRAM перед запуском
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="$ROOT/out/soldarch.iso"
TEST_DIR="$ROOT/test-gui"
DISK="$TEST_DIR/disk.qcow2"
VARS="$TEST_DIR/OVMF_VARS.4m.fd"
SERIAL_LOG="$TEST_DIR/serial.log"

OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd

die() { echo "Ошибка: $*" >&2; exit 1; }

[[ -f "$ISO" ]] || die "нет $ISO. Соберите: ./scripts/build-iso.sh release"
[[ -r "$OVMF_CODE" && -r "$OVMF_VARS" ]] || die "не найден OVMF (edk2-ovmf)"
command -v qemu-system-x86_64 >/dev/null 2>&1 || die "не установлен qemu"

mkdir -p "$TEST_DIR"

if [[ "${SOLDARCH_KEEP_DISK:-0}" != "1" ]]; then
    rm -f "$DISK" "$VARS"
fi

if [[ ! -f "$DISK" ]]; then
    qemu-img create -f qcow2 "$DISK" "${SOLDARCH_DISK_SIZE:-48G}" >/dev/null
fi
if [[ ! -f "$VARS" ]]; then
    cp "$OVMF_VARS" "$VARS"
fi
: >"$SERIAL_LOG"

ARGS=(
    -name "Soldarch GUI installer"
    -machine q35
    -m "${SOLDARCH_RAM:-8192}"
    -smp "${SOLDARCH_CPUS:-8}"
    -drive file="$DISK",if=virtio,format=qcow2
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
    -drive if=pflash,format=raw,file="$VARS"
    -device virtio-vga
    -device qemu-xhci
    -device usb-tablet
    -display gtk
    -nic user,model=virtio-net-pci
    -boot once=d
    -serial "file:$SERIAL_LOG"
    -no-reboot
)

if [[ -r /dev/kvm ]]; then
    ARGS+=(-enable-kvm -cpu host)
else
    ARGS+=(-cpu max)
    echo "KVM недоступен — виртуалка будет медленной." >&2
fi

AUDIO="${SOLDARCH_AUDIO:-pipewire}"
if [[ "$AUDIO" != "none" ]]; then
    ARGS+=(
        -audiodev "$AUDIO,id=snd0"
        -device intel-hda
        -device hda-duplex,audiodev=snd0
    )
fi

echo "ISO:   $ISO"
echo "Диск:  $DISK ($(qemu-img info --output=json "$DISK" | grep -o '"virtual-size": [0-9]*' | awk '{printf "%.0fG", $2/1024/1024/1024}'))"
echo "Лог:   $SERIAL_LOG"
echo
echo "В окне QEMU должен открыться графический установщик Soldarch."
echo "После установки нажмите «Перезагрузить» — система загрузится с диска."
echo

exec qemu-system-x86_64 "${ARGS[@]}"
