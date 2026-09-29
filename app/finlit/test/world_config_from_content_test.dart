import 'dart:io';

import 'package:finlit/data/world_config_from_content.dart';
import 'package:finlit/data/world_content.dart';
import 'package:finlit/domain/world/world_config.dart';
import 'package:finlit/domain/world/world_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'domain/world/week_one_scenario.dart';

/// Настоящие файлы из assets → [WorldConfig], синхронно (сценарий недели
/// строит мир внутри теста).
WorldConfig _fromFiles() {
  String read(String f) =>
      File('${WorldContentLoader.base}/$f').readAsStringSync();
  return worldConfigFromContent(WorldContent.parse(
    economy: read('economy.json'),
    jobs: read('jobs.json'),
    events: read('events.json'),
  ));
}

/// Все числа и id конфига — без названий (их фейк держит свои).
Map<String, Object?> _numbers(WorldConfig c) => <String, Object?>{
      'pocketMoney': c.pocketMoney,
      'startGift': c.startGift,
      'energy': <Object>[
        c.energyBasePerWeek,
        c.energyMax,
        c.livingDrainPerAction,
        c.sleepMinLeftForBonus,
        c.sleepCarryNextWeek,
        c.sleepHappiness,
        c.exhaustedHappiness,
      ],
      'happiness': <Object>[
        c.happinessStart,
        c.happinessMin,
        c.happinessMax,
        c.happinessNeutral,
        c.payMultPerPoint,
        c.payMultMin,
        c.payMultMax,
        c.energyCostMultPerPoint,
        c.energyCostMultMin,
        c.energyCostMultMax,
        c.weeklyDecayBase,
        c.weeklyDecayK,
        c.happinessDayDrain,
        c.weekGrowthIncomeMinShare,
        c.weekGrowthBonus,
        c.stagnationStep,
        c.stagnationMax,
        c.leisureWeeklyCap,
        c.goalReachedBonus,
        c.petsHappinessCap,
        c.petTapHappiness,
        c.familyHelpHappiness,
      ],
      'ids': <Object>[c.simpleFoodId, c.startFoodId, c.startHomeId, c.snackId],
      'shifts': <int>[c.maxShiftsPerWeek, c.maxShiftsPerJobPerWeek],
      'meals': c.mealsPerWeek,
      'p1': <Object>[
        c.experienceGrowth,
        c.goodScoreMin,
        c.goodShiftEnergyExtra,
        c.goodShiftHappiness,
        c.efficiencyShare,
      ],
      'growth': <Object>[
        c.savedRegularlyMinShare,
        c.growthPointsPerReason,
        ...c.stageMinPoints,
        ...c.stageSteps,
      ],
      'snack': <Object>[c.snackPrice, c.snackEnergyNow, c.snackMaxPerWeek],
      'transport': <Object>[
        c.transportPrice,
        c.transportDiscount,
        c.transportMinJobEnergy,
        ...c.transports.keys,
      ],
      'foods': <String>[
        for (final WorldFood f in c.foods)
          '${f.id} ${f.price} ${f.happiness} ${f.energyNow} ${f.treat} ${f.why}',
      ],
      'homes': <String>[
        for (final WorldHome h in c.homes)
          '${h.id} ${h.price} ${h.weeklyCost} ${h.energyPerWeek} '
              '${h.happinessPerWeek}',
      ],
      'pets': <String>[
        for (final WorldPet p in c.pets)
          '${p.id} ${p.price} ${p.foodPerWeek} ${p.happinessPerWeek}',
      ],
      'items': <String>[
        for (final WorldItem i in <WorldItem>[...c.clothes, ...c.decor])
          '${i.id} ${i.price} ${i.happinessByWeek}',
      ],
      'leisure': <String>[
        for (final WorldLeisure l in c.leisure)
          '${l.id} ${l.price} ${l.energy} ${l.happiness} ${l.perExtraPet} '
              '${l.requires}',
      ],
      'jobs': <String>[
        for (final WorldJob j in c.jobs)
          '${j.id}/${j.variant} ${j.pay} ${j.energy} ${j.needs}',
      ],
      'perks': <Object>[
        c.sleepHappinessPerks,
        c.sleepCarryPerks,
        c.decayPerks,
        <String>[
          for (final MapEntry<String, ({String jobId, double mult})> e
              in c.payPerks.entries)
            '${e.key} ${e.value.jobId} ${e.value.mult.toStringAsFixed(6)}',
        ],
      ],
    };

void main() {
  group('WorldGame на числах из content/',
      () => weekOneEnergyScenario(() => WorldGame(config: _fromFiles())));

  test('загрузчик закрывает расхождения файла и домена', () {
    final WorldConfig c = _fromFiles();

    // Декор: id из файла — те же, по которым экран комнаты узнаёт вещь.
    expect(c.decorItem('poster_city')?.price, 200);
    expect(c.decorItem('light_garland_long')?.happinessByWeek, <int>[3]);

    // Перк котёнка: в файле доля 0,1, в домене множитель 1,1.
    expect(c.payPerks['pet_kitten']?.jobId, 'consultant');
    expect(c.payPerks['pet_kitten']?.mult, closeTo(1.1, 1e-9));

    // Транспорт: shift_energy_delta −0,5 и min_cost 1 → скидка 0,5, минимум 1.
    expect(c.transportDiscount, 0.5);
    expect(c.transportMinJobEnergy, 1);

    // P1 и P6 — из файла, а не из кода.
    expect(c.efficiencyShare, 0.2);
    expect(c.goodScoreMin, 0.75);
    expect(c.goodShiftEnergyExtra, 0.5);
    expect(c.goodShiftHappiness, -1);
    expect(c.stageSteps, <double>[1, 1.2, 1.35]); // перепроверка 29.09

    // В игре только питомцы demo, резерв — после 29.09.
    expect(c.pets.map((WorldPet p) => p.id), <String>[
      'pet_fish',
      'pet_hamster',
      'pet_turtle',
      'pet_kitten',
      'pet_dog',
    ]);
    expect(c.job('programmer', 'hard')?.title, 'Программист · сложная');
  });

  test(
      'значения по умолчанию WorldConfig = content/economy.json '
      '(их читают FakeWorld и WorldGame() без конфига)', () {
    final Map<String, Object?> file = _numbers(_fromFiles());
    final Map<String, Object?> defaults = _numbers(const WorldConfig());
    for (final String key in file.keys) {
      expect(defaults[key].toString(), file[key].toString(),
          reason: 'WorldConfig.$key расходится с файлом: поправь значения '
              'по умолчанию в world_config.dart — иначе экраны на FakeWorld '
              'показывают не те числа, что настоящая игра');
    }
  });
}
