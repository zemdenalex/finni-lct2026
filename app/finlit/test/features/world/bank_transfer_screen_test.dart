import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/domain/world/world_entry.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:finlit/features/world/bank/transfer_screen.dart';
import 'package:finlit/features/world/history/history_screen.dart';
import 'package:finlit/features/world/piggy/piggy_screen.dart';
import 'package:finlit/features/world/world_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/bank_world.dart';
import '../../support/world_harness.dart';

/// Банк: карточка «Что такое банк?» и «Перевод монет» (ТЗ Насти 18.10,
/// экраны 10–11; флаг `bank.transfer`).
///
/// Защищает: при флаге off копилка и вход в банк — как в rc-7d, без новых
/// элементов; при on — карточка один раз при первом входе в «Банк», с неё и
/// из копилки открывается перевод; на экране ТЗ-тексты, до/после обеих
/// частей и «Всего монет»; двойное касание даёт один перевод; ошибки ТЗ;
/// 360×640 и 640×360 при шрифте 1,3 без переполнения и с целями ≥ 48 dp;
/// строка перевода в истории недели. Уронит: кнопка без флага, повторная
/// карточка, второе списание, экран, не влезающий в телефон.
Finder _k(String k) => find.byKey(ValueKey<String>(k));

/// Экран-вход: кнопка «в банк» открывает копилку так, как город открывает
/// здание «Банк» (`cityBuildingRoutes`, аргумент — id здания).
class _City extends StatelessWidget {
  const _City();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey<String>('test:bank'),
            onPressed: () => Navigator.of(context)
                .pushNamed(WorldRoutes.piggy, arguments: 'piggy-bank'),
            child: const Text('в банк'),
          ),
        ),
      );
}

Future<void> _enterBank(WidgetTester tester) async {
  await tester.tap(_k('test:bank'));
  await tester.pumpAndSettle();
}

/// Цель касания не меньше 48 × 48 и целиком на экране.
void _target(WidgetTester tester, String key) {
  final Rect r = tester.getRect(_k(key));
  final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(r.width, greaterThanOrEqualTo(48), reason: '$key: ширина $r');
  expect(r.height, greaterThanOrEqualTo(48), reason: '$key: высота $r');
  expect(r.left, greaterThanOrEqualTo(0), reason: '$key: за левым краем');
  expect(r.right, lessThanOrEqualTo(screen.width + 0.5),
      reason: '$key: за правым краем');
}

/// Прокрутить к [key] и коснуться.
Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_k(key));
  await tester.pump();
  await tester.tap(_k(key));
}

int _transfers(WorldGame w) => w.journal
    .where((WorldEntry e) => e.isKind(WorldLedgerKind.envelopeTransfer))
    .length;

