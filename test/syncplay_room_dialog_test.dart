import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SyncPlay join dialog requires both room number and username', () {
    final source = File('lib/pages/player/player_item.dart').readAsStringSync();

    expect(
      source,
      contains("playerController.syncplay.syncplayRoom != ''"),
    );
    expect(source, contains("isSwitchingRoom ? '切换房间' : '加入房间'"));
    expect(source, contains("labelText: '房间号'"));
    expect(source, contains("labelText: '用户名'"));
    expect(source, contains('房间号需要6到10位数字'));
    expect(source, contains('用户名必须为4到12位英文字符'));
    expect(source, isNot(contains('generateSyncPlayUsername')));
  });

  test('SyncPlay menus hide disconnect action before joining a room', () {
    final files = <String>[
      'lib/pages/player/player_item_panel.dart',
      'lib/pages/player/smallest_player_item_panel.dart',
    ];

    for (final file in files) {
      final source = File(file).readAsStringSync();
      final compactSource = source.replaceAll(RegExp(r'\s+'), '');

      expect(source, contains('Text("断开连接")'));
      expect(
        compactSource,
        contains(
          'playerController.syncplay.syncplayRoom==\'\'?"加入房间":"切换房间"',
        ),
        reason:
            '$file should label the room action as switching after joining.',
      );
      expect(
        source,
        contains("if (playerController.syncplay.syncplayRoom != '')"),
        reason:
            '$file should guard the disconnect action by joined room state.',
      );
    }
  });
}
