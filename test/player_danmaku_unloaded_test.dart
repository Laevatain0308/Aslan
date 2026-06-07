import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/syncplay_client.dart';
import 'package:kazumi/utils/constants.dart';

void main() {
  group('player danmaku runtime wiring', () {
    test('player runtime files do not import or call danmaku components', () {
      final files = <String>[
        'lib/pages/player/player_controller.dart',
        'lib/pages/player/player_item.dart',
        'lib/pages/video/video_controller.dart',
      ];

      for (final file in files) {
        final source = File(file).readAsStringSync();

        expect(
          source,
          isNot(contains('player_danmaku_controller.dart')),
          reason: '$file should not import the retained danmaku controller.',
        );
        expect(
          source,
          isNot(contains('canvas_danmaku')),
          reason: '$file should not import the danmaku canvas package.',
        );
        expect(
          source,
          isNot(contains('PlayerDanmakuController')),
          reason: '$file should not create player danmaku controllers.',
        );
        expect(
          source,
          isNot(contains('playerController.danmaku')),
          reason: '$file should not call player danmaku APIs.',
        );
        expect(
          source,
          isNot(contains('DanmakuScreen')),
          reason: '$file should not mount a danmaku canvas in the player.',
        );
      }
    });

    test('player shortcuts do not expose danmaku toggle', () {
      expect(defaultShortcuts, isNot(contains('toggledanmaku')));
      expect(shortcutsChineseName, isNot(contains('toggledanmaku')));
    });

    test('picture-in-picture actions do not expose danmaku toggle', () {
      final files = <String>[
        'lib/pages/player/player_item.dart',
        'lib/pages/player/player_item_panel.dart',
        'lib/pages/player/smallest_player_item_panel.dart',
        'lib/services/player/pip_utils.dart',
        'android/app/src/main/kotlin/com/example/kazumi/MainActivity.kt',
        'macos/Runner/AppDelegate.swift',
        'macos/Runner/Base.lproj/MainMenu.xib',
        'macos/Runner/zh-Hans.lproj/MainMenu.strings',
      ];

      for (final file in files) {
        final source = File(file).readAsStringSync();

        expect(source, isNot(contains('toggle_danmaku')));
        expect(source, isNot(contains('actionPipToggleDanmaku')));
        expect(source, isNot(contains('danmakuEnabled')));
        expect(source, isNot(contains('danmakuSupported')));
        expect(source, isNot(contains('menuToggleDanmaku')));
        expect(source, isNot(contains('toggledanmaku')));
        expect(source, isNot(contains('Toggle Danmaku')));
        expect(source, isNot(contains('弹幕开关')));
      }
    });

    test('syncplay runtime does not expose chat while danmaku is disabled', () {
      final files = <String>[
        'lib/services/player/syncplay_client.dart',
        'lib/pages/player/controller/player_syncplay_controller.dart',
        'lib/pages/player/player_controller.dart',
        'lib/pages/video/video_page.dart',
        'lib/pages/player/controller/player_models.dart',
      ];

      for (final file in files) {
        final source = File(file).readAsStringSync();

        expect(source, isNot(contains('ChatMessage')));
        expect(source, isNot(contains('sendChatMessage')));
        expect(source, isNot(contains('onChatMessage')));
        expect(source, isNot(contains('chatStream')));
        expect(source, isNot(contains('SyncPlayChatMessage')));
        expect(source, isNot(contains('_syncChatSubscription')));
        expect(source, isNot(contains('chatRoom')));
      }
    });

    test('syncplay handshake does not advertise chat support', () {
      final json = HelloMessage(
        username: 'aslan',
        version: '1.7.0',
        room: '123456',
      ).toJson();

      expect(json['Hello']['features']['chat'], isFalse);
    });
  });
}
