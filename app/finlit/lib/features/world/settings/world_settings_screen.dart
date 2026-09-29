import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../core/world_theme.dart';
import '../../../domain/models/profile.dart';
import '../../settings/settings_screen.dart' show SettingsScreen;
import '../shop/shop_kit.dart';
import '../world_help.dart';
import '../world_layout.dart';

/// S15 — настройки нового мира: звук и анимации (ТЗ 3.6.7), лицензии.
///
/// Флаги — те же, что у старого [SettingsScreen]: профиль [AppState], запись
/// через [AppState.updateProfile]. Второго хранилища нет, а читает флаги
/// одно место — `core/feel.dart` (`context.cue`, `context.motion`).
///
/// Чего здесь нет и почему:
/// - «Читать вслух» — мир ничего не озвучивает (ни `Speaker`, ни карточки
///   последствия), тумблер был бы мёртвой ручкой;
/// - «Числа покрупнее» — масштаб живёт в экономике старой игры, числа мира
///   берутся из `assets/content/world/*.json` и от флага не зависят;
/// - сброс и режим проверки — только за барьером «Взрослым» (🔒 в комнате).
class WorldSettingsScreen extends StatelessWidget {
  const WorldSettingsScreen({super.key});

  static const Key soundKey = ValueKey<String>('settings:sound');
  static const Key motionKey = ValueKey<String>('settings:motion');
  static const Key helpKey = ValueKey<String>('settings:help');

  /// Профиль может ещё не прочитаться (заставка), а в тестах одного экрана
  /// провайдера нет вовсе — тогда экран честно говорит, что ждёт.
  static AppState? _appOrNull(BuildContext context) {
    try {
      return context.watch<AppState>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState? app = _appOrNull(context);
    final bool land = WorldLayout.isLandscape(context);
    return Scaffold(
      backgroundColor: WorldColors.night,
      appBar: AppBar(
        // Альбомная — основная: низкая шапка, как у «Взрослым».
        toolbarHeight: land ? 48 : null,
        leading: IconButton(
          key: const ValueKey<String>('settings:back'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Настройки'),
        actions: <Widget>[
          HelpButton(
            key: helpKey,
            onPressed: () => showHelp(
                context,
                'Что здесь?',
                'Здесь настраивают звук и движение.\n\n'
                    '«Звуки» — щелчок и вибрация, когда смена получилась.\n'
                    '«Анимации» — движутся ли Финни, питомцы и экраны. '
                    'Выключишь — всё стоит на месте.\n\n'
                    'Начать игру заново можно только в разделе «Взрослым» '
                    '(замок в комнате).'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: app == null || !app.ready
            ? const Center(child: Text('Настройки загружаются', style: kitText))
            : _Body(app: app),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final GameProfile profile = app.game.profile;
    final GameSettings s = profile.settings;
    Future<void> apply(GameSettings next) =>
        app.updateProfile(profile.copyWith(settings: next));

    final Widget feel = _Block(
      icon: Icons.volume_up_rounded,
      title: 'Звук и движение',
      children: <Widget>[
        _Toggle(
          key: WorldSettingsScreen.soundKey,
          title: 'Звуки',
          // По факту: игра сама звучит только щелчком с вибрацией, когда
          // смена сделана верно (`context.cue`). Музыки и озвучки нет.
          // 🔴 Щелчок на каждое касание кнопки на Android играет система
          // («Звук касаний»), а не игра, — тумблер его не гасит, и подпись
          // не обещает «полную тишину»: об этом сказано в блоке ниже.
          text: 'Щелчок и вибрация, когда смена получилась.',
          value: s.soundOn,
          onChanged: (bool v) => apply(s.copyWith(soundOn: v)),
        ),
        _Toggle(
          key: WorldSettingsScreen.motionKey,
          title: 'Анимации',
          text: 'Финни, питомцы, переходы между экранами. '
              'Выключено — всё стоит на месте.',
          value: s.animationsOn,
          onChanged: (bool v) => apply(s.copyWith(animationsOn: v)),
        ),
      ],
    );
    // ТЗ 3.6.7, вторая половина: важное не передаётся одним звуком.
    const Widget note = _Block(
      icon: Icons.visibility_outlined,
      title: 'Всё видно и без звука',
      children: <Widget>[
        Text(
            'Монеты, цель и что изменилось всегда написаны на экране. '
            'Щелчок при нажатии кнопок — звук телефона, он выключается '
            'в настройках телефона, как и «Убрать анимацию».',
            style: kitSoft),
      ],
    );
    final Widget about = _Block(
      icon: Icons.info_outline_rounded,
      title: 'О приложении',
      children: <Widget>[
        const Text('Финни, версия ${SettingsScreen.version}', style: kitText),
        const Text(
            'Игра без рекламы и покупок. Работает без сети, всё хранится '
            'только на этом устройстве.',
            style: kitSoft),
        const SizedBox(height: Gap.sm),
        // Экран внутри приложения, а не ссылка наружу (ТЗ 3.5). Тексты
        // лицензий шрифтов регистрирует main.dart.
        OutlinedButton.icon(
          key: const ValueKey<String>('settings:licenses'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(TapSize.min)),
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Финни',
            applicationVersion: SettingsScreen.version,
          ),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Лицензии', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: Gap.sm),
        const Text(
            'Начать игру заново и режим проверки — в разделе «Взрослым» '
            '(замок в комнате).',
            style: kitSoft),
      ],
    );

    if (!WorldLayout.isLandscape(context)) {
      return ListView(
        key: const ValueKey<String>('settings:list'),
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.lg),
        children: <Widget>[feel, note, about],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            key: const ValueKey<String>('settings:list'),
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.md),
            children: <Widget>[feel],
          ),
        ),
        Expanded(
          child: ListView(
            key: const ValueKey<String>('settings:list:more'),
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.md, Gap.md),
            children: <Widget>[about, note],
          ),
        ),
      ],
    );
  }
}

/// Строка-переключатель: название и тумблер в строку, пояснение под ними
/// на всю ширину — в альбомной половине экрана SwitchListTile сжимал
/// пояснение в узкий столбец в шесть строк.
///
/// Тап по всей строке переключает. [MergeSemantics] склеивает название
/// с ролью и состоянием тумблера: TalkBack читает «Анимации, включено».
class _Toggle extends StatelessWidget {
  const _Toggle({
    super.key,
    required this.title,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String text;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(WorldRadii.tile),
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: TapSize.min),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(title, style: kitTitle)),
                      Switch(value: value, onChanged: onChanged),
                    ],
                  ),
                ),
                Text(text, style: kitSoft),
              ],
            ),
          ),
        ),
      );
}

class _Block extends StatelessWidget {
  const _Block(
      {required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, color: WorldColors.text),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Semantics(
                        header: true, child: Text(title, style: kitTitle)),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              ...children,
            ],
          ),
        ),
      );
}
