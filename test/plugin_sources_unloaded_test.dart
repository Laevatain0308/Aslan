import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('plugin source runtime wiring', () {
    test('startup does not initialize or update plugin sources by default', () {
      final source = File('lib/pages/init_page.dart').readAsStringSync();

      expect(source, isNot(contains('PluginsController')));
      expect(source, isNot(contains('pluginsController.init')));
      expect(source, isNot(contains('queryPluginHTTPList')));
      expect(source, isNot(contains('KazumiRules')));
    });

    test('settings routes hide retained plugin editor by default', () {
      final source =
          File('lib/pages/settings/settings_module.dart').readAsStringSync();

      expect(source, isNot(contains('PluginModule')));
      expect(source, isNot(contains('"/plugin"')));
      expect(source, contains('AppFeatureFlags.pluginSources'));
      expect(source, contains('DownloadModule'));
    });

    test(
        'index module does not bind plugin controller unless feature is enabled',
        () {
      final source = File('lib/pages/index_module.dart').readAsStringSync();

      expect(source, contains('if (AppFeatureFlags.pluginSources)'));
      expect(source, contains('PluginsController.new'));
    });

    test('download page entry is hidden while plugin sources are disabled', () {
      final source = File('lib/pages/my/my_page.dart').readAsStringSync();

      expect(source, contains('if (AppFeatureFlags.pluginSources)'));
      expect(source, contains('/settings/download/'));
      expect(source, contains('/settings/download-settings'));
    });

    test('download resolver does not touch plugin runtime when disabled', () {
      final source = File('lib/pages/download/download_controller.dart')
          .readAsStringSync();

      expect(source, contains('if (!AppFeatureFlags.pluginSources)'));
      expect(source, contains('return null;'));
      expect(source, contains('WebViewVideoSourceService'));
    });

    test('history card resumes playback through API source, not plugins', () {
      final source =
          File('lib/bean/card/bangumi_history_card.dart').readAsStringSync();

      expect(source, isNot(contains('PluginsController')));
      expect(source, isNot(contains('Plugin plugin')));
      expect(source, isNot(contains('queryRoads')));
      expect(source, contains('initLaevaSource'));
    });
  });
}
