import 'dart:io';

import 'package:finlit/features/settings/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Protects: the version a child and an expert see in Settings / "About"
/// ([SettingsScreen.version], hard-coded on purpose) is the versionName the
/// APK is built with (`pubspec.yaml` -> `version: <name>+<build>`), and the
/// build number stays above the builds already handed out (0.1.4+5), so
/// the new APK installs over it as an update.
/// Fails when: pubspec is bumped and the constant is not (or the other way
/// round); the build number is left at 5 or lower.
void main() {
  test('pubspec version = version in Settings, build number above 5', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? m =
        RegExp(r'^version:\s*([0-9.]+)\+([0-9]+)\s*$', multiLine: true)
            .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml: no "version: X.Y.Z+N" line');
    expect(SettingsScreen.version, m!.group(1),
        reason: 'SettingsScreen.version and pubspec versionName differ');
    expect(int.parse(m.group(2)!), greaterThan(5),
        reason: 'build number must be above 0.1.4+5 (installs as an update)');
  });
}
