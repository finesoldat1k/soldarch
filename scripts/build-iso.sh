#!/usr/bin/env bash
# build-iso.sh — собирает Soldarch ISO.
#   ./scripts/build-iso.sh            обычная ISO
#   ./scripts/build-iso.sh test-auto  тестовая ISO с автоустановкой на /dev/vda
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$ROOT/airootfs/opt/soldarch/repo"
MODE="${1:-release}"
ISO_NAME="soldarch"
BUILD_DIR="$ROOT/build"
PKG_CACHE="$BUILD_DIR/pkgcache"
PACMAN_LIVE="$BUILD_DIR/pacman-live.conf"

if (( EUID == 0 )); then
    echo "Запускайте сборку от обычного пользователя: mkarchiso умеет rootless." >&2
    exit 1
fi

[[ -f "$REPO/soldarch.db.tar.gz" ]] || {
    echo "Нет офлайн-репозитория. Сначала: ./scripts/build-repo.sh" >&2
    exit 1
}

mkdir -p "$ROOT/out" "$BUILD_DIR" "$PKG_CACHE"

# mkarchiso переиспользует рабочий каталог по маркерам *_run_once и может
# собрать ISO со старой базой. Для предсказуемой сборки всегда начинаем
# с чистого каталога.
WORK_DIR="$ROOT/work-$MODE"
if [[ -d "$WORK_DIR" ]]; then
    chmod -R u+w "$WORK_DIR" 2>/dev/null || true
    rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"

# Отдельный pacman.conf только для сборки live-системы: все пакеты
# берутся из локального репозитория, без обращения к зеркалам.
cat >"$PACMAN_LIVE" <<EOF
[options]
HoldPkg = pacman glibc
Architecture = auto
SigLevel = Optional TrustAll
LocalFileSigLevel = Optional
CacheDir = $PKG_CACHE
ParallelDownloads = 10

[soldarch]
SigLevel = Optional TrustAll
Server = file://$REPO
EOF

export SOLDARCH_ISO_NAME="$ISO_NAME"
export SOLDARCH_ISO_LABEL="SOLDARCH_$(date +%Y%m)"

if [[ "$MODE" == "test-auto" ]]; then
    export SOLDARCH_ISO_NAME="soldarch-test"
    export SOLDARCH_ISO_LABEL="SOLDARCH_TEST"
    export SOLDARCH_KERNEL_PARAMS="console=tty0 console=ttyS0,115200 soldarch.auto=1 soldarch.disk=${SOLDARCH_TEST_DISK:-/dev/vda} soldarch.password=${SOLDARCH_TEST_PASSWORD:-test} soldarch.reboot=0 soldarch.autologin=1 soldarch.serial=1"
    export SOLDARCH_SQUASHFS_LEVEL="${SOLDARCH_SQUASHFS_LEVEL:-3}"
else
    export SOLDARCH_SQUASHFS_LEVEL="${SOLDARCH_SQUASHFS_LEVEL:-15}"
fi

echo "==> Сборка ISO ($MODE)"
mkarchiso -v -C "$PACMAN_LIVE" \
    -w "$ROOT/work-$MODE" -o "$ROOT/out" "$ROOT"

ISO=$(ls -1t "$ROOT/out/${SOLDARCH_ISO_NAME}"-*.iso 2>/dev/null | head -n1 || true)
[[ -n "$ISO" && -s "$ISO" ]] || {
    echo "mkarchiso не создал ISO" >&2
    exit 1
}

if [[ "$MODE" == "test-auto" ]]; then
    ln -sfn "$(basename "$ISO")" "$ROOT/out/soldarch-test.iso"
else
    ln -sfn "$(basename "$ISO")" "$ROOT/out/soldarch.iso"
fi

echo
echo "==> ISO готов: $ISO"
ls -lh "$ISO" "$ROOT/out/soldarch-test.iso" 2>/dev/null || true
