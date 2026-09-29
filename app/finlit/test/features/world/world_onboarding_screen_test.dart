import 'dart:convert';
import 'dart:io';

import 'package:finlit/app_state.dart';
import 'package:finlit/data/onboarding_store.dart';
import 'package:finlit/data/storage.dart';
import 'package:finlit/data/world_save.dart';
import 'package:finlit/domain/models/profile.dart';
import 'package:finlit/domain/world/contract.dart';
import 'package:finlit/features/world/onboarding/onboarding_script.dart';
import 'package:finlit/features/world/onboarding/world_onboarding_screen.dart';
import 'package:finlit/core/widgets.dart';
import 'package:finlit/features/world/pic_text.dart';
import 'package:finlit/features/world/world_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/world_harness.dart';

final Finder _next = find.byKey(const ValueKey<String>('onboarding-next'));
final Finder _skip = find.byKey(const ValueKey<String>('onboarding:skip'));
final Finder _planPlus = find.byKey(const ValueKey<String>('plus:need'));

Future<void> _tapNext(WidgetTester tester) async {
  await tester.ensureVisible(_next);
  await tester.tap(_next);
  await _settle(tester);
}

/// Финни дышит (idle) без конца, поэтому не pumpAndSettle, а время
/// перехода шага с запасом.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Регистрация: ник → облик и имя → «Поехали» (неделя 1 началась).
Future<void> _register(WidgetTester tester,
    {String nick = 'Звёздочка', bool customise = true}) async {
  expect(tester.widget<FilledButton>(_next).onPressed, isNull,
      reason: 'без ника дальше нельзя');
  await tester.enterText(
      find.byKey(const ValueKey<String>('onboarding-nick')), nick);
  await tester.pump();
  await _tapNext(tester); // ник → облик
  if (customise) {
    final Finder girl = find.byKey(const ValueKey<String>('gender:girl'));
    await tester.ensureVisible(girl);
    await tester.tap(girl);
    await tester.pump();
    final Finder look = find.byKey(const ValueKey<String>('look:finni-a2:3'));
    await tester.ensureVisible(look);
    await tester.tap(look);
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey<String>('onboarding-finni-name')), 'Бублик');
    await tester.pump();
  }
  await _tapNext(tester); // облик → сценки
}

/// «Дальше» по репликам, пока не откроется сценка плана.
Future<void> _talkToPlan(WidgetTester tester) async {
  for (int i = 0; i < 40 && _planPlus.evaluate().isEmpty; i++) {
    await _tapNext(tester);
  }
  expect(_planPlus, findsOneWidget, reason: 'сценки дошли до плана');
}

/// Жмёт «+» у НУЖНО, пока есть что раскладывать (конверты с нуля).
Future<void> _fillNeeds(WidgetTester tester) async {
  await tester.ensureVisible(_planPlus);
  for (int i = 0;
      i < 200 &&
          find.byKey(const ValueKey<String>('plan:full')).evaluate().isEmpty;
      i++) {
    await tester.tap(_planPlus);
    await tester.pump();
  }
  await _settle(tester);
}

/// Проходит регистрацию и все сценки; возвращает состояние мира.
Future<WorldState> _walk(WidgetTester tester, WorldKind kind,
    {double textScale = 1, Size size = portrait}) async {
  final WorldState ws = await pumpWorldScreen(
      tester, const WorldOnboardingScreen(),
      world: kind.make(), textScale: textScale, size: size);
  await _register(tester);
  expect(ws.phase, WeekPhase.planning);
  await _talkToPlan(tester);
  await _fillNeeds(tester); // конверты с нуля: всё — в НУЖНО
  await _tapNext(tester);
  expect(ws.phase, WeekPhase.living);
  expect(tester.widget<FilledButton>(_next).onPressed, isNull,
      reason: 'цель по умолчанию не выбирается');
  final Finder goal = find.byKey(const ValueKey<String>('goal:pet_fish'));
  await tester.ensureVisible(goal);
  await tester.tap(goal);
  await _settle(tester);
  for (int i = 0;
      i < 10 && find.byType(WorldOnboardingScreen).evaluate().isNotEmpty;
      i++) {
    await _tapNext(tester); // прощание → комната
  }
  return ws;
}

