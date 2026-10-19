import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../domain/world/contract.dart';

/// Как разложен город (Денис, 29.09, 10:02: «направление экрана должно быть
/// как в clash of clans примерно, сейчас слишком вертикально» — вопрос
/// открыт с Алиной, поэтому два варианта).
enum CityVariant {
  /// A · «вертикально, но наполнено»: прежняя колонка ромбов 160 × 170,
  /// карта целиком в ширину портрета.
  vertical,

  /// B · «как Clash of Clans»: ромбы 2 : 1, поле 5 × 5 под углом, шире,
  /// чем выше; в портрете карта шире экрана и листается пальцем вбок.
  iso,
}

/// 🔴 Выбор варианта — одна строка. Денис выбрал B (29.09: «B 100%,
/// вообще супер»); A остаётся для сравнения.
const CityVariant cityVariant = CityVariant.iso;

/// Камера города — все числа настройки в одном месте (Денис, 29.09, 10:33:
/// «как в paper mario экран должен следовать за финни»).
abstract final class CityCamera {
  /// Мёртвая зона: доля окна в центре, где Финни ходит, а камера стоит.
  static const double deadZone = 0.3;

  /// Сколько камера догоняет Финни. «Анимации» выкл. — сразу.
  static const Duration ease = Duration(milliseconds: 250);

  /// Постоянный масштаб карты: здания читаются, карта крупнее окна.
  ///
  /// [shortSide] — короткая сторона экрана в dp. Телефон (до [phoneSide])
  /// — масштаб как был. Планшет и компьютер — крупнее, по короткой стороне,
  /// но не больше [maxGrow]: иначе вся карта влезала в окно маленькой, Финни
  /// был в 30 px, и камере некого было вести (финал, «камера и адаптив»).
  static double scale(CityVariant v, {double shortSide = 0}) =>
      switch (v) {
        CityVariant.vertical => 1.25,
        CityVariant.iso => 1.1,
      } *
      (shortSide / phoneSide).clamp(1.0, maxGrow);

  /// Короткая сторона самого крупного телефона (S25 Ultra ≈ 412 dp).
  static const double phoneSide = 412;

  /// Во сколько раз карта может вырасти на большом экране.
  static const double maxGrow = 2.2;
}

/// Клетка сетки: (столбец, ряд).
typedef CityCell = (int, int);

/// Вид декора. Спрайты — заготовки трека арта (`night_items/city_*`),
/// остальное рисуется кодом по пиксельной сетке ([cityPixelSprite]).
enum DecorKind {
  tree,
  bench,
  fountain,
  busstop,
  kiosk,
  flowerbed,
  bush,
  bushSmall,
  lamp,
  flowers,
  fenceDown, // забор вдоль «\» (вниз-вправо)
  fenceUp, // забор вдоль «/» (вверх-вправо)
}

/// Предмет декора: вид и точка, где он стоит на земле (низ-центр, px карты
/// при 1×). Декор не нажимается и не читается TalkBack.
@immutable
class CityDecor {
  const CityDecor(this.kind, this.x, this.y);

  final DecorKind kind;
  final double x;
  final double y;

  Offset get bottom => Offset(x, y);
}

/// Геометрия варианта: шаг сетки, где какое здание, какие клетки — земля,
/// какие — дорога, и декор по стадиям.
@immutable
class CityGeometry {
  const CityGeometry._({
    required this.variant,
    required this.tileW,
    required this.tileH,
    required this.topPad,
    required this.originX,
    required this.base,
    required this.cells,
    required this.ground,
    required this.roads,
    required this.skyline,
    required Map<WorldStage, List<CityDecor>> decor,
    this.grid = 0,
    required this.walkSpan,
    this.doorLeft = const <String>{},
  }) : _decor = decor;

  /// Сторона поля в клетках (B — квадрат `grid × grid`); A — 0.
  final int grid;

  /// Путь этой длины (px при 1×) идётся за самое долгое время перехода:
  /// ширина прежней карты. Карта выросла — переходы между прежними
  /// зданиями идут прежнее время, а не быстрее.
  final double walkSpan;

  /// Здания, у которых дверь слева от переднего угла ([CityWalk.door]):
  /// Магазин стоял у правого края прежнего поля — дверь там и остаётся.
  final Set<String> doorLeft;

  final CityVariant variant;
  final double tileW;
  final double tileH;

  /// Поле над верхней клеткой: значок роли и «!» верхнего здания.
  final double topPad;

