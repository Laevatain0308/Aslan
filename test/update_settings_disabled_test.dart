import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('about settings hide app update controls until release strategy exists',
      () {
    final source = File('lib/pages/about/about_page.dart').readAsStringSync();

    expect(source, isNot(contains('应用更新')));
    expect(source, isNot(contains('自动更新')));
    expect(source, isNot(contains('检查更新')));
    expect(source, isNot(contains('SettingBoxKey.autoUpdate')));
  });

  test('automatic update checks default to disabled', () {
    final startupSource = File('lib/pages/init_page.dart').readAsStringSync();
    final updaterSource =
        File('lib/services/update/auto_updater.dart').readAsStringSync();

    expect(
      startupSource,
      contains('SettingBoxKey.autoUpdate, defaultValue: false'),
    );
    expect(
      updaterSource,
      contains('SettingBoxKey.autoUpdate, defaultValue: false'),
    );
  });

  test('automatic updater service is hard-disabled', () {
    final updaterSource =
        File('lib/services/update/auto_updater.dart').readAsStringSync();
    final autoCheckSource = updaterSource.substring(
      updaterSource.indexOf('Future<void> autoCheckForUpdates() async'),
      updaterSource.indexOf('  /// 手动检查更新'),
    );

    expect(autoCheckSource,
        contains('setting.put(SettingBoxKey.autoUpdate, false)'));
    expect(autoCheckSource, isNot(contains('checkForUpdates()')));
    expect(autoCheckSource, isNot(contains('_showUpdateDialog')));
  });
}
