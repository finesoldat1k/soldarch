#!/usr/bin/env bash
# download-video.sh — готовит открытое видео для приветственного экрана
# установщика. Big Buck Bunny © Blender Foundation, лицензия CC BY 3.0.
#
# Требует curl и ffmpeg. Архивный файл на archive.org помечен как h.264,
# но фактически содержит AV1, который в live-ISO декодируется очень медленно.
# Поэтому видео перекодируется в H.264 (avdec_h264 из gst-libav).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIDEO_DIR="$ROOT/airootfs/usr/share/soldarch/video"
OUTPUT="$VIDEO_DIR/soldarch-intro.mp4"
SOURCE="$VIDEO_DIR/.soldarch-intro-source.mp4"
URL="${SOLDARCH_VIDEO_URL:-https://archive.org/download/big-buck-bunny-multi-quality/big_buck_bunny_720p.mp4}"

mkdir -p "$VIDEO_DIR"

if [[ -s "$OUTPUT" ]]; then
    echo "Видео уже существует: $OUTPUT"
    ls -lh "$OUTPUT"
    exit 0
fi

for cmd in curl ffmpeg; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Ошибка: нужен $cmd" >&2
        exit 1
    }
done

cleanup() {
    rm -f "$SOURCE"
}
trap cleanup EXIT

echo "Скачивание Big Buck Bunny 720p (CC BY 3.0)..."
curl -fL --retry 6 --retry-delay 3 --retry-all-errors \
    --connect-timeout 20 \
    -o "$SOURCE.part" "$URL"
mv "$SOURCE.part" "$SOURCE"

echo "Перекодирование в H.264..."
ffmpeg -y -hide_banner -loglevel warning \
    -i "$SOURCE" \
    -c:v libx264 -preset medium -crf 25 \
    -pix_fmt yuv420p -profile:v high -level 4.0 \
    -c:a aac -b:a 128k \
    -movflags +faststart \
    "$OUTPUT.part"

mv "$OUTPUT.part" "$OUTPUT"
echo "Готово: $OUTPUT"
ffprobe -v error -show_entries stream=codec_name,width,height \
    -of default=nw=1 "$OUTPUT" 2>/dev/null || true
ls -lh "$OUTPUT"
