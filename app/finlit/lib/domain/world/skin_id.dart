/// id варианта предмета комнаты — `<предмет>__<код><плитка>`
/// (`skin_cabinet__20b`, `decor_globe__35a`).
library;

/// Предмет, чей это вид (`skin_cabinet__20b` → `skin_cabinet`); не вариант —
/// null.
String? skinObject(String id) {
  final int i = id.indexOf('__');
  return i <= 0 ? null : id.substring(0, i);
}
