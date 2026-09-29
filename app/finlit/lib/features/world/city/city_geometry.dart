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
  static double scale(CityVariant v) => switch (v) {
        CityVariant.vertical => 1.25,
        CityVariant.iso => 1.1,
      };
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
  }) : _decor = decor;

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

/// B: поле 5 × 5 ромбов 128 × 64 (2 : 1). Дороги — ряд 2 и столбец 2
/// крестом плюс две дорожки к дальним зданиям; здания — по два в каждой
/// четверти, рядом на одной высоте (так они не заслоняют друг друга);
/// пятая «четверть» у Дома — площадь.
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

final CityGeometry isoGeometry = CityGeometry._(
  variant: CityVariant.iso,
  tileW: 128,
  tileH: 64,
  topPad: _bTopPad,
  originX: 320,
  base: Size(640, _bTopPad + 5 * 64 + 8),
  cells: _cellsB,
  ground: <CityCell>[
    for (int c = 0; c < 5; c++)
      for (int r = 0; r < 5; r++) (c, r),
  ],
  roads: <CityCell>{
    for (int i = 0; i < 5; i++) (i, 2),
    for (int i = 0; i < 5; i++) (2, i),
    (4, 1), // дорожка к Магазину
    (0, 3), // дорожка к Копилке
  },
  skyline: <(String, Offset)>[
    ('moscow-city-a', Offset(150, 132)),
    ('moscow-city-b', Offset(492, 130)),
  ],
  decor: <WorldStage, List<CityDecor>>{
    WorldStage.village: _decorBVillage,
    WorldStage.town: _decorBTown,
    WorldStage.moscow: _decorBMoscow,
  },
);

// Свободные клетки травы B (центр): (0,0) 320,88 · (1,1) 320,152 ·
// (3,0) 512,184 · (1,4) 128,248 · (3,3) 320,280 · (4,3) 384,312 — площадь
// у Дома · (4,4) 320,344. Перекрёсток (2,2) — 320,216. Плюс опушка вне поля.
const List<CityDecor> _edgeB = <CityDecor>[
  // Опушка за полем: слева-сверху и справа-сверху.
  CityDecor(DecorKind.tree, 40, 120),
  CityDecor(DecorKind.tree, 96, 92),
  CityDecor(DecorKind.bush, 190, 50),
  CityDecor(DecorKind.tree, 600, 120),
  CityDecor(DecorKind.tree, 546, 92),
  CityDecor(DecorKind.bush, 452, 50),
  // Снизу-слева и снизу-справа, перед полем.
  CityDecor(DecorKind.bush, 70, 350),
  CityDecor(DecorKind.tree, 150, 380),
  CityDecor(DecorKind.bush, 572, 350),
  CityDecor(DecorKind.tree, 494, 380),
];

const List<CityDecor> _decorBVillage = <CityDecor>[
  ..._edgeB,
  CityDecor(DecorKind.tree, 320, 100),
  CityDecor(DecorKind.flowers, 304, 160),
  CityDecor(DecorKind.bush, 338, 172),
  CityDecor(DecorKind.fenceDown, 494, 152),
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
  CityDecor(DecorKind.lamp, 128, 186),
  CityDecor(DecorKind.lamp, 512, 250),
];
