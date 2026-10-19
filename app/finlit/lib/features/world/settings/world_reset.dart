import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/world/contract.dart';
import '../../../domain/world/world_game.dart';
import '../demo/world_checklist.dart';
import '../shop/shop_kit.dart';
import '../world_routes.dart';
import '../world_state.dart';

/// Раздел «Взрослым» есть как раздел (`economy.json → adult.section`,
/// DEN-27). Денис 18.10: «Взрослых мы вообще убираем пока как раздел» — в
/// сборке false: входа из комнаты нет, сброс и режим проверки — в
/// «Настройках». У FakeWorld (без файлов) — как раньше.
bool adultSectionOn(World w) => w is! WorldGame || w.config.adultSection;

/// «Начать игру заново» из «Настроек» (ТЗ §3.5.5): сначала тот же пример
/// на умножение, что у «Режима проверки» ([WorldRoutes.resetGate]), потом
/// [confirmWorldReset]. Назад или неверный ответ — ничего не стирается.
Future<void> gatedWorldReset(BuildContext context) async {
  // Маршруты из таблицы — MaterialPageRoute<dynamic>: `pushNamed<bool>`
  // упал бы на приведении типа, поэтому результат сверяется с true.
  final Object? passed =
      await Navigator.of(context).pushNamed(WorldRoutes.resetGate);
  if (passed != true || !context.mounted) return;
  await confirmWorldReset(context);
}

/// «Начать игру заново» с подтверждением: стереть всё и начать со
/// знакомства. Один диалог для «Взрослым» и «Настроек».
Future<void> confirmWorldReset(BuildContext context) async {
  final bool yes = await showDialog<bool>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: const Text('Начать игру заново?'),
          content: const SingleChildScrollView(
            child: Text(
              // Правила текстов 2 и 7: без «очков роста», до 140 знаков —
              // диалог теперь и в «Настройках», где его читает ребёнок.
              'Всё будет стёрто: недели, монеты, копилка, цель, покупки, '
              'питомцы, имя и облик Финни. Игра начнётся со знакомства. '
              'Отменить нельзя.',
              style: kitText,
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const ValueKey<String>('adult:confirm:no'),
              style: TextButton.styleFrom(minimumSize: kitButton),
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const ValueKey<String>('adult:confirm:yes'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(c).colorScheme.error,
                minimumSize: kitButton,
              ),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Стереть и начать'),
            ),
          ],
        ),
      ) ??
      false;
  if (!yes || !context.mounted) return;
  await context.read<WorldState>().reset();
  if (!context.mounted) return;
  WorldDemoSession.resetDone = true;
  await Navigator.of(context)
      .pushNamedAndRemoveUntil(WorldRoutes.onboarding, (_) => false);
}
