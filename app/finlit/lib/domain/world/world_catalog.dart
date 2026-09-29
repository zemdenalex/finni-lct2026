import 'dart:math' as math;

import 'contract.dart';
import 'world_config.dart';

/// Каталог нового мира из [WorldConfig] (карточка A11) — общий для
/// `WorldGame` и `FakeWorld`, чтобы цены на экране и списание в `buy` брались
/// из одного места.
///
/// [leisureEnergy] — цена досуга в ⚡ **сейчас** (с 😊 и «на жизнь»): её
/// считает мир, каталог только кладёт в [WorldCatalogItem.energy] со знаком
/// минус.
List<WorldCatalogItem> catalogFromConfig(
  WorldConfig c, {
  required double Function(WorldLeisure l) leisureEnergy,
}) {
  final List<WorldJob> transportJobs =
      c.jobs.where((WorldJob j) => j.needs == 'transport').toList();
  final String transportPerk = transportJobs.isEmpty
      ? 'Смены на ⚡ легче'
      : 'Открывает работу «${_baseTitle(transportJobs.first.title)}», '
          'смены на ⚡ легче. ${_payback(c, c.transportPrice, transportJobs)}';

  return <WorldCatalogItem>[
    for (final WorldPet p in c.pets)
      WorldCatalogItem(
        id: p.id,
        title: p.title,
        category: WorldCatalogCategory.pet,
        price: p.price,
        weeklyCost: p.foodPerWeek,
        happiness: p.happinessPerWeek,
        perk: _petPerk(c, p.id),
      ),
    for (final MapEntry<String, String> t in c.transports.entries)
      WorldCatalogItem(
        id: t.key,
        title: t.value,
        category: WorldCatalogCategory.transport,
        price: c.transportPrice,
        perk: transportPerk,
      ),
    for (final WorldTech t in c.techs)
      WorldCatalogItem(
        id: t.id,
        title: t.title,
        category: WorldCatalogCategory.tech,
        price: t.price,
        perk: _techPerk(c, t),
      ),
    for (final WorldHome h in c.homes)
      if (h.isGoal)
        WorldCatalogItem(
          id: h.id,
          title: h.title,
          category: WorldCatalogCategory.home,
          price: h.price,
          weeklyCost: h.weeklyCost,
          happiness: h.happinessPerWeek,
          energy: h.energyPerWeek,
          perk: _movePerk(c, h),
        ),
    for (final WorldItem i in c.clothes)
      WorldCatalogItem(
        id: i.id,
        title: i.title,
        category: WorldCatalogCategory.clothes,
        price: i.price,
        happiness: i.happinessByWeek.isEmpty ? 0 : i.happinessByWeek.first,
        happinessByWeek: i.happinessByWeek,
      ),
    for (final WorldItem i in c.decor)
      WorldCatalogItem(
        id: i.id,
        title: i.title,
        category: WorldCatalogCategory.decor,
        price: i.price,
        happiness: i.happinessByWeek.isEmpty ? 0 : i.happinessByWeek.first,
      ),
    WorldCatalogItem(
      id: c.snackId,
      title: 'Перекус',
      category: WorldCatalogCategory.snack,
      price: c.snackPrice,
      energy: c.snackEnergyNow,
      weeklyLimit: c.snackMaxPerWeek,
    ),
    for (final WorldFood f in c.foods)
      WorldCatalogItem(
        id: f.id,
        title: f.title,
        category: WorldCatalogCategory.food,
        price: f.price,
        weeklyCost: f.price * c.mealsPerWeek,
        happiness: f.happiness,
        energy: f.energyNow,
        weeklyLimit: c.mealsPerWeek,
      ),
    for (final WorldLeisure l in c.leisure)
      WorldCatalogItem(
        id: l.id,
        title: l.title,
        category: WorldCatalogCategory.leisure,
        price: l.price,
        happiness: l.happiness,
        energy: -leisureEnergy(l),
        requires: l.requires,
        requiresText: l.needsPet ? 'Нужен питомец' : null,
      ),
  ];
}

/// Позиция по id.
WorldCatalogItem? findCatalogItem(List<WorldCatalogItem> catalog, String id) {
  for (final WorldCatalogItem i in catalog) {
    if (i.id == id) return i;
  }
  return null;
}

/// «Курьер · близко» → «Курьер».
String _baseTitle(String title) => title.split(' · ').first;

/// Что даст переезд (критерии ночи §7 п. 5): стадия, ступень оплаты и
/// сколько очков роста нужно.
String? _movePerk(WorldConfig c, WorldHome h) {
  final WorldStage? s = h.stage;
  if (s == null) return null;
  const Map<WorldStage, String> place = <WorldStage, String>{
    WorldStage.village: 'в деревню',
    WorldStage.town: 'в город',
    WorldStage.moscow: 'в Москву',
  };
  final double step = s.index < c.stageSteps.length ? c.stageSteps[s.index] : 1;
  final int points =
      s.index < c.stageMinPoints.length ? c.stageMinPoints[s.index] : 0;
  final String pay =
      step == 1 ? '' : ', оплата смен ×${step.toString().replaceAll('.', ',')}';
  return 'Переезд ${place[s]}: аренда, залог и первая неделя — ${h.price}$pay. '
      'Откроется при $points очках роста';
}