/// Текст на экране целиком (в том числе внутри [Text.rich]).
Finder _say(String text) => find.byWidgetPredicate(
    (Widget w) => w is Text && (w.data ?? w.textSpan?.toPlainText()) == text);

/// Ловит: онбординг не доводит мир до недели 1 с планом, теряет выбор
/// ребёнка или не помещается на маленьком экране с крупным шрифтом.
void main() {
  forEachWorld((WorldKind kind) {
    testWidgets(
        'ник, облик, сценки: неделя 1 идёт, счета в НУЖНО, профиль сохранён',
        (WidgetTester tester) async {
      final World fresh = kind.make();
      ok(fresh.startWeek());
      final int pool = fresh.snapshot.unallocated;
      final int bill = fresh.snapshot.weeklyBill;
      final WorldState ws = await _walk(tester, kind);

      expect(ws.phase, WeekPhase.living);
      expect(ws.snapshot.weekNo, 1);
      expect(ws.snapshot.need, bill < pool ? bill : pool);
      expect(ws.snapshot.want, 0);
      expect(ws.snapshot.unallocated, 0);
      expect(ws.snapshot.activeGoalId, 'pet_fish');
      final OnboardingProgress p = ws.world.onboarding;
      expect(p.nickname, 'Звёздочка');
      expect(p.finniName, 'Бублик');
      expect(p.finniSpecies, 'finni-a2');
      expect(p.finniLook, 3);
      expect(p.finniGender, FinniGender.girl);
      expect(p.done, isTrue);
      expect(find.byType(WorldOnboardingScreen), findsNothing,
          reason: 'в конце — переход в комнату');
    });

    // Ловит: регистрация снова стала опросником (Денис, 29.09: «только свой
    // ник и выбор персонажа»). На старом коде первым экраном была
    // «Финни переезжает», а ник — третьим шагом из шести.
    testWidgets(
        'регистрация — только ник, облик и имя; сразу за ней — сценка '
        'в комнате', (WidgetTester tester) async {
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: kind.make());
      expect(
          find.byKey(const ValueKey<String>('onboarding-nick')), findsOneWidget,
          reason: 'первый экран — ник');
      expect(find.text('Шаг 1 из 2'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey<String>('onboarding-nick')), 'Кот');
      await tester.pump();
      await _tapNext(tester);
      expect(find.text('Шаг 2 из 2'), findsOneWidget);
      expect(
          find.byWidgetPredicate((Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('look:')),
          findsAtLeastNWidgets(9),
          reason: 'ТЗ 2.5.2.1: не меньше девяти обликов');
      final TextField name = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('onboarding-finni-name')));
      expect(name.controller!.text, OnboardingProgress.defaultFinniName);
      await _tapNext(tester);
      final String first = fillLine(contentScript.scenes.first.lines.first,
          <String, String>{'nick': 'Кот', 'name': 'Финни'});
      expect(_say(first), findsOneWidget,
          reason: 'после облика Финни здоровается в комнате');
      expect(find.byKey(const ValueKey<String>('onboarding:stage')),
          findsOneWidget);
    });

    // Ловит: реплики снова зашиты в код (ТЗ 3.2.3) — сценка обязана
    // показать то, что лежит в файле, с подстановками мира.
    testWidgets('реплики сценок — из onboarding.json, с ником и числами мира',
        (WidgetTester tester) async {
      final OnboardingScript script = _withScenes(<Object?>[
        <String, Object?>{
          'id': 'a',
          'kind': 'talk',
          'focus': 'piggy',
          'lines': <String>['Проверка {nick}: счета {bill}'],
          'help': 'помощь {name}',
        },
        <String, Object?>{
          'id': 'p',
          'kind': 'plan',
          'focus': null,
          'lines': <String>['План {pool}'],
          'help': 'п',
        },
        <String, Object?>{
          'id': 'g',
          'kind': 'goal',
          'focus': null,
          'lines': <String>['Цель'],
          'help': 'ц',
        },
      ], skip: 'Мимо');
      final WorldState ws = await pumpWorldScreen(
          tester, const WorldOnboardingScreen(),
          world: kind.make(), script: script);
      await _register(tester, nick: 'Кот', customise: false);
      expect(_say('Проверка Кот: счета ${ws.snapshot.weeklyBill}'),
          findsOneWidget);
      expect(find.text('Мимо'), findsOneWidget);
      await _tapNext(tester);
      expect(_say('План ${ws.snapshot.unallocated}'), findsOneWidget);
    });

    // Ловит: «Пропустить» проглатывает объяснение трёх решений (ТЗ 2.5.1.1)
    // или сами решения — план и цель ребёнок делает всегда сам.
    testWidgets(
        '«Пропустить» ведёт к плану: три конверта со смыслом видны, '
        'план и цель не пропускаются', (WidgetTester tester) async {
      final WorldState ws = await pumpWorldScreen(
          tester, const WorldOnboardingScreen(),
          world: kind.make());
      await _register(tester, customise: false);
      expect(_skip, findsOneWidget);
      await tester.tap(_skip);
      await _settle(tester);
      expect(_planPlus, findsOneWidget);
      expect(ws.phase, WeekPhase.planning, reason: 'план не сделан за ребёнка');
      for (final String meaning in <String>[
        contentScript.envelopesShort.need,
        contentScript.envelopesShort.want,
        contentScript.envelopesShort.goal,
      ]) {
        expect(find.textContaining(meaning), findsOneWidget, reason: meaning);
      }
      expect(_skip, findsNothing, reason: 'план не пропускается');
      await _tapNext(tester);
      expect(_skip, findsNothing, reason: 'цель не пропускается');
      expect(tester.widget<FilledButton>(_next).onPressed, isNull);
    });

    // ТЗ 2.5.1.3. Ловит: «?» в сценке показывает общую подсказку, а не про
    // то, что Финни сейчас объясняет.
    testWidgets('«?» в сценке — подсказка этой сценки',
        (WidgetTester tester) async {
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: kind.make());
      await _register(tester, nick: 'Кот', customise: false);
      await tester.tap(find.byKey(const ValueKey<String>('onboarding:help')));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      final String help = fillLine(contentScript.scenes.first.help,
          <String, String>{'name': OnboardingProgress.defaultFinniName});
      expect(
          find.byWidgetPredicate((Widget w) => w is PicText && w.text == help),
          findsOneWidget);
    });

    testWidgets(
        'назад из сценок в облик и снова вперёд не начисляет карманные дважды',
        (WidgetTester tester) async {
      final WorldState ws = await pumpWorldScreen(
          tester, const WorldOnboardingScreen(),
          world: kind.make());
      await _register(tester, nick: 'Кот', customise: false);
      final int pool = ws.snapshot.unallocated;
      expect(pool, greaterThan(0));
      await tester.tap(find.byTooltip('Назад'));
      await _settle(tester);
      expect(find.byKey(const ValueKey<String>('onboarding-finni-name')),
          findsOneWidget,
          reason: 'из первой сценки назад — облик и имя');
      await _tapNext(tester); // снова сценки
      expect(ws.snapshot.weekNo, 1);
      expect(ws.snapshot.unallocated, pool);
    });

    // Переполнение Flex бросает исключение, и тест упадёт на нём.
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      for (final double scale in <double>[1, 1.3]) {
        testWidgets('все шаги проходятся · ${o.key} · шрифт $scale',
            (WidgetTester tester) async {
          final WorldState ws =
              await _walk(tester, kind, textScale: scale, size: o.value);
          expect(ws.phase, WeekPhase.living);
          expect(ws.world.onboarding.finniLook, 3);
          expect(ws.world.onboarding.finniGender, FinniGender.girl);
          expect(tester.takeException(), isNull);
        });
      }
    }

    // Ловит: после перезапуска онбординг начинается с нуля и ник потерян —
    // экран должен продолжить с сохранённого шага (A14).
    testWidgets('сохранённый шаг облика: экран продолжает с него, ник на месте',
        (WidgetTester tester) async {
      final World world = kind.make(
        onboarding: const OnboardingProgress(
            step: OnboardingProgress.stepFinni, nickname: 'Звёздочка'),
      );
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: world);
      await _settle(tester);
      expect(find.text('Шаг 2 из 2'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('gender:boy')), findsOneWidget);

      await tester.tap(find.byTooltip('Назад'));
      await _settle(tester);
      final TextField nick = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('onboarding-nick')));
      expect(nick.controller!.text, 'Звёздочка');
    });

    // Ловит: шаги не доходят до хранилища — после перезапуска всё заново.
    testWidgets('ник, облик и имя уходят в хук сохранения',
        (WidgetTester tester) async {
      final List<Map<String, Object?>> saved = <Map<String, Object?>>[];
      final World world = kind.make(
          saveOnboarding: (Map<String, Object?> json) async => saved.add(json));
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: world);
      await tester.enterText(
          find.byKey(const ValueKey<String>('onboarding-nick')), 'Кот');
      await tester.pump();
      await _tapNext(tester);
      expect(saved.last['nickname'], 'Кот');
      expect(saved.last['step'], OnboardingProgress.stepFinni);

      await tester.tap(find.byKey(const ValueKey<String>('gender:boy')));
      await tester.pump();
      expect(saved.last['finniGender'], 'boy');

      await tester.enterText(
          find.byKey(const ValueKey<String>('onboarding-finni-name')),
          'Бублик');
      await _tapNext(tester);
      expect(saved.last['finniName'], 'Бублик');
      expect(saved.last['step'], OnboardingProgress.stepMoney);
    });

    // Ловит: цели без цены или из списка экранов, а не из каталога мира;
    // план подтверждён — экран продолжает со сценки цели, а не с начала.
    testWidgets('план есть: сценка цели, цели из каталога мира с ценой',
        (WidgetTester tester) async {
      final World world = kind.make();
      ok(world.startWeek());
      ok(world.plan(needs: world.snapshot.unallocated, wants: 0, goal: 0));
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: world);
      await _settle(tester);
      expect(_planPlus, findsNothing);
      final WorldCatalogItem fish = world.catalogItem('pet_fish')!;
      expect(
          find.byWidgetPredicate((Widget w) =>
              w is PicText && w.text == '${fish.title} · ${fish.price} 💰'),
          findsOneWidget);
    });

    // Ловит: план и цель не доходят до хранилища — после перезапуска
    // знакомство снова с начала, а конверты недели уже разложены.
    testWidgets('план и цель тоже сохраняются: шаг цели, потом «готово»',
        (WidgetTester tester) async {
      final List<Map<String, Object?>> saved = <Map<String, Object?>>[];
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: kind.make(
              saveOnboarding: (Map<String, Object?> json) async =>
                  saved.add(json)));
      await _register(tester, customise: false);
      await tester.tap(_skip);
      await _settle(tester);
      await _tapNext(tester); // план
      expect(saved.last['step'], OnboardingProgress.stepGoal);
      final Finder goal = find.byKey(const ValueKey<String>('goal:pet_fish'));
      await tester.ensureVisible(goal);
      await tester.tap(goal);
      await _settle(tester);
      for (int i = 0;
          i < 10 && find.byType(WorldOnboardingScreen).evaluate().isNotEmpty;
          i++) {
        await _tapNext(tester);
      }
      expect(saved.last['step'], OnboardingProgress.stepDone);
    });

    // Ловит: ребёнок выбрал «Девочка», а Финни говорит о себе «вырос»,
    // «снял» (ревью 29.09) — реплики с родом берутся из lines_girl.
    testWidgets('Девочка: Финни говорит о себе в женском роде',
        (WidgetTester tester) async {
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: kind.make());
      await _register(tester); // «Девочка», имя «Бублик»
      final OnboardingScene hello = contentScript.scenes.first;
      expect(hello.linesGirl, isNotNull);
      final Map<String, String> v = <String, String>{
        'nick': 'Звёздочка',
        'name': 'Бублик'
      };
      expect(_say(fillLine(hello.linesFor(FinniGender.girl)[0], v)),
          findsOneWidget);
      expect(_say(fillLine(hello.lines[0], v)), findsNothing);
      expect(hello.linesFor(FinniGender.girl)[0], isNot(hello.lines[0]));
      expect(find.byKey(const ValueKey<String>('room:name')), findsNothing,
          reason: 'имя — над репликой, табличка в углу не ложится на дверь');
    });

    // Ловит: перезапуск посреди сценок снова спрашивает ник или второй раз
    // начисляет карманные — продолжаем сценками, неделя та же.
    testWidgets(
        'перезапуск посреди сценок: снова сценки, ник и карманные '
        'не повторяются', (WidgetTester tester) async {
      final World world = kind.make(
          onboarding: const OnboardingProgress(
              step: OnboardingProgress.stepMoney, nickname: 'Кот'));
      ok(world.startWeek());
      final int pool = world.snapshot.unallocated;
      final WorldState ws = await pumpWorldScreen(
          tester, const WorldOnboardingScreen(),
          world: world);
      await _settle(tester);
      expect(
          find.byKey(const ValueKey<String>('onboarding-nick')), findsNothing);
      expect(
          _say(fillLine(contentScript.scenes.first.lines.first,
              <String, String>{'nick': 'Кот', 'name': 'Финни'})),
          findsOneWidget);
      expect(ws.snapshot.weekNo, 1);
      expect(ws.snapshot.unallocated, pool);
    });

    // Ловит: поле имени уехало под плитки обликов — жюри на шаге 3
    // Приложения А его не видит (ТЗ 2.5.2.2).
    for (final MapEntry<String, Size> o in bothOrientations.entries) {
      testWidgets('облик и имя: поле имени видно без прокрутки · ${o.key}',
          (WidgetTester tester) async {
        await pumpWorldScreen(tester, const WorldOnboardingScreen(),
            size: o.value,
            world: kind.make(
                onboarding: const OnboardingProgress(
                    step: OnboardingProgress.stepFinni, nickname: 'Кот')));
        await _settle(tester);
        final Rect field = tester.getRect(
            find.byKey(const ValueKey<String>('onboarding-finni-name')));
        expect(field.top, greaterThanOrEqualTo(0));
        expect(field.bottom, lessThanOrEqualTo(o.value.height));
        // Над кнопкой в портрете; в альбомной кнопка в той же колонке ниже.
        expect(field.bottom, lessThanOrEqualTo(tester.getRect(_next).top));
      });

      // Ловит: из трёх конвертов плана виден один, остальные под прокруткой
      // (ревью 29.09) — все три «+» на экране над «Готово».
      testWidgets('план: все три конверта видны без прокрутки · ${o.key}',
          (WidgetTester tester) async {
        await pumpWorldScreen(tester, const WorldOnboardingScreen(),
            size: o.value, world: kind.make());
        await _register(tester, customise: false);
        await tester.tap(_skip);
        await _settle(tester);
        final double bottom = tester.getRect(_next).top;
        for (final String id in <String>['need', 'want', 'goal']) {
          for (final String b in <String>['minus', 'plus']) {
            final Rect r =
                tester.getRect(find.byKey(ValueKey<String>('$b:$id')));
            expect(r.top, greaterThanOrEqualTo(0), reason: '$b:$id');
            expect(r.bottom, lessThanOrEqualTo(bottom), reason: '$b:$id');
            expect(r.height, greaterThanOrEqualTo(48), reason: '$b:$id');
          }
        }
      });
    }

    // Ловит: TalkBack молчит после «Дальше» — новая реплика должна
    // прозвучать сама.
    testWidgets('реплика — живая область для TalkBack',
        (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: kind.make());
      await _register(tester, nick: 'Кот', customise: false);
      final Finder line = find.byWidgetPredicate((Widget w) =>
          w is Semantics &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('onboarding:line:'));
      expect(line, findsOneWidget);
      expect(tester.getSemantics(line), isSemantics(isLiveRegion: true));
      h.dispose();
    });

    // Ловит: в альбомной шаг снова стал узким портретным столбцом — Финни
    // и управление шага должны стоять рядом, «Дальше» — в правой панели.
    testWidgets('альбомная: Финни слева, шаг и «Дальше» справа',
        (WidgetTester tester) async {
      await tester.runAsync(() async {
        await pumpWorldScreen(tester, const WorldOnboardingScreen(),
            world: kind.make(), size: landscape);
        for (int i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      await _settle(tester);
      final Rect stage = tester
          .getRect(find.byKey(const ValueKey<String>('onboarding:stage')));
      final Rect next = tester.getRect(_next);
      expect(stage.right, lessThanOrEqualTo(next.left));
      expect(stage.height, greaterThan(landscape.height * 0.6));
      expect(next.bottom, lessThanOrEqualTo(landscape.height));
      expect(next.height, greaterThanOrEqualTo(48));
      expect(find.byKey(const ValueKey<String>('onboarding:help')),
          findsOneWidget);
      expect(find.byType(AppBar), findsNothing, reason: 'шапка — одна строка');
    });
  });

  /// Сценки открыты сразу (арт комнаты читается под runAsync); «Дальше»
  /// до сценки, где Финни подходит к [object]. Возвращает, где Финни стоял
  /// до неё.
  Future<({Finder spot, double homeX})> toScene(
      WidgetTester tester, String object,
      {bool animations = true}) async {
    // rootBundle кеширует Future из зоны прошлого теста — арт бы не пришёл.
    rootBundle.clear();
    final World world = contentWorld(
        onboarding: const OnboardingProgress(
            step: OnboardingProgress.stepMoney, nickname: 'Кот'));
    ok(world.startWeek());
    await tester.runAsync(() async {
      AppState? app;
      if (!animations) {
        app = AppState(MemoryStorage());
        await app.boot();
        await app.updateProfile(app.game.profile
            .copyWith(settings: const GameSettings(animationsOn: false)));
      }
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: world, app: app);
      for (int i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await _settle(tester);
    final Finder spot = find.byKey(const ValueKey<String>('room:finni:spot'));
    expect(spot, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('room:piggy')), findsOneWidget,
        reason: 'арт комнаты загрузился: копилка на месте');
    final double homeX = tester.getRect(spot).center.dx;
    expect(contentScript.scenes.any((OnboardingScene s) => s.focus == object),
        isTrue,
        reason: 'в onboarding.json есть сценка у $object');
    final Finder focus = find.byKey(ValueKey<String>('room:focus:$object'));
    for (int i = 0; i < 30 && focus.evaluate().isEmpty; i++) {
      await tester.tap(_next);
      await tester.pump(); // без хода часов: только перестройка
    }
    expect(focus, findsOneWidget);
    return (spot: spot, homeX: homeX);
  }

  /// Ключ реплики на экране (`onboarding:line:<сцена>:<номер>`).
  String lineKey() => find
      .byWidgetPredicate((Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('onboarding:line:'))
      .evaluate()
      .single
      .widget
      .key
      .toString();

  // Ловит: Финни стоит на месте, пока рассказывает про копилку, холодильник
  // и дверь, — первые шаги по комнате он делает сам (Денис, 941), а предмет
  // подсвечен и нажимается (для TalkBack — кнопка с его названием).
  for (final (String object, String key) in <(String, String)>[
    ('piggy', 'room:piggy'),
    ('fridge', 'room:fridge'),
    ('door', 'room:door'),
  ]) {
    testWidgets(
        'сценка «$object»: Финни сам подходит, предмет подсвечен '
        'и нажимается', (WidgetTester tester) async {
      final (:Finder spot, homeX: _) = await toScene(tester, object);
      await tester.pump(const Duration(seconds: 3)); // дошёл
      // Стоит рядом: ноги Финни (точка без размера, пока спрайт не
      // прочитан) — у края предмета, не дальше 64 dp (полшага Финни).
      final double x = tester.getRect(spot).center.dx;
      final Rect thing = tester.getRect(find.byKey(ValueKey<String>(key)));
      expect(
          (x - x.clamp(thing.left, thing.right)).abs(), lessThanOrEqualTo(64),
          reason: 'Финни у $object: x $x, предмет $thing');
      final String line = lineKey();
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await _settle(tester);
      expect(lineKey(), isNot(line), reason: 'касание $object — дальше');
    });
  }

  // ТЗ 3.6.7. Ловит: с выключенными «Анимациями» Финни всё равно идёт по
  // комнате — должен сразу стоять у двери (дверь далеко от его места).
  testWidgets('«Анимации» выкл.: Финни у двери сразу, без хода',
      (WidgetTester tester) async {
    final (:Finder spot, :double homeX) =
        await toScene(tester, 'door', animations: false);
    final double x = tester.getRect(spot).center.dx;
    expect(x, isNot(closeTo(homeX, 8)), reason: 'в том же кадре, без хода');
    final Rect door =
        tester.getRect(find.byKey(const ValueKey<String>('room:door')));
    expect((x - x.clamp(door.left, door.right)).abs(), lessThanOrEqualTo(64));
  });

  // Ловит: реплика растянулась в монолог (Денис, 938: «не одним текстом,
  // а мини-сценками и монологом коротким»).
  test('в каждой реплике сценок не больше двух фраз', () {
    for (final OnboardingScene sc in contentScript.scenes) {
      for (final String line in <String>[
        ...sc.lines,
        ...?sc.linesGirl,
      ]) {
        final int sentences = RegExp(r'[.!?…]+(\s|$)')
            .allMatches(line.replaceAll('«?»', ''))
            .length;
        expect(sentences, lessThanOrEqualTo(2), reason: '${sc.id}: $line');
      }
    }
  });

  // Ловит: сброс оставляет сохранённый онбординг — после перезапуска
  // ребёнок попадает в середину старого профиля. Проводка — ровно как в
  // main.dart: openSavedWorld → WorldState.persistent.
  test('сброс через SavedWorld: свежий мир, сохранённое стёрто', () async {
    final MemoryStorage storage = MemoryStorage();
    await storage.write(onboardingStorageKey,
        const OnboardingProgress(step: 3, nickname: 'Кот').toJson());
    final SavedWorld saved = await openSavedWorld(
        read: (String p) => File(p).readAsString(), storage: storage);
    final WorldState ws = WorldState.persistent(saved.world,
        freshWorld: saved.freshWorld, onReset: saved.forget);
    expect(ws.onboarding.nickname, 'Кот');
    await ws.reset();
    expect(ws.onboarding.nickname, isEmpty);
    expect(ws.world, same(saved.world), reason: 'сохраняется новый мир');
    expect(await storage.read(onboardingStorageKey), isNull);

    // Ловит: стирание шло без ожидания и съедало выбор, сделанный сразу
    // после сброса (демо-панель ставит ник «Тест» следом за сбросом).
    await ws.setNickname('Тест');
    await saved.flush();
    expect((await loadOnboarding(storage)).nickname, 'Тест');
  });

  // Телефон Алины 28.09 (портрет): в плане всё уже в НУЖНО, «+» были
  // погашены — «кнопки не работают». Настоящее касание «+» теперь объясняет.
  forEachWorld((WorldKind kind) {
    testWidgets('план: «+» при остатке 0 говорит, что сделать · ${kind.name}',
        (WidgetTester tester) async {
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: kind.make(), size: const Size(393, 851));
      await _register(tester, customise: false);
      await tester.tap(_skip);
      await _settle(tester);
      await _fillNeeds(tester);
      expect(find.text(planAllSpentLine), findsOneWidget);
      final Finder plus = find.byKey(const ValueKey<String>('plus:want'));
      await tester.ensureVisible(plus);
      await tester.tap(plus);
      await tester.pump();
      expect(find.text(contentScript.t('pool_full')), findsOneWidget);
    });
  });

  // Денис 29.09: «изначально 0 и пускай сами распределяют»; «всего 600, в
  // копилке то, что ты не можешь трогать» — в плане видно, сколько на
  // неделю, а не сумма с копилкой.
  forEachWorld((WorldKind kind) {
    testWidgets(
        'план: конверты с нуля, «На неделю» — только карманные · '
        '${kind.name}', (WidgetTester tester) async {
      final World fresh = kind.make();
      ok(fresh.startWeek());
      final int pool = fresh.snapshot.unallocated;
      await pumpWorldScreen(tester, const WorldOnboardingScreen(),
          world: kind.make(), size: portrait);
      await _register(tester, customise: false);
      await tester.tap(_skip);
      await _settle(tester);
      for (final String id in <String>['need', 'want', 'goal']) {
        final Finder v = find.descendant(
            of: find
                .ancestor(
                    of: find.byKey(ValueKey<String>('plus:$id')),
                    matching: find.byType(Row))
                .first,
            matching: find.text('0'));
        expect(v, findsOneWidget, reason: '$id начинается с 0');
      }
      final Finder row = find.byKey(const ValueKey<String>('plan:pool'));
      expect(
          find.descendant(
              of: row, matching: find.text(contentScript.t('pool'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: row,
              matching: find.byWidgetPredicate(
                  (Widget w) => w is Coins && w.amount == pool)),
          findsOneWidget);
      expect(contentScript.t('pool'), isNot(contains('Пришло')));
    });
  });

  // Ловит: правят content/onboarding.json, а в сборку едет старая копия.
  test('копия onboarding.json в assets совпадает с content/', () {
    final String root = File('../../content/onboarding.json')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final String asset =
        File(OnboardingScript.path).readAsStringSync().replaceAll('\r\n', '\n');
    expect(asset, root,
        reason: 'скопируй content/onboarding.json в ${OnboardingScript.path}');
  });

  // Ловит: сценка без реплик или с неизвестным предметом доезжает до
  // ребёнка пустым облаком — разбор называет поле.
  test('битая сценка называет поле', () {
    expect(
        () => _withScenes(<Object?>[
              <String, Object?>{
                'id': 'x',
                'kind': 'talk',
                'focus': 'sofa',
                'lines': <String>['a'],
                'help': 'h',
              },
            ]),
        throwsA(isA<FormatException>().having((FormatException e) => e.message,
            'message', contains('scenes[0].focus'))));
  });

  _genderTest();

  // Ловит: знакомство снова растянулось — на живом показе (Приложение А)
  // до комнаты не больше восьми касаний «Дальше».
  test('до комнаты не больше восьми касаний «Дальше»', () {
    final int taps = contentScript.scenes.fold(
        0,
        (int n, OnboardingScene s) =>
            n + (s.kind == SceneKind.talk ? s.lines.length : 1));
    expect(taps, lessThanOrEqualTo(8));
  });

  // Ловит: битый onboarding.json роняет запуск — вместо этого знакомство
  // без реплик: сразу план и цель.
  test('битый onboarding.json — запасной сценарий с планом и целью', () async {
    final OnboardingScript s =
        await OnboardingScript.load((String _) async => '{битый');
    expect(identical(s, OnboardingScript.fallback), isTrue);
    expect(s.planIndex, greaterThanOrEqualTo(0));
    expect(s.goalIndex, greaterThan(s.planIndex));
    final OnboardingScript real = await OnboardingScript.load(
        (String p) async => File(p).readAsStringSync());
    expect(identical(real, OnboardingScript.fallback), isFalse);
  });
}

// Ловит: у реплики с мужским родом нет варианта для девочки (ревью 29.09:
// «жить одному», «вырос», «снял»). Слова рода — список: новое слово с
// родом дописывается сюда же.
final RegExp _masculine = RegExp(
    r'(^|[^а-яё])(вырос|снял|сам|сын|одному|переехал|положил|гляну|рад)([^а-яё]|$)',
    caseSensitive: false);

void _genderTest() {
  test('реплика с мужским родом — есть вариант для девочки', () {
    for (final OnboardingScene sc in contentScript.scenes) {
      for (int i = 0; i < sc.lines.length; i++) {
        if (!_masculine.hasMatch(sc.lines[i])) continue;
        expect(sc.linesGirl, isNotNull, reason: '${sc.id}: ${sc.lines[i]}');
        expect(_masculine.hasMatch(sc.linesGirl![i]), isFalse,
            reason: '${sc.id} (девочка): ${sc.linesGirl![i]}');
      }
      if (_masculine.hasMatch(sc.help)) {
        expect(sc.helpGirl, isNotNull, reason: '${sc.id}: ${sc.help}');
      }
    }
  });
}

/// Настоящий `onboarding.json` с другими сценами: подписи, конверты и шаг
/// плана — из сборки, сцены — свои.
OnboardingScript _withScenes(List<Object?> scenes, {String? skip}) {
  final Map<String, Object?> root =
      jsonDecode(File(OnboardingScript.path).readAsStringSync())
          as Map<String, Object?>;
  root['scenes'] = scenes;
  if (skip != null) root['skip'] = skip;
  return OnboardingScript.parse(jsonEncode(root));
}
