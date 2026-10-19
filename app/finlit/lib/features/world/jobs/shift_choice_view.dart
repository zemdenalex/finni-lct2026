import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/world_theme.dart';
import '../../../domain/world/contract.dart';
import '../../../domain/world/world_config.dart' show ceilPay;
import '../pic_text.dart';
import '../world_layout.dart';
import 'mini_games.dart' show gameText, gameTextCompact;

/// Мини-решение смены на экране (finni 17.10): вопрос «по пути» и 2–3
/// варианта с последствиями. Вопрос и числа — из [JobOffer.choice] и
/// [JobOffer.pay]; ответ уходит в `completeJob(choice:)`.

/// Заголовок блока вопроса.
// Нейтрально для любой работы и без рода (ревью 17.10).
const String shiftChoiceHeading = 'Что сделаешь?';

/// Строка под вопросом: выбор и есть начало смены.
const String shiftChoicePrompt = 'Выбери — и смена начнётся.';

/// Сколько монет вариант прибавит к оплате смены: та же формула, что у
/// `completeJob` (оплата × pay_x вверх до монеты минус оплата).
int shiftChoicePayDelta(JobOffer offer, ShiftChoiceOption option) =>
    ceilPay(offer.pay * option.payX) - offer.pay;

String _signed(String n, bool plus) => '${plus ? '+' : '−'}$n';

/// Последствия варианта значками: «+20 💰 · −2 ⚡ · +1 😊»; ничего не
/// меняет — пустая строка. ⚡ варианта — траты сверх цены смены, поэтому
/// со знаком минус.
String shiftChoiceEffects(JobOffer offer, ShiftChoiceOption option) {
  final int coins = shiftChoicePayDelta(offer, option);
  final double e = option.energy;
  final String energy = energyShown(e.abs());
  return <String>[
    if (coins != 0) '${_signed('${coins.abs()}', coins > 0)} 💰',
    if (energy != '0') '${_signed(energy, e < 0)} ⚡',
    if (option.happiness != 0)
      '${_signed('${option.happiness.abs()}', option.happiness > 0)} 😊',
  ].join(' · ');
}

/// Последствия только значками со знаком, без чисел: «+💰 · −⚡ · +😊» —
/// для альбомной при крупном шрифте, где числа рядом со словами не влезают
/// без прокрутки (ревью: значки не убирать совсем).
String shiftChoiceSigns(JobOffer offer, ShiftChoiceOption option) {
  final int coins = shiftChoicePayDelta(offer, option);
  final double e = option.energy;
  return <String>[
    if (coins != 0) '${coins > 0 ? '+' : '−'}💰',
    if (energyShown(e.abs()) != '0') '${e < 0 ? '+' : '−'}⚡',
    if (option.happiness != 0) '${option.happiness > 0 ? '+' : '−'}😊',
  ].join(' ');
}

/// Те же последствия словами для TalkBack (правило 4А Насти: «монеты»,
/// «силы»; именительный падеж — без согласования с числом).
String shiftChoiceSpoken(JobOffer offer, ShiftChoiceOption option) {
  final int coins = shiftChoicePayDelta(offer, option);
  final double e = option.energy;
  final String energy = energyShown(e.abs());
  final List<String> parts = <String>[
    if (coins != 0) 'монеты ${_signed('${coins.abs()}', coins > 0)}',
    if (energy != '0') 'силы ${_signed(energy, e < 0)}',
    if (option.happiness != 0)
      'настроение '
          '${_signed('${option.happiness.abs()}', option.happiness > 0)}',
  ];
  if (parts.isEmpty) return '';
  final String s = parts.join(', ');
  return '${s[0].toUpperCase()}${s.substring(1)}.';
}

/// Подсказка варианта словами («больше монет, но меньше сил») — из
/// контента (`effect_hint`, ветка texts-choices); нет — null.
String? shiftChoiceHint(ShiftChoiceOption option) => option.effectHint;

/// Блок вопроса на карточке смены: заголовок, вопрос и кнопки вариантов.
/// Нажатие на вариант начинает смену ([onPick]).
class ShiftChoiceBlock extends StatelessWidget {
  const ShiftChoiceBlock({
    super.key,
    required this.offer,
    required this.question,
    required this.onPick,
    this.hintOf = shiftChoiceHint,
  });

  final JobOffer offer;
  final ShiftChoice question;
  final ValueChanged<ShiftChoiceOption> onPick;

  /// Подсказка варианта словами или null (по умолчанию [shiftChoiceHint]).
  final String? Function(ShiftChoiceOption option) hintOf;