/// Что открывает техника — из замков работ конфига, которые исполняет мир:
/// «Открывает работу «Программист»: лёгкая, средняя».
String? _techPerk(WorldConfig c, WorldTech t) {
  final Map<String, List<String>> byJob = <String, List<String>>{};
  for (final WorldJob j in c.jobs) {
    if (j.needs == null || !t.unlocks.contains(j.needs)) continue;
    final List<String> parts = j.title.split(' · ');
    final List<String> levels = byJob[parts.first] ??= <String>[];
    if (parts.length > 1) levels.add(parts[1]);
  }
  if (byJob.isEmpty) return null;
  final List<WorldJob> opened = <WorldJob>[
    for (final WorldJob j in c.jobs)
      if (j.needs != null && t.unlocks.contains(j.needs)) j,
  ];
  return '${byJob.entries.map((MapEntry<String, List<String>> e) => e.value.isEmpty ? 'Открывает работу «${e.key}»' : 'Открывает работу «${e.key}»: ${e.value.join(', ')}').join('. ')}. '
      '${_payback(c, t.price, opened)}';
}

/// Инструмент — вложение (критерии ночи 29.09, §3 п. 4; ревью 28d9a1f).
/// Честно: окупает вещь только **прибавка** к тому, что Финни и так
/// зарабатывает, — лучшая открытая ею ставка минус лучшая ставка работы,
/// открытой с первого дня. Ставки базовые (без опыта и 😊), округление
/// вверх — не обещать раньше, чем получится. Прибавки нет — так и сказать.
String _payback(WorldConfig c, int price, List<WorldJob> opened) {
  WorldJob? best;
  for (final WorldJob j in opened) {
    if (best == null || j.pay > best.pay) best = j;
  }
  WorldJob? base;
  for (final WorldJob j in c.jobs) {
    if (j.needs != null) continue;
    if (base == null || j.pay > base.pay) base = j;
  }
  if (best == null || base == null) return '';
  final int gain = best.pay - base.pay;
  if (gain <= 0) {
    return 'Только оплатой не окупится: «${_baseTitle(best.title)}» платит не '
        'больше, чем «${base.title}», — зато работа новая';
  }
  final int shifts = (price + gain - 1) ~/ gain;
  // В неделях — чтобы срок был виден на шкале игры: одну работу берут не
  // чаще `max_shifts_per_job_per_week` раз в неделю (ревью 2b58bdb §3.4).
  final int cap = math.max(1, c.maxShiftsPerJobPerWeek);
  final int weeks = (shifts + cap - 1) ~/ cap;
  // Словами, не «≈»: в Onest нет U+2248 (font_glyphs_test).
  return 'Окупится примерно за $shifts ${_shiftWord(shifts)}, то есть '
      'за $weeks ${_weekWord(weeks)}: '
      '«${best.title}» платит на $gain больше, чем «${base.title}»';
}

/// «неделю / недели / недель» после «за N».
String _weekWord(int n) {
  final int m10 = n % 10;
  final int m100 = n % 100;
  if (m100 >= 11 && m100 <= 14) return 'недель';
  if (m10 == 1) return 'неделю';
  if (m10 >= 2 && m10 <= 4) return 'недели';
  return 'недель';
}

/// «смену / смены / смен» после «за N».
String _shiftWord(int n) {
  final int m10 = n % 10;
  final int m100 = n % 100;
  if (m100 >= 11 && m100 <= 14) return 'смен';
  if (m10 == 1) return 'смену';
  if (m10 >= 2 && m10 <= 4) return 'смены';
  return 'смен';
}

/// Перк питомца одной фразой — из тех же полей конфига, что исполняет мир.
String? _petPerk(WorldConfig c, String petId) {
  final List<String> out = <String>[];
  final ({String jobId, double mult})? pay = c.payPerks[petId];
  if (pay != null) {
    WorldJob? job;
    for (final WorldJob j in c.jobs) {
      if (j.id == pay.jobId) job = j;
    }
    final int pct = ((pay.mult - 1) * 100).round();
    out.add('${job == null ? pay.jobId : _baseTitle(job.title)}: '
        'оплата +$pct %');
  }
  if (c.sleepHappinessPerks.containsKey(petId)) {
    out.add('ранний сон радует больше');
  }
  if (c.sleepCarryPerks.containsKey(petId)) {
    out.add('ранний сон бережёт больше ⚡');
  }
  if (c.decayPerks.containsKey(petId)) {
    out.add('радость остывает медленнее');
  }
  for (final WorldJob j in c.jobs) {
    if (j.needs == petId) out.add('открывает работу «${_baseTitle(j.title)}»');
  }
  if (out.isEmpty) return null;
  final String s = out.join(', ');
  return s[0].toUpperCase() + s.substring(1);
}
