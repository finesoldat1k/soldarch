#!/usr/bin/env bash
# build-repo.sh — собирает офлайн-репозиторий в airootfs/opt/soldarch/repo.
#
# Запуск от обычного пользователя, без sudo:
#   ./scripts/build-repo.sh
#
# Скрипт:
#   1. скачивает свежие core.db / extra.db / multilib.db;
#   2. считает точный dependency closure для target- и live-пакетов;
#   3. берёт совпавшие по имени/версии пакеты из /var/cache/pacman/pkg,
#      остальные докачивает параллельно;
#   4. собирает throne-bin и soldarch-zapret через makepkg;
#   5. создаёт soldarch.db.tar.gz через repo-add.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$ROOT/airootfs/opt/soldarch/repo"
WORK="$ROOT/build/repo"
SYNC="$WORK/root/var/lib/pacman/sync"
CACHE="$ROOT/build/pkgcache"
PACMAN_CONF="$WORK/pacman-repo.conf"
TARGET_FILE="$ROOT/airootfs/opt/soldarch/packages-target.txt"
LIVE_FILE="$ROOT/packages.x86_64"
HOST_CACHE="/var/cache/pacman/pkg"
MIRROR="${SOLDARCH_MIRROR:-https://geo.mirror.pkgbuild.com}"
JOBS="${SOLDARCH_JOBS:-12}"
LOCAL_PKGS=(throne-bin soldarch-zapret)

die() { echo "Ошибка: $*" >&2; exit 1; }
msg() { echo "==> $*"; }

(( EUID != 0 )) || die "запускайте скрипт от обычного пользователя, без sudo"

for cmd in pacman curl repo-add makepkg bsdtar xargs; do
    command -v "$cmd" >/dev/null 2>&1 || die "не найдена утилита: $cmd"
done

mkdir -p "$REPO" "$WORK" "$SYNC" "$CACHE" "$WORK/gnupg" "$WORK/hooks" \
    "$WORK/root/var/lib/pacman/local" "$WORK/aur" "$WORK/src"

# Чистим только незавершённые загрузки и старую базу. Готовые пакеты
# оставляем: повторный запуск докачает только недостающее.
find "$REPO" -maxdepth 1 -type f \
    \( -name '*.pkg.tar.zst.part' -o -name '*.sig' \
       -o -name 'soldarch.db*' -o -name 'soldarch.files*' -o -name '*.old' \) \
    -delete 2>/dev/null || true

# ── 1. Свежие базы пакетов ───────────────────────────────────
download_db() {
    local name="$1" dest="$SYNC/$1.db"
    if [[ -s "$dest" ]]; then
        msg "База $name уже скачана"
        return 0
    fi
    msg "Скачивание $name.db"
    curl -fL --retry 6 --retry-delay 5 --retry-all-errors \
        --connect-timeout 20 --max-time 1800 \
        -o "$dest.part" "$MIRROR/$name/os/x86_64/$name.db" || {
        rm -f "$dest.part"
        die "не удалось скачать $name.db"
    }
    bsdtar -tf "$dest.part" >/dev/null 2>&1 || {
        rm -f "$dest.part"
        die "$name.db повреждён"
    }
    mv "$dest.part" "$dest"
}

for db in core extra multilib; do
    download_db "$db"
done

cat >"$PACMAN_CONF" <<EOF
[options]
HoldPkg = pacman glibc
Architecture = auto
SigLevel = Optional TrustAll
LocalFileSigLevel = Optional
DBPath = $WORK/root/var/lib/pacman
CacheDir = $CACHE
GPGDir = $WORK/gnupg
LogFile = $WORK/pacman.log
HookDir = $WORK/hooks
ParallelDownloads = 10

[core]
Server = $MIRROR/\$repo/os/\$arch

[extra]
Server = $MIRROR/\$repo/os/\$arch

[multilib]
Server = $MIRROR/\$repo/os/\$arch
EOF

