#!/usr/bin/env bash
# Склейка видео-прохода по приложению из кадров.
#
# Кадры генерирует `flutter test tool/generate_walkthrough_test.dart`,
# здесь они собираются в MP4.
#
# Зачем вообще: ни устройства, ни эмулятора под рукой нет, а показать команде
# работающее приложение надо. Кадры снимаются с настоящих экранов и настоящего
# состояния — сценарий прогоняется через игровое ядро. Когда появится телефон,
# запись экрана это заменит.
#
#   ./tool/make_walkthrough.sh            2.8 с на кадр
#   ./tool/make_walkthrough.sh 3.5        3.5 с на кадр

set -euo pipefail

DIR="build/walkthrough"
OUT="build/finni-walkthrough.mp4"
HOLD="${1:-2.8}"

command -v ffmpeg >/dev/null || { echo "ffmpeg не найден: brew install ffmpeg"; exit 1; }
[ -d "$DIR" ] || { echo "Нет кадров. Сначала: flutter test tool/generate_walkthrough_test.dart"; exit 1; }

LIST="$DIR/concat.txt"
: > "$LIST"
for f in "$DIR"/frame-*.png; do
  echo "file '$(basename "$f")'" >> "$LIST"
  echo "duration $HOLD" >> "$LIST"
done
# Последний кадр повторяется: демультиплексор concat игнорирует duration
# у последней записи, и без повтора финальный кадр мелькнёт на один кадр.
last=$(ls "$DIR"/frame-*.png | tail -1)
echo "file '$(basename "$last")'" >> "$LIST"

ffmpeg -y -loglevel error \
  -f concat -safe 0 -i "$LIST" \
  -vf "fps=30,format=yuv420p" \
  -c:v libx264 -preset slow -crf 20 -movflags +faststart \
  "$OUT"

SIZE=$(du -h "$OUT" | cut -f1)
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" | cut -d. -f1)
echo "Готово: $OUT — ${DUR} с, $SIZE"
