import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player settings no longer owns SyncPlay endpoint configuration', () {
    final source =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();

    expect(source, isNot(contains('SyncPlayEndPointSettingsTile')));
    expect(source, isNot(contains('syncPlayEndPoint')));
    expect(source, isNot(contains('一起看服务器')));
  });
}