# ── 2. Список пакетов и dependency closure ───────────────────
read_pkg_file() {
    sed 's/#.*//' "$1" | tr -s '[:space:]' '\n' | sed '/^$/d'
}

declare -A seen=()
declare -a requested=()
add_pkg() {
    local p="$1" local_p
    [[ -n "$p" ]] || return 0
    for local_p in "${LOCAL_PKGS[@]}"; do
        [[ "$p" == "$local_p" ]] && return 0
    done
    [[ -n "${seen[$p]:-}" ]] && return 0
    seen[$p]=1
    requested+=("$p")
}

while IFS= read -r pkg; do add_pkg "$pkg"; done < <(read_pkg_file "$TARGET_FILE")
# Пакеты профилей нужны в репозитории, даже если профиль не выбран:
# установщик добавляет их к базовому набору на этапе pacstrap.
for extra in "$ROOT/airootfs/opt/soldarch/packages-developer.txt" \
             "$ROOT/airootfs/opt/soldarch/packages-gaming.txt"; do
    [[ -f "$extra" ]] || continue
    while IFS= read -r pkg; do add_pkg "$pkg"; done < <(read_pkg_file "$extra")
done
while IFS= read -r pkg; do add_pkg "$pkg"; done < <(read_pkg_file "$LIVE_FILE")

msg "Пакетов в запросе: ${#requested[@]}"
msg "Разрешение зависимостей"
if ! pacman -Sp --print-format '%n|%v|%a|%f|%r' \
    --config "$PACMAN_CONF" \
    --root "$WORK/root" \
    --dbpath "$WORK/root/var/lib/pacman" \
    --disable-sandbox --noconfirm \
    "${requested[@]}" >"$WORK/closure.txt" 2>"$WORK/closure.err"; then
    cat "$WORK/closure.err" >&2
    die "pacman не смог разрешить зависимости"
fi

declare -A pkg_repo=()
declare -a files=()
while IFS='|' read -r _name _ver _arch file repo; do
    [[ -n "$file" ]] || continue
    [[ -n "${pkg_repo[$file]:-}" ]] && continue
    pkg_repo[$file]="$repo"
    files+=("$file")
done <"$WORK/closure.txt"

