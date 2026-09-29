import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Настоящие директивы импорта, без комментариев и строк в коде.
List<String> _imports(String src) => src
    .split('\n')
    .map((String l) => l.trim())
    .where((String l) => l.startsWith('import ') || l.startsWith('export '))
    .toList();

List<String> _offenders(String dir, bool Function(String directive) bad) {
  final List<String> out = <String>[];
  for (final FileSystemEntity f in Directory(dir).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (_imports(f.readAsStringSync()).any(bad)) out.add(f.path);
  }
  return out;
}

void main() {
  test('домен не знает про Flutter', () {
    final List<String> offenders = _offenders(
      'lib/domain',
      (String d) => d.contains('package:flutter/'),
    );
    expect(offenders, isEmpty,
        reason: 'Слои расползаются к пятому дню спринта, если это не '
            'проверяется машиной. Вынеси логику из виджета или наоборот:\n'
            '${offenders.join('\n')}');
  });

  test('в домене нет обращений к файловой системе и сети', () {
    final List<String> offenders = _offenders(
      'lib/domain',
      (String d) => d.contains('dart:io') || d.contains('dart:html'),
    );
    expect(offenders, isEmpty,
        reason: 'Чтение файлов живёт в lib/data, иначе домен нельзя '
            'прогнать без устройства:\n${offenders.join('\n')}');
  });

  test('экраны не лезут в хранилище напрямую', () {
    final List<String> offenders = _offenders(
      'lib/features',
      (String d) => d.contains('dart:io') || d.contains('path_provider'),
    );
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