void main() {
  group('флаг выключен (сборка)', () {
    testWidgets('копилка без кнопки перевода, вход в банк без карточки',
        (WidgetTester tester) async {
      final WorldGame w = bankWorld(on: false);
      await pumpWorldScreen(tester, const _City(), world: w);
      await _enterBank(tester);
      expect(find.byType(PiggyScreen), findsOneWidget);
      expect(_k('bank:intro'), findsNothing);
      expect(_k('piggy:transfer'), findsNothing);
      expect(find.text(BankTexts.title), findsNothing);
      expect(find.text(BankTexts.intro), findsNothing);
      expect(w.seen(bankIntroSeen), isFalse);
      // Прежние панели копилки на месте. Нижнее меню (стиль Алины) забрало
      // 60 dp: «Снять» — ниже первого экрана, ленивый список строит её,
      // когда до неё докрутили (как в shop_piggy_test, 0861aaa5). Кнопка
      // перевода стояла бы над «Отложить» — та построена, значит проверка
      // «перевода нет» выше не пустая.
      expect(_k('piggy:deposit'), findsOneWidget);
      await tester.scrollUntilVisible(_k('piggy:withdraw'), 200,
          scrollable: find
              .descendant(
                  of: find.byType(PiggyScreen),
                  matching: find.byWidgetPredicate((Widget s) =>
                      s is Scrollable && s.axisDirection == AxisDirection.down))
              .first);
      expect(_k('piggy:withdraw'), findsOneWidget);
      expect(_k('piggy:transfer'), findsNothing);
    });
  });

  group('флаг включён', () {
    testWidgets(
        'карточка «Что такое банк?» — один раз, текст ТЗ, ведёт в '
        'перевод', (WidgetTester tester) async {
      final WorldGame w = bankWorld();
      await pumpWorldScreen(tester, const _City(), world: w);
      await _enterBank(tester);
      expect(_k('bank:intro'), findsOneWidget);
      expect(find.text('Что такое банк?'), findsOneWidget);
      expect(
          find.text('В банке люди хранят деньги, переводят их и копят на '
              'большие покупки. А иногда берут деньги в долг. Пока мы '
              'научимся самому простому — переводить монеты из одной части в другую!'),
          findsOneWidget);
      expect(find.text('Попробовать перевод'), findsOneWidget);
      expect(w.seen(bankIntroSeen), isTrue, reason: 'отмечено сразу');
      await tester.tap(_k('bank:intro:go'));
      await tester.pumpAndSettle();
      expect(find.byType(TransferScreen), findsOneWidget);
      // Назад до города и снова в банк — карточки больше нет.
      await tester.tap(_k('transfer:back'));
      await tester.pumpAndSettle();
      await tester.tap(_k('piggy:back'));
      await tester.pumpAndSettle();
      await _enterBank(tester);
      expect(find.byType(PiggyScreen), findsOneWidget);
      expect(_k('bank:intro'), findsNothing);
    });

    testWidgets('закрыл карточку без перевода — второй раз не показывается',
        (WidgetTester tester) async {
      final WorldGame w = bankWorld();
      await pumpWorldScreen(tester, const _City(), world: w);
      await _enterBank(tester);
      expect(_k('bank:intro'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4)); // мимо карточки
      await tester.pumpAndSettle();
      expect(_k('bank:intro'), findsNothing);
      expect(find.byType(TransferScreen), findsNothing);
      // «Показано» в профиле: переживает перезапуск.
      final OnboardingProgress back =
          OnboardingProgress.fromJson(w.onboarding.toJson());
      expect(back.seen, contains(bankIntroSeen));
      await tester.tap(_k('piggy:back'));
      await tester.pumpAndSettle();
      await _enterBank(tester);
      expect(_k('bank:intro'), findsNothing);
    });

    testWidgets('копилка из комнаты — без карточки, кнопка ведёт в перевод',
        (WidgetTester tester) async {
      final WorldGame w = bankWorld();
      await pumpWorldScreen(tester, const PiggyScreen(), world: w);
      await tester.pumpAndSettle();
      expect(_k('bank:intro'), findsNothing);
      await tester.ensureVisible(_k('piggy:transfer'));
      await tester.tap(_k('piggy:transfer'));
      await tester.pumpAndSettle();
      expect(find.byType(TransferScreen), findsOneWidget);
    });

    testWidgets(
        'перевод Хочу → Копилка 30: до/после, всего, итог ТЗ, '
        'двойное касание — один перевод', (WidgetTester tester) async {
      final WorldGame w = bankWorld();
      final ResourceSnapshot s = w.snapshot;
      await pumpWorldScreen(tester, const TransferScreen(), world: w);
      expect(find.text('Перевод монет'), findsOneWidget);
      expect(find.text('Из одной части в другую'), findsOneWidget);
      expect(_k('transfer:hello'), findsOneWidget);
      for (int i = 0; i < 3; i++) {
        await _tap(tester, 'transfer:plus');
        await tester.pump();
      }
      expect(find.text('Хочу: ${s.want} → ${s.want - 30}'), findsOneWidget);
      expect(find.text('Копилка: ${s.goal} → ${s.goal + 30}'), findsOneWidget);
      final int total = s.need + s.want + s.goal;
      expect(find.text('Всего монет: $total'), findsOneWidget);
      expect(find.text('Перевести 30 монет'), findsOneWidget);
      await tester.ensureVisible(_k('transfer:go'));
      await tester.pump();
      // Подтверждение дважды до перерисовки: обработчик кнопки зовётся два
      // раза подряд (касания в тесте между кадрами до кнопки не доходят).
      final VoidCallback confirm =
          tester.widget<FilledButton>(_k('transfer:go')).onPressed!;
      confirm();
      confirm();
      await tester.pumpAndSettle();
      expect(_transfers(w), 1);
      expect(w.snapshot.want, s.want - 30);
      expect(w.snapshot.goal, s.goal + 30);
      expect(
          find.text('Готово! Мы перевели 30 монет из части «Хочу» в '
              '«Копилка».'),
          findsOneWidget);
      expect(
          find.text('Видишь? Мы ничего не потратили! Просто переложили '
              'монеты в другую часть.'),
          findsOneWidget);
      await tester.tap(_k('transfer:done:ok'));
      await tester.pumpAndSettle();
      expect(_k('transfer:done'), findsNothing);
      // Второе касание не дошло до мира: ни отказа, ни ошибки на экране.
      expect(_k('transfer:error'), findsNothing);
      expect(w.journal.last.isKind(WorldLedgerKind.envelopeTransfer), isTrue);
      expect(find.text('Всего монет: $total'), findsOneWidget);
      expect(_k('transfer:hello'), findsNothing,
          reason: 'обучение после первого перевода не повторяется');
    });

    testWidgets('та же часть и больше остатка — ошибки ТЗ, кнопка погашена',
        (WidgetTester tester) async {
      final WorldGame w = bankWorld();
      final int want = w.snapshot.want;
      await pumpWorldScreen(tester, const TransferScreen(), world: w);
      await _tap(tester, 'transfer:to:want');
      await tester.pump();
      expect(find.text('Выбери другую часть для перевода.'), findsOneWidget);
      await _tap(tester, 'transfer:to:goal');
      await tester.pump();
      expect(_k('transfer:error'), findsNothing);
      // «+» до остатка «Хочу» и ещё раз — упёрся.
      for (int i = 0; i <= want ~/ TransferScreen.step; i++) {
        await _tap(tester, 'transfer:plus');
        await tester.pump();
      }
      expect(
          find.text('В этой части не хватает монет. Выбери сумму '
              'поменьше.'),
          findsOneWidget);
      // Копилка больше: взяли из неё, потом источником снова «Хочу» —
      // сумма та же, остатка мало.
      await _tap(tester, 'transfer:to:need');
      await _tap(tester, 'transfer:from:goal');
      await tester.pump();
      for (int i = 0; i < 3; i++) {
        await _tap(tester, 'transfer:plus');
        await tester.pump();
      }
      expect(_k('transfer:error'), findsNothing);
      await _tap(tester, 'transfer:from:want');
      await tester.pump();
      expect(
          find.text('В этой части не хватает монет. Выбери сумму '
              'поменьше.'),
          findsOneWidget);
      final FilledButton go = tester.widget<FilledButton>(_k('transfer:go'));
      expect(go.onPressed, isNull);
      expect(_transfers(w), 0);
    });

    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      testWidgets('${o.key} при шрифте 1,3: влезает, цели ≥ 48 dp',
          (WidgetTester tester) async {
        final WorldGame w = bankWorld();
        await pumpWorldScreen(tester, const _City(),
            world: w, size: o.value, textScale: 1.3);
        await _enterBank(tester);
        expect(tester.takeException(), isNull);
        _target(tester, 'bank:intro:go');
        await tester.tap(_k('bank:intro:go'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final String k in <String>[
          for (final MoneyPart p in MoneyPart.values) ...<String>[
            'transfer:from:${p.name}',
            'transfer:to:${p.name}',
          ],
          'transfer:minus',
          'transfer:plus',
          'transfer:go',
        ]) {
          await tester.ensureVisible(_k(k));
          await tester.pump();
          _target(tester, k);
        }
        await tester.ensureVisible(_k('transfer:plus'));
        await _tap(tester, 'transfer:plus');
        await tester.pump();
        await tester.ensureVisible(_k('transfer:go'));
        await tester.pump();
        await tester.tap(_k('transfer:go'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _target(tester, 'transfer:done:ok');
      });
    }

    testWidgets('неделя ещё не началась — причина сразу, кнопка погашена',
        (WidgetTester tester) async {
      final WorldGame w = WorldGame(
          config: bankConfig(on: true),
          onboarding:
              const OnboardingProgress(step: OnboardingProgress.stepDone));
      ok(w.startWeek());
      await pumpWorldScreen(tester, const TransferScreen(), world: w);
      await _tap(tester, 'transfer:plus');
      await tester.pump();
      expect(find.text(w.canDo(WorldAction.transfer)!.text), findsOneWidget);
      expect(tester.widget<FilledButton>(_k('transfer:go')).onPressed, isNull);
    });

    testWidgets('история недели: строка перевода; без переводов её нет',
        (WidgetTester tester) async {
      final WorldGame w = bankWorld();
      await pumpWorldScreen(tester, const HistoryScreen(), world: w);
      expect(_k('history:w1:transfer:0'), findsNothing);
      // Два перевода за неделю — две строки (ключи не совпадают).
      ok(w.transfer(from: MoneyPart.want, to: MoneyPart.goal, amount: 30));
      ok(w.transfer(from: MoneyPart.want, to: MoneyPart.goal, amount: 10));
      await pumpWorldScreen(tester, const HistoryScreen(), world: w);
      expect(tester.takeException(), isNull);
      expect(find.text('Перевод: Хочу → Копилка, 30 монет'), findsOneWidget);
      expect(find.text('Перевод: Хочу → Копилка, 10 монет'), findsOneWidget);
    });
  });
}
