#!/usr/bin/env bash
# Замер холодного старта приложения.
#
# §3.4 ТЗ: «на физическом тестовом устройстве приложение запускается до главного
# или стартового экрана не более чем за 5 секунд». Порог Android vitals для
# холодного старта — ровно 5 секунд («excessive»), то есть требование ТЗ совпадает
# с границей «медленно» по Google. Поэтому целимся в 2 секунды, а не в 4,9.
#
# 🔴 Одно красивое число эксперт не засчитает. Скрипт делает серию прогонов,
# отбрасывает прогревочный и выдаёт min / median / mean / max вместе с моделью
# устройства, версией Android, ABI и версией Flutter — это и есть отчёт для §5 п.10.
#
# 🔴 Мерить только релизную сборку. В debug каждый кадр идёт через JIT, и
# холодный старт выходит в разы дольше — такое число в документации будет
# враньём в худшую сторону. Скрипт сам проверяет флаг DEBUGGABLE у того, что
# стоит на устройстве, и отказывается считать, если это debug.
#
# 🔴 Эмулятор — не телефон. §3.4 ТЗ говорит «на физическом тестовом
# устройстве», а §3.1.3 отдельно требует проверки не только в эмуляторе.
# Скрипт печатает, на чём он мерил, и это должно попасть в отчёт дословно.
#
# Перед прогоном:
#   flutter build apk --release
#   adb install -r build/app/outputs/flutter-apk/app-release.apk
#
# Использование:
#   ./tool/measure_startup.sh            10 прогонов
#   ./tool/measure_startup.sh 20         20 прогонов

set -euo pipefail

PKG="ru.lct2026.finlit"
ACT=".MainActivity"
RUNS="${1:-10}"

command -v adb >/dev/null || { echo "adb не найден в PATH"; exit 1; }

DEVICES=$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | wc -l | tr -d ' ')
if [ "$DEVICES" -eq 0 ]; then
  echo "🔴 Устройство не подключено. adb devices пуст."
  echo "   Включите «Отладка по USB» и подтвердите отпечаток на телефоне."
  exit 1
fi

IS_EMULATOR=$(adb shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')
[ -z "$IS_EMULATOR" ] && IS_EMULATOR=$(adb shell getprop ro.boot.qemu 2>/dev/null | tr -d '\r')

echo "УСТРОЙСТВО"
echo "  модель:   $(adb shell getprop ro.product.brand | tr -d '\r') $(adb shell getprop ro.product.model | tr -d '\r')"
echo "  Android:  $(adb shell getprop ro.build.version.release | tr -d '\r') (API $(adb shell getprop ro.build.version.sdk | tr -d '\r'))"
echo "  ABI:      $(adb shell getprop ro.product.cpu.abi | tr -d '\r')"
echo "  память:   $(adb shell cat /proc/meminfo | awk '/MemTotal/ {printf "%.1f ГБ", $2/1024/1024}')"
echo "  батарея:  $(adb shell dumpsys battery | awk '/level/ {print $2"%"}')"
if [ "$IS_EMULATOR" = "1" ]; then
  echo "  🔴 это ЭМУЛЯТОР. §3.4 требует замера на физическом устройстве,"
  echo "     эти числа — только предварительная оценка."
else
  echo "  тип:      физическое устройство"
fi
echo

# 🔴 Что именно стоит на устройстве: debug-сборка завышает старт в разы.
if ! adb shell pm path "$PKG" >/dev/null 2>&1; then
  echo "🔴 Пакет $PKG на устройстве не установлен."
  echo "   flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk"
  exit 1
fi
if adb shell dumpsys package "$PKG" | grep -q "DEBUGGABLE"; then
  echo "🔴 На устройстве стоит DEBUG-сборка. Замер отменён: число будет"
  echo "   в разы хуже настоящего. Поставьте релизную:"
  echo "   flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk"
  exit 1
fi
echo "СБОРКА НА УСТРОЙСТВЕ: релизная (флага DEBUGGABLE нет)"
echo
echo "СБОРКА"
flutter --version | head -1
echo

# Системные анимации искажают замер — гасим на время и возвращаем в конце.
restore_animations() {
  adb shell settings put global window_animation_scale 1 || true
  adb shell settings put global transition_animation_scale 1 || true
  adb shell settings put global animator_duration_scale 1 || true
}
trap restore_animations EXIT
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

echo "ПРОГОНЫ (первый — прогревочный, в статистику не идёт)"
echo "  TotalTime — до первого кадра приложения; WaitTime — вся дорога,"
echo "  которую ждёт человек, включая работу системы до запуска процесса."
TIMES=()
WAITS=()
for i in $(seq 0 "$RUNS"); do
  # -S = force-stop перед запуском, то есть именно холодный старт.
  OUT=$(adb shell am start -S -W -n "$PKG/$ACT" \
        -c android.intent.category.LAUNCHER \
        -a android.intent.action.MAIN 2>/dev/null)
  T=$(echo "$OUT" | awk -F': ' '/TotalTime/ {print $2}' | tr -d '\r')
  W=$(echo "$OUT" | awk -F': ' '/WaitTime/ {print $2}' | tr -d '\r')
  if [ -z "$T" ]; then echo "  прогон $i: не удалось прочитать TotalTime"; continue; fi
  if [ "$i" -eq 0 ]; then
    echo "  прогрев: total ${T} мс / wait ${W:-—} мс (отброшен)"
  else
    echo "  прогон $i: total ${T} мс / wait ${W:-—} мс"
    TIMES+=("$T")
    [ -n "$W" ] && WAITS+=("$W")
  fi
  sleep 1
done

if [ "${#TIMES[@]}" -lt 5 ]; then
  echo "🔴 Удачных прогонов меньше пяти — медиана по такому ряду ничего не значит."
  exit 1
fi

printf '%s\n' "${TIMES[@]}" | sort -n | awk '
  { a[NR]=$1; s+=$1 }
  END {
    n=NR
    med = (n%2) ? a[(n+1)/2] : (a[n/2]+a[n/2+1])/2
    printf "\nИТОГ по %d прогонам\n", n
    printf "  min     %d мс\n", a[1]
    printf "  медиана %d мс   ← это число идёт в документацию\n", med
    printf "  среднее %.0f мс\n", s/n
    printf "  max     %d мс\n", a[n]
    printf "\n  порог ТЗ §3.4: 5000 мс. Медиана %s; худший прогон %s\n", \
      (med <= 2000 ? "🟢 с запасом" : (med <= 5000 ? "🟡 проходит, но близко" : "🔴 НЕ ПРОХОДИТ")), \
      (a[n] <= 5000 ? "тоже в пороге" : "🔴 ВЫШЕ ПОРОГА")
  }'

if [ "${#WAITS[@]}" -ge 5 ]; then
  printf '%s\n' "${WAITS[@]}" | sort -n | awk '
    { a[NR]=$1 }
    END {
      n=NR
      med = (n%2) ? a[(n+1)/2] : (a[n/2]+a[n/2+1])/2
      printf "\nWaitTime по %d прогонам\n", n
      printf "  медиана %d мс\n", med
      printf "  max     %d мс\n", a[n]
    }'
fi

echo
echo "ВТОРАЯ, НЕЗАВИСИМАЯ МЕТРИКА — Displayed из logcat"
echo "  (документированная Google метрика TTID; TotalTime описан только примером вывода)"
adb logcat -d | grep "Displayed $PKG" | tail -3 || echo "  записей нет — очистите logcat и повторите"