  /// x верхнего угла клетки (0, 0).
  final double originX;

  /// Размер карты при 1×.
  final Size base;

  /// Здание → клетка.
  final Map<String, CityCell> cells;

  /// Клетки земли (ромбы, по которым ходит Финни).
  final List<CityCell> ground;

  /// Клетки-дороги (только B; в A дорожки — кромки ромбов).
  final Set<CityCell> roads;

  /// Башни Москва-Сити: id и низ-центр при 1×.
  final List<(String, Offset)> skyline;

  final Map<WorldStage, List<CityDecor>> _decor;

  bool get iso => variant == CityVariant.iso;

  /// Декор стадии: деревня, город и Москва выглядят по-разному.
  List<CityDecor> decor(WorldStage stage) =>
      _decor[stage] ?? const <CityDecor>[];

  /// Нижний угол клетки — якорь спрайта здания.
  Offset anchor(CityCell c) => Offset(
        originX + (c.$1 - c.$2) * tileW / 2,
        topPad + tileH + (c.$1 + c.$2) * tileH / 2,
      );

  /// Центр ромба клетки.
  Offset center(CityCell c) => anchor(c) - Offset(0, tileH / 2);

  /// Точка внутри ромба клетки [c].
  bool inCell(CityCell c, Offset p) {
    final Offset m = center(c);
    return (p.dx - m.dx).abs() / (tileW / 2) +
            (p.dy - m.dy).abs() / (tileH / 2) <=
        1;
  }

  /// Точка на земле города (там, где Финни может идти джойстиком).
  bool onGround(Offset p) {
    for (final CityCell c in ground) {
      if (inCell(c, p)) return true;
    }
    return false;
  }

  static CityGeometry of(CityVariant v) =>
      v == CityVariant.iso ? isoGeometry : verticalGeometry;
}

// ─── A · вертикально ──────────────────────────────────────────────────────

const Map<String, CityCell> _cellsA = <String, CityCell>{
  'home': (1, 1),
  'grocery': (1, 2),
  'job-centre': (0, 1),
  'pet-shop': (2, 1),
  'park': (0, 0),
  'cinema': (1, 0),
  'piggy-bank': (2, 2),
};

/// A: прежняя сетка 3 × 3 без левого и правого углов, шаг 160 × 170 (ревью
/// 29.09: «Дом касается Магазина» — было 136 × 68). Декор — в пустых углах
/// карты и на перекрёстках дорожек; зданий и значков не касается.
const CityGeometry verticalGeometry = CityGeometry._(
  variant: CityVariant.vertical,
  tileW: 160,
  tileH: 170,
  topPad: 8,
  originX: 160,
  base: Size(320, 8 + 3 * 170 + 8),
  walkSpan: 320,
  cells: _cellsA,
  ground: <CityCell>[(1, 1), (1, 2), (0, 1), (2, 1), (0, 0), (1, 0), (2, 2)],
  roads: <CityCell>{},
  skyline: <(String, Offset)>[
    ('moscow-city-a', Offset(80, 231)),
    ('moscow-city-b', Offset(240, 233)),
  ],
  decor: <WorldStage, List<CityDecor>>{
    WorldStage.village: _decorAVillage,
    WorldStage.town: _decorATown,
    WorldStage.moscow: _decorAMoscow,
  },
);

// Углы карты A (вне ромбов): верх-лево / верх-право — треугольники над
// Парком, лево / право — выемки между ромбами, низ-лево / низ-право — под
// Магазином и Зоомагазином. Координаты — низ-центр предмета.
const List<CityDecor> _decorAVillage = <CityDecor>[
  CityDecor(DecorKind.tree, 34, 62),
  CityDecor(DecorKind.bush, 86, 34),
  CityDecor(DecorKind.tree, 286, 62),
  CityDecor(DecorKind.bushSmall, 238, 30),
  CityDecor(DecorKind.fenceDown, 16, 120),
  CityDecor(DecorKind.flowers, 44, 150),
  CityDecor(DecorKind.fenceUp, 304, 120),
  CityDecor(DecorKind.bush, 22, 262),
  CityDecor(DecorKind.bushSmall, 300, 262),
  CityDecor(DecorKind.tree, 30, 478),
  CityDecor(DecorKind.bush, 70, 516),
  CityDecor(DecorKind.tree, 292, 478),
  CityDecor(DecorKind.flowers, 256, 512),
  CityDecor(DecorKind.bushSmall, 12, 404),
  CityDecor(DecorKind.bushSmall, 304, 404),
];