  @override
  Widget build(BuildContext context) {
    // Альбомная: высота дороже — без заголовка (вопрос и так первый в
    // панели), подсказка в строке вопроса, кнопки 48 dp: вопрос и варианты
    // видны без прокрутки при шрифте 1,3.
    final bool land = WorldLayout.isLandscape(context);
    return Column(
      key: const ValueKey<String>('job:choice'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!land) ...<Widget>[
          Semantics(
            header: true,
            child: Text(shiftChoiceHeading,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: Gap.xs),
        ],
        if (land)
          // Подсказка в той же строке, что вопрос: экономит строку высоты.
          Text.rich(
              TextSpan(children: <InlineSpan>[
                TextSpan(text: question.question),
                TextSpan(
                    text: ' $shiftChoicePrompt',
                    style: const TextStyle(color: WorldColors.textSoft)),
              ]),
              key: const ValueKey<String>('job:choice:question'),
              style: gameText(context))
        else ...<Widget>[
          Text(question.question,
              key: const ValueKey<String>('job:choice:question'),
              style: gameTextCompact),
          const SizedBox(height: Gap.xs),
          Text(shiftChoicePrompt,
              style: gameTextCompact.copyWith(color: WorldColors.textSoft)),
        ],
        const SizedBox(height: Gap.sm),
        for (final ShiftChoiceOption o in question.options) ...<Widget>[
          ShiftChoiceButton(
            key: ValueKey<String>('job:choice:${o.id}'),
            label: o.label,
            hint: hintOf(o),
            // Альбомная со словами: значки без чисел — в одну строку со
            // словами; числа читает TalkBack и показывает портрет.
            effects: land && hintOf(o) != null
                ? shiftChoiceSigns(offer, o)
                : shiftChoiceEffects(offer, o),
            inline: land,
            spoken: shiftChoiceSpoken(offer, o),
            minHeight: land ? 48 : TapSize.min,
            onPressed: () => onPick(o),
          ),
          const SizedBox(height: Gap.xs),
        ],
      ],
    );
  }
}

/// Кнопка варианта: подпись, под ней подсказка словами ([hint]) и
/// последствия значками ([effects]) — слова не заменяют точных чисел
/// (ревью). TalkBack читает подпись, подсказку и последствия
/// словами ([spoken]).
class ShiftChoiceButton extends StatelessWidget {
  const ShiftChoiceButton({
    super.key,
    required this.label,
    required this.effects,
    required this.spoken,
    required this.onPressed,
    this.hint,
    this.minHeight = TapSize.min,
    this.inline = false,
  });

  /// Подсказка и значки одной строкой (альбомная: высота дороже).
  final bool inline;

  /// Высота не меньше: 56 dp, в альбомной — 48 (минимум ТЗ).
  final double minHeight;

  final String label;
  final String? hint;
  final String effects;
  final String spoken;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final String? h = hint == null || hint!.trim().isEmpty ? null : hint;
    final String said = <String>[
      if (h != null) h.endsWith('.') ? h : '$h.',
      if (spoken.isNotEmpty) spoken,
    ].join(' ');
    final Widget labelText = Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: WorldColors.text,
      ),
    );
    // Альбомная: подсказка словами и значки в 14 sp (порог текста) —
    // иначе при шрифте 1,3 варианты уходят под край без прокрутки.
    final TextStyle subStyle = TextStyle(
      fontSize: inline ? 14 : 16,
      height: inline ? 1.15 : 1.25,
      color: WorldColors.textSoft,
    );
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(minHeight),
        alignment: Alignment.centerLeft,
        // Альбомная: поля тоньше — три варианта с подсказками без
        // прокрутки при шрифте 1,3 (высота 48 dp остаётся минимумом).
        padding: EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: inline ? 2 : Gap.xs,
        ),
        side: const BorderSide(color: WorldColors.needs, width: 2),
      ),
      onPressed: onPressed,
      child: Semantics(
        label: said.isEmpty ? label : '$label. $said',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (inline && h != null && effects.isNotEmpty)
              // Альбомная: значки — справа в строке подписи, подсказка —
              // строкой ниже: высота как у кнопки без значков.
              Row(
                children: <Widget>[
                  Flexible(child: labelText),
                  const SizedBox(width: Gap.sm),
                  PicText(effects,
                      key: const ValueKey<String>('job:choice:effects'),
                      style: subStyle),
                ],
              )
            else
              labelText,
            if (inline && h != null)
              Text(h,
                  key: const ValueKey<String>('job:choice:hint'),
                  style: subStyle)
            else ...<Widget>[
              if (h != null)
                Text(
                  h,
                  key: const ValueKey<String>('job:choice:hint'),
                  style: subStyle,
                ),
              if (effects.isNotEmpty)
                PicText(effects,
                    key: const ValueKey<String>('job:choice:effects'),
                    style: subStyle),
            ],
          ],
        ),
      ),
    );
  }
}
