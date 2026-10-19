/// Скины предметов комнаты (Денис 29.09): у кровати, стола, тумбочки и
/// вещей вроде глобуса в комнате один предмет, а купленный вариант — его
/// вид. id варианта — `<предмет>__<код><плитка>` (`skin_cabinet__20b`,
/// `decor_globe__35a`), цены и названия — `economy.json → decor`.
library;

import '../../../domain/world/skin_id.dart';

export '../../../domain/world/skin_id.dart' show skinObject;

/// Карточка магазина: все цвета одного кода (`skin_cabinet__20b` →
/// `skin_cabinet__20`). Не скин — сам id.
String skinFamily(String id) {
  if (skinObject(id) == null) return id;
  final int last = id.codeUnitAt(id.length - 1);
  final bool letter = last >= 0x61 && last <= 0x7a;
  return letter ? id.substring(0, id.length - 1) : id;
}

/// Слот общей раскладки комнаты для мебели-скина.
const Map<String, String> skinSlots = <String, String>{
  'skin_bed': 'bed',
  'skin_desk': 'desk_chair',
  'skin_cabinet': 'bedside_cabinet',
};

/// Что надето: предмет → id варианта. Последний купленный, если ребёнок не
/// выбрал другой из купленных ([chosen] — `ResourceSnapshot.chosenSkins`,
/// из журнала).
Map<String, String> equippedSkins(
    Iterable<String> owned, Map<String, String> chosen) {
  final Map<String, String> out = <String, String>{};
  for (final String id in owned) {
    final String? o = skinObject(id);
    if (o != null) out[o] = id;
  }
  final Set<String> have = owned.toSet();
  for (final MapEntry<String, String> e in chosen.entries) {
    if (have.contains(e.value)) out[e.key] = e.value;
  }
  return out;
}

/// Мебель-скины по слоту раскладки (`bed` → `skin_bed__4a`).
Map<String, String> furnitureSkins(Map<String, String> equipped) =>
    <String, String>{
      for (final MapEntry<String, String> e in equipped.entries)
        if (skinSlots[e.key] case final String slot) slot: e.value,
    };