const List<CityDecor> _decorATown = <CityDecor>[
  CityDecor(DecorKind.tree, 34, 62),
  CityDecor(DecorKind.bench, 96, 40),
  CityDecor(DecorKind.tree, 286, 62),
  CityDecor(DecorKind.bushSmall, 238, 30),
  CityDecor(DecorKind.flowerbed, 36, 146),
  CityDecor(DecorKind.lamp, 80, 94),
  CityDecor(DecorKind.lamp, 240, 94),
  CityDecor(DecorKind.bush, 290, 150),
  CityDecor(DecorKind.lamp, 130, 262),
  CityDecor(DecorKind.lamp, 190, 262),
  CityDecor(DecorKind.bush, 22, 262),
  CityDecor(DecorKind.bushSmall, 300, 262),
  CityDecor(DecorKind.tree, 30, 478),
  CityDecor(DecorKind.kiosk, 282, 486),
  CityDecor(DecorKind.bush, 70, 516),
  CityDecor(DecorKind.flowers, 256, 518),
];

const List<CityDecor> _decorAMoscow = <CityDecor>[
  CityDecor(DecorKind.bush, 30, 56),
  CityDecor(DecorKind.fountain, 102, 60),
  CityDecor(DecorKind.bush, 290, 56),
  CityDecor(DecorKind.flowerbed, 240, 40),
  CityDecor(DecorKind.busstop, 38, 150),
  CityDecor(DecorKind.lamp, 80, 94),
  CityDecor(DecorKind.lamp, 240, 94),
  CityDecor(DecorKind.kiosk, 290, 152),
  CityDecor(DecorKind.lamp, 130, 262),
  CityDecor(DecorKind.lamp, 190, 262),
  CityDecor(DecorKind.flowers, 20, 262),
  CityDecor(DecorKind.flowers, 302, 262),
  CityDecor(DecorKind.lamp, 139, 432),
  CityDecor(DecorKind.lamp, 181, 432),
  CityDecor(DecorKind.flowerbed, 34, 480),
  CityDecor(DecorKind.bench, 284, 484),
  CityDecor(DecorKind.bushSmall, 70, 518),
  CityDecor(DecorKind.bushSmall, 252, 518),
];

// ─── B · как Clash of Clans ───────────────────────────────────────────────

/// B: поле 8 × 8 ромбов 128 × 64 (2 : 1). Прежний квартал 5 × 5 (здания,
/// дороги, декор) — клетки 0…4 без изменений; вокруг него — новые кварталы
/// (Денис, ночь 18.10: «town is too small»): главная улица (ряд 2) и
/// проспект (столбец 2) продлены до края, кольцо — ряд 6 и столбец 6,
/// площадь у перекрёстка, парк и скверы. Здания — по два в каждой
/// четверти прежнего квартала (так они не заслоняют друг друга).
const Map<String, CityCell> _cellsB = <String, CityCell>{
  'park': (0, 1),
  'cinema': (1, 0),
  'pet-shop': (3, 1),
  'grocery': (4, 0),
  'job-centre': (1, 3),
  'piggy-bank': (0, 4),
  'home': (3, 4),
};

const double _bTopPad = 56;

/// Сторона поля B в клетках.
const int _bGrid = 8;

/// Прежний квартал 5 × 5 сдвинут вправо на столько: поле выросло и влево.
const double _bShift = (_bGrid - 5) * 64.0;

const double _bOriginX = _bGrid * 64.0;

/// Центр ромба клетки B (px при 1×) — для декора новых кварталов.
Offset _bAt(int c, int r, [double dx = 0, double dy = 0]) => Offset(
    _bOriginX + (c - r) * 64 + dx, _bTopPad + 64 + (c + r) * 32 - 32 + dy);

/// Дороги прежнего квартала.
const Set<CityCell> _roadsOld = <CityCell>{
  (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), //
  (2, 0), (2, 1), (2, 3), (2, 4),
  (4, 1), // дорожка к Магазину
  (0, 3), // дорожка к Копилке
};

/// Дороги новых кварталов: главная улица и проспект до края, кольцо
/// (ряд 6 и столбец 6), площадь у перекрёстка (4, 5) · (5, 5).
final Set<CityCell> _roadsNew = <CityCell>{
  for (int i = 5; i < _bGrid; i++) ...<CityCell>{(i, 2), (2, i)},
  for (int i = 0; i < _bGrid; i++) ...<CityCell>{(i, 6), (6, i)},
  (4, 5), (5, 5), // площадь
};

