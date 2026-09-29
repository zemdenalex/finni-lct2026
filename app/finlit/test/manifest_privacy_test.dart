import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// §3.5: «данные только на устройстве». Без этих атрибутов Android сам кладёт
// файл профиля в облачную резервную копию Google — приложение ничего не
// отправляет, а данные всё равно уезжают.
void main() {
  test('резервная копия и перенос данных выключены в манифесте', () {
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    final String rules =
        File('android/app/src/main/res/xml/data_extraction_rules.xml')
            .readAsStringSync();
    expect(rules, contains('<cloud-backup>'));
    expect(rules, contains('<device-transfer>'));
    expect(manifest, isNot(contains('android.permission.INTERNET')),
        reason: 'в релизном манифесте сети нет');
  });
}
