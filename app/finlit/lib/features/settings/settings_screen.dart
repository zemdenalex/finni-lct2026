import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/icons.dart';
import '../../core/speaker.dart';
import '../../core/theme.dart';
import '../../domain/models/profile.dart';
import '../../routes.dart';

/// Настройки (§3.6).
///
/// Требования пункта, из которых собран экран:
/// §3.6.7 — «звуки и анимации можно отключить; критически важная информация
///           не передаётся только звуком»;
/// §3.6.4 — «читаемость сохраняется при системном увеличении шрифта»;
/// §3.5   — в детской части нет внешних ссылок, поэтому «О приложении»
///           здесь — текст, а не ссылка на сайт.
///
/// Экран без собственного состояния: каждый переключатель пишет в профиль
/// через [AppState.updateProfile], а профиль сохраняется на диск.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Версия приложения. Захардкожена сознательно: package_info_plus — это
  /// ещё одна зависимость и плагин с нативной частью ради одной строки,
  /// которую всё равно правит человек при выпуске.
  static const String version = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: Text('Настройки')));
    }

    final GameProfile profile = app.game.profile;
    final GameSettings s = profile.settings;

    Future<void> apply(GameSettings next) =>
        app.updateProfile(profile.copyWith(settings: next));

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xl),
          children: <Widget>[
            _Group(
              title: 'Звук и движение',
              children: <Widget>[
                _SwitchRow(
                  icon: Pic.sound,
                  title: 'Звуки',
                  // Подпись описывает ровно то, что есть: системный щелчок и
                  // короткая вибрация. Музыки и озвученных эффектов в игре
                  // нет, и обещать их подписью нельзя.
                  subtitle: 'Щелчок и вибрация, когда приходят и уходят '
                      'монетки. Выключено — тишина, и чтение вслух тоже.',
                  value: s.soundOn,
                  onChanged: (bool v) => apply(s.copyWith(soundOn: v)),
                ),
                _SwitchRow(
                  icon: Pic.motion,
                  title: 'Анимации',
                  // Тоже по факту: движутся листание знакомства и карточка
                  // «что изменилось». Никаких летающих монеток в игре нет.
                  subtitle: 'Листание, подскок Финни, выезжающие карточки. '
                      'Выключи, если движение мешает. «Убрать анимацию» '
                      'в настройках телефона тоже работает.',
                  value: s.animationsOn,
                  onChanged: (bool v) => apply(s.copyWith(animationsOn: v)),
                ),
                // 🔴 Подписка, а не разовое чтение. Проверка голоса теперь
                // идёт после первого кадра, чтобы не задерживать запуск
                // (§3.4.5), — значит, на момент первой сборки этого экрана
                // ответа от системы может ещё не быть. Без подписки взрослый
                // увидел бы «озвучка недоступна» на рабочем устройстве.
                ValueListenableBuilder<bool>(
                  valueListenable: Speaker.instance.availability,
                  builder: (BuildContext context, bool canSpeak, _) =>
                      Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                  // 🔴 Переключатель существует, только если озвучка реально
                  // работает. Синтезатор системный: без русского голоса
                  // «Читать вслух» ничего не включает, а тумблер, который
                  // ничего не делает, — это обещание, которое продукт не
                  // выполняет. Лучше честная строка, чем мёртвая ручка.
                  if (canSpeak)
                    _SwitchRow(
                      icon: Pic.speak,
                      title: 'Читать вслух',
                      // Честная подпись: озвучены не все экраны, а объяснения —
                      // те самые карточки «что изменилось и почему» (§2.2).
                      subtitle: 'Ключевые объяснения можно прослушать. '
                          'Работает офлайн, голосом системы.',
                      value: s.readAloud,
                      onChanged: (bool v) => apply(s.copyWith(readAloud: v)),
                    )
                  else
                    const _InfoRow(
                      icon: Pic.speakOff,
                      title: 'Читать вслух',
                      subtitle: 'Озвучка недоступна: на устройстве нет русского '
                          'голоса. Всё, что говорит Финни, написано на экране — '
                          'без озвучки игра полная.',
                    ),
                  // 🔴 Со снятыми «Звуками» приложение молчит целиком, и кнопка
                  // проверки замолчала бы вместе с ним — взрослый решил бы, что
                  // озвучка сломана. Вместо мёртвой кнопки — строка с причиной.
                  if (canSpeak && !s.soundOn)
                    const _InfoRow(
                      icon: Pic.soundOff,
                      title: 'Голос сейчас молчит',
                      subtitle: 'Пока «Звуки» выключены, Финни не говорит вслух. '
                          'Включи звуки, чтобы проверить голос.',
                    ),
                  if (canSpeak && s.soundOn)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Gap.md, 0, Gap.md, Gap.sm),
                      child: OutlinedButton.icon(
                        icon: const Pictogram(Pic.sound,
                            color: AppColors.primary),
                        label: const Text('Проверить голос'),
                        // Взрослому нужно услышать звук до того, как он отдаст
                        // телефон ребёнку: громкость, язык и сам факт речи
                        // проверяются здесь, а не посреди игры.
                        onPressed: () =>
                            Speaker.instance.speak('Привет! Я Финни.'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(TapSize.min),
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            // §3.6.7, вторая половина: «критически важная информация не
            // передаётся только звуком». Это свойство приложения, а не
            // переключатель, поэтому оно здесь написано, а не включается.
            const _Note(
              icon: Pic.soundOff,
              text: 'Со звуком и без звука игра одинаковая: всё важное — '
                  'сколько монеток, что изменилось и почему — всегда написано '
                  'на экране. Звук ничего не сообщает в одиночку.',
            ),
            const SizedBox(height: Gap.md),
            _Group(
              title: 'Числа',
              children: <Widget>[
                _SwitchRow(
                  icon: Pic.calc,
                  title: 'Числа покрупнее',
                  subtitle: 'Для тех, кто уже уверенно считает до ста.',
                  value: s.bigNumbers,
                  onChanged: (bool v) async {
                    // 🔴 Переключатель меняет масштаб всей экономики: цены,
                    // карманные и цели пересчитываются и перезагружаются из
                    // контента. Это «действие, заметно меняющее прогресс»
                    // по §3.6 — значит, через подтверждение.
                    final bool ok = await _confirmScale(context, on: v);
                    if (!ok) return;
                    await apply(s.copyWith(bigNumbers: v));
                  },
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            _Group(
              title: 'О приложении',
              children: <Widget>[
                const _InfoRow(
                  icon: Pic.family,
                  title: 'Возрастная маркировка 0+',
                  subtitle: 'Игра без насилия, азарта, рекламы и покупок '
                      'внутри приложения.',
                ),
                const _InfoRow(
                  icon: Pic.lock,
                  title: 'Данные только на устройстве',
                  subtitle: 'Приложение работает без сети и без аккаунта. '
                      'Ничего никуда не отправляется.',
                ),
                const _InfoRow(
                  icon: Pic.info,
                  title: 'Финни, версия $version',
                  subtitle: 'Учебная игра о карманных деньгах для детей '
                      '7–11 лет.',
                ),
                // §2.5.13: демонстрационный режим существует «для экспертной
                // проверки», а найти его эксперт должен с первого запуска.
                // Единственная ссылка на главном экране показывалась только
                // когда режим уже включён, — то есть путь внутрь был замкнут
                // сам на себя. Здесь он открыт всегда.
                _InfoRow(
                  icon: Pic.flask,
                  title: 'Демонстрационный режим (для проверки)',
                  subtitle: 'Переключает игру на отдельный тестовый профиль '
                      'и открывает экран «Проверка». Игру ребёнка не трогает: '
                      'она ждёт на своём месте.',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.demo),
                ),
                // Экран внутри приложения, а не ссылка наружу, — §3.5 соблюдён.
                _InfoRow(
                  icon: Pic.book,
                  title: 'Лицензии',
                  subtitle: 'Шрифты и библиотеки, из которых собрана игра.',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Финни',
                    applicationVersion: version,
                  ),
                ),
                const _InfoRow(
                  icon: Pic.lock,
                  title: 'Раздел для взрослого',
                  // Ссылки наружу в детской части запрещены §3.5, поэтому
                  // это подсказка, а не кнопка: путь к разделу один и тот же
                  // с главного экрана, и взрослый его запоминает.
                  subtitle: 'Сброс и удаление данных, а также подсказки для '
                      'разговора с ребёнком — на главном экране, плитка '
                      '«Взрослым».',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmScale(BuildContext context, {required bool on}) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(on ? 'Включить крупные числа?' : 'Вернуть обычные числа?',
          style: const TextStyle(fontSize: 22)),
      content: Text(
        on
            ? 'Карманные, цены и цели станут в пять раз больше: вместо 10 '
                'монеток в неделю — 50. Игровые числа перезагрузятся. '
                'Накопленное не пропадёт, но суммы на экранах будут другими.'
            : 'Карманные, цены и цели вернутся к суммам в пределах двадцати. '
                'Игровые числа перезагрузятся. Накопленное не пропадёт.',
        style: const TextStyle(fontSize: 16),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size(120, TapSize.min)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Продолжить'),
        ),
      ],
    ),
  );
  return answer ?? false;
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: Gap.xs, bottom: Gap.sm),
          child: Semantics(
            header: true,
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

/// Строка-переключатель.
///
/// SwitchListTile сам выдаёт корректную семантику (роль «переключатель» и
/// состояние), поэтому своего Semantics здесь нет — второй слой только
/// сломал бы озвучку.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Pic icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TapSize.min),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: Gap.md, vertical: Gap.xs),
        secondary: Pictogram(icon, size: 26, color: AppColors.primary),
        title: Text(title,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
        isThreeLine: false,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final Pic icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TapSize.min),
      child: ListTile(
        onTap: onTap,
        trailing: onTap == null
            ? null
            : const Pictogram(Pic.arrowRight, color: AppColors.inkSoft),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: Gap.md, vertical: Gap.xs),
        leading: Pictogram(icon, size: 26, color: AppColors.primary),
        title: Text(title,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 16, color: AppColors.inkSoft)),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final Pic icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.needsBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Pictogram(icon, size: 24, color: AppColors.needs),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