final CityGeometry isoGeometry = CityGeometry._(
  variant: CityVariant.iso,
  tileW: 128,
  tileH: 64,
  topPad: _bTopPad,
  originX: _bOriginX,
  base: const Size(_bGrid * 128, _bTopPad + _bGrid * 64 + 8),
  grid: _bGrid,
  walkSpan: 640,
  doorLeft: const <String>{'grocery'},
  cells: _cellsB,
  ground: <CityCell>[
    for (int c = 0; c < _bGrid; c++)
      for (int r = 0; r < _bGrid; r++) (c, r),
  ],
  roads: <CityCell>{..._roadsOld, ..._roadsNew},
  skyline: const <(String, Offset)>[
    ('moscow-city-a', Offset(150 + _bShift, 132)),
    ('moscow-city-b', Offset(492 + _bShift, 130)),
  ],
  decor: <WorldStage, List<CityDecor>>{
    for (final WorldStage s in WorldStage.values)
      s: <CityDecor>[
        for (final CityDecor d in switch (s) {
          WorldStage.village => _decorBVillage,
          WorldStage.town => _decorBTown,
          WorldStage.moscow => _decorBMoscow,
        })
          CityDecor(d.kind, d.x + _bShift, d.y),
        ..._edgeBig,
        ..._decorNew(s),
      ],
  },
);

// Прежний квартал (px при 1× до сдвига на [_bShift]). Свободные клетки
// травы: (0,0) 320,88 · (1,1) 320,152 · (3,0) 512,184 · (1,4) 128,248 ·
// (3,3) 320,280 · (4,3) 384,312 · (4,4) 320,344. Перекрёсток (2,2) — 320,216.
const List<CityDecor> _edgeB = <CityDecor>[
  // Опушка над прежним кварталом: слева-сверху и справа-сверху.
  CityDecor(DecorKind.tree, 40, 120),
  CityDecor(DecorKind.tree, 96, 92),
  CityDecor(DecorKind.bush, 190, 50),
  CityDecor(DecorKind.tree, 600, 120),
  CityDecor(DecorKind.tree, 546, 92),
  CityDecor(DecorKind.bush, 452, 50),
];

/// Опушка вокруг всего поля 8 × 8: в треугольниках карты вне ромба,
/// слева и зеркально справа.
final List<CityDecor> _edgeBig = <CityDecor>[
  for (final (DecorKind k, double x, double y) in <(DecorKind, double, double)>[
    (DecorKind.tree, 70, 150),
    (DecorKind.bush, 150, 110),
    (DecorKind.tree, 40, 470),
    (DecorKind.bush, 110, 520),
    (DecorKind.tree, 200, 556),
    (DecorKind.bushSmall, 60, 400),
  ]) ...<CityDecor>[
    CityDecor(k, x, y),
    CityDecor(k, _bGrid * 128 - x, y),
  ],
];

const List<CityDecor> _decorBVillage = <CityDecor>[
  ..._edgeB,
  CityDecor(DecorKind.tree, 320, 100),
  CityDecor(DecorKind.flowers, 304, 160),
  CityDecor(DecorKind.bush, 338, 172),
  CityDecor(DecorKind.fenceDown, 502, 164), // на траве (3, 0), не на дороге (2, 0)
  CityDecor(DecorKind.bushSmall, 530, 162),
  CityDecor(DecorKind.tree, 128, 278),
  CityDecor(DecorKind.bush, 330, 292),
  CityDecor(DecorKind.flowers, 384, 318),
  CityDecor(DecorKind.bushSmall, 408, 330),
  CityDecor(DecorKind.fenceUp, 356, 300),
  CityDecor(DecorKind.tree, 322, 356),
];

const List<CityDecor> _decorBTown = <CityDecor>[
  ..._edgeB,
  CityDecor(DecorKind.tree, 320, 100),
  CityDecor(DecorKind.bench, 320, 172),
  CityDecor(DecorKind.flowerbed, 512, 160),
  CityDecor(DecorKind.kiosk, 128, 276),
  CityDecor(DecorKind.bush, 330, 292),
  CityDecor(DecorKind.flowerbed, 384, 326),
  CityDecor(DecorKind.tree, 322, 356),
  // Фонари на углах перекрёстка.
  CityDecor(DecorKind.lamp, 256, 216),
  CityDecor(DecorKind.lamp, 384, 216),
  CityDecor(DecorKind.lamp, 320, 250),
];