(( ${#files[@]} > 0 )) || die "dependency closure пуст"
msg "В репозитории должно быть файлов: ${#files[@]}"

# Убираем пакеты, которые больше не входят в closure (например, после
# изменения списка пакетов). Локальные пакеты не трогаем.
while IFS= read -r existing; do
    base="${existing##*/}"
    [[ -n "${pkg_repo[$base]:-}" ]] && continue
    case "$base" in
        throne-bin-*|soldarch-zapret-*) continue ;;
    esac
    echo "  удаляю лишний пакет: $base"
    rm -f "$existing"
done < <(find "$REPO" -maxdepth 1 -type f -name '*.pkg.tar.zst' -printf '%p\n')

# ── 3. Host-кэш и докачка недостающего ───────────────────────
cached=0
for file in "${files[@]}"; do
    [[ -s "$REPO/$file" ]] && continue
    src="$HOST_CACHE/$file"
    if [[ -r "$src" && -s "$src" ]]; then
        if cp -f --reflink=auto "$src" "$REPO/$file" 2>/dev/null; then
            cached=$((cached + 1))
        else
            rm -f "$REPO/$file"
        fi
    fi
done
msg "Взято из host-кэша: $cached"

declare -a missing=()
for file in "${files[@]}"; do
    [[ -s "$REPO/$file" ]] && continue
    repo="${pkg_repo[$file]}"
    missing+=("$MIRROR/$repo/os/x86_64/$file|$file")
done

download_one() {
    local spec="$1" url="${1%%|*}" file="${1#*|}"
    local dest="$REPO/$file" part="$REPO/$file.part"
    [[ -s "$dest" ]] && return 0
    if ! curl -fL --retry 6 --retry-delay 5 --retry-all-errors \
        --connect-timeout 20 --max-time 7200 \
        --continue-at - -o "$part" "$url" 2>/dev/null; then
        rm -f "$part"
        curl -fL --retry 6 --retry-delay 5 --retry-all-errors \
            --connect-timeout 20 --max-time 7200 \
            -o "$part" "$url" || return 1
    fi
    mv "$part" "$dest"
}
export REPO
export -f download_one

download_all() {
    (( ${#missing[@]} > 0 )) || return 0
    msg "Докачка ${#missing[@]} пакетов (${JOBS} потоков)"
    printf '%s\n' "${missing[@]}" | xargs -r -P "$JOBS" -n1 bash -c 'download_one "$1"' _
}

# ── 4. Локальные пакеты ──────────────────────────────────────
build_local() {
    local aur="$WORK/aur/throne-bin"
    if [[ ! -f "$aur/PKGBUILD" ]]; then
        msg "Загрузка AUR-снимка throne-bin"
        mkdir -p "$aur"
        curl -fL --retry 6 --retry-delay 5 --retry-all-errors \
            "https://aur.archlinux.org/cgit/aur.git/snapshot/throne-bin.tar.gz" | \
            tar -xz -C "$aur" --strip-components=1
    fi

    # Ускоряем сборку soldarch-zapret: если исходники уже распакованы
    # в /tmp/soldarch-src, кладём их в SRCDEST готовыми tarball'ами.
    if [[ ! -f "$WORK/src/zapret.tar.gz" && -d /tmp/soldarch-src/zapret ]]; then
        msg "Упаковка локального zapret"
        tar -C /tmp/soldarch-src -czf "$WORK/src/zapret.tar.gz" \
            --transform 's,^zapret,zapret-v72.13,' zapret
    fi
    if [[ ! -f "$WORK/src/zapret.cfgs.tar.gz" && -d /tmp/soldarch-src/cfgs ]]; then
        msg "Упаковка локальных zapret.cfgs"
        tar -C /tmp/soldarch-src -czf "$WORK/src/zapret.cfgs.tar.gz" \
            --transform 's,^cfgs,zapret.cfgs-a91a433939db2e0164997f5e8cba3bcf15255549,' cfgs
    fi

    msg "Сборка throne-bin"
    ( cd "$aur" && PKGDEST="$REPO" SRCDEST="$WORK/src" BUILDDIR="$WORK/build-throne" \
        makepkg -f --noconfirm --nodeps --cleanbuild )

    msg "Сборка soldarch-zapret"
    ( cd "$ROOT/packages/soldarch-zapret" && \
        PKGDEST="$REPO" SRCDEST="$WORK/src" BUILDDIR="$WORK/build-zapret" \
        makepkg -f --noconfirm --nodeps --cleanbuild )
}

# Скачивание и сборка локальных пакетов идут параллельно.
download_all &
DL_PID=$!
build_local
if ! wait "$DL_PID"; then
    die "не все пакеты скачались"
fi

# ── 5. Проверка и repo-add ───────────────────────────────────
failed=0
for file in "${files[@]}"; do
    if [[ ! -s "$REPO/$file" ]]; then
        echo "  отсутствует: $file" >&2
        failed=1
    fi
done
(( failed == 0 )) || die "репозиторий неполный"

for pkg in "${LOCAL_PKGS[@]}"; do
    find "$REPO" -maxdepth 1 -name "${pkg}-*.pkg.tar.zst" -size +0 -print -quit | \
        grep -q . || die "не собран локальный пакет: $pkg"
done

msg "Создание базы репозитория"
repo-add -q "$REPO/soldarch.db.tar.gz" "$REPO"/*.pkg.tar.zst

echo
msg "Готово"
printf 'Пакетов: %s\n' "$(find "$REPO" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)"
printf 'Размер:  %s\n' "$(du -sh "$REPO" | cut -f1)"
printf 'База:    %s\n' "$REPO/soldarch.db.tar.gz"