const List<CityDecor> _decorBMoscow = <CityDecor>[
  ..._edgeB,
  CityDecor(DecorKind.flowers, 320, 100),
  CityDecor(DecorKind.bench, 320, 172),
  CityDecor(DecorKind.flowers, 512, 166),
  CityDecor(DecorKind.kiosk, 128, 276),
  CityDecor(DecorKind.bushSmall, 334, 292),
  CityDecor(DecorKind.fountain, 384, 334),
  CityDecor(DecorKind.flowers, 322, 356),
  CityDecor(DecorKind.lamp, 256, 216),
  CityDecor(DecorKind.lamp, 384, 216),
  CityDecor(DecorKind.lamp, 320, 250),
  // Не на дорожках к Копилке (0, 3) и к Магазину (4, 1): на траве рядом.
  CityDecor(DecorKind.lamp, 128, 224),
  CityDecor(DecorKind.lamp, 526, 280),
];

/// Декор новых кварталов — по клеткам травы, только уже готовые виды.
/// Парк — клетки (7, 0) · (7, 1) · (7, 3) · (7, 4); сквер — (0, 5) · (1, 5)
/// · (0, 7) · (1, 7). Площадь (4, 5) · (5, 5) — дорога, декора на ней нет.
List<CityDecor> _decorNew(WorldStage s) {
  final bool v = s == WorldStage.village, m = s == WorldStage.moscow;
  CityDecor d(DecorKind k, int c, int r, [double dx = 0, double dy = 0]) {
    final Offset p = _bAt(c, r, dx, dy);
    return CityDecor(k, p.dx, p.dy);
  }

  return <CityDecor>[
    // Парк за кольцом справа.
    d(DecorKind.tree, 7, 0, -26, 4),
    d(v ? DecorKind.bush : DecorKind.bench, 7, 0, 24, 10),
    d(DecorKind.tree, 7, 1, 20, 2),
    d(m ? DecorKind.fountain : DecorKind.flowers, 7, 1, -22, 14),
    d(DecorKind.tree, 7, 3, -18, 6),
    d(DecorKind.bushSmall, 7, 3, 26, 12),
    d(v ? DecorKind.flowers : DecorKind.flowerbed, 7, 4, 0, 10),
    d(DecorKind.tree, 7, 5, 16, 8),
    // Между прежним кварталом и кольцом справа.
    d(DecorKind.bush, 5, 0, 34, 12),
    d(v ? DecorKind.fenceDown : DecorKind.lamp, 5, 1, 30, 4),
    d(DecorKind.tree, 5, 3, -10, 8),
    d(v ? DecorKind.flowers : DecorKind.kiosk, 5, 4, 14, 12),
    // Сквер слева внизу.
    d(DecorKind.tree, 0, 5, 0, 8),
    d(DecorKind.bushSmall, 1, 5, 20, 12),
    d(v ? DecorKind.fenceUp : DecorKind.lamp, 1, 5, -28, 6),
    d(DecorKind.tree, 0, 7, 10, 6),
    d(v ? DecorKind.bush : DecorKind.bench, 1, 7, -10, 12),
    d(DecorKind.flowers, 3, 5, 0, 10),
    // Нижние кварталы.
    d(m ? DecorKind.busstop : DecorKind.bush, 3, 7, 0, 10),
    d(DecorKind.tree, 4, 7, -20, 6),
    d(DecorKind.bushSmall, 4, 7, 24, 12),
    d(DecorKind.tree, 5, 7, 18, 4),
    d(v ? DecorKind.flowers : DecorKind.flowerbed, 5, 7, -24, 14),
    d(DecorKind.tree, 7, 7, 0, 6),
    // Были на площади (4, 5) · (5, 5) — это дорога (скрин Дениса 18.10:
    // клумба посреди дороги под Домом). Теперь на траве рядом: клумба или
    // фонтан — у парка за кольцом, фонари — по краям площади.
    d(s == WorldStage.town ? DecorKind.fountain : DecorKind.flowerbed, 7, 5,
        -34, 0),
    if (!v) ...<CityDecor>[
      d(DecorKind.lamp, 3, 5, 14, 18),
      d(DecorKind.lamp, 5, 4, -40, 4),
    ],
  ];
}
