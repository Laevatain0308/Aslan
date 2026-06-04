import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync settings copy avoids implementation names', () {
    final files = [
      File('lib/pages/settings/server_settings.dart'),
      File('lib/pages/my/my_page.dart'),
      File('lib/request/apis/private_sync_api.dart'),
    ];
    final copy = files.map((file) => file.readAsStringSync()).join('\n');

    expect(copy, isNot(contains('私有同步')));
    expect(copy, isNot(contains('LaevaBangumi 后端')));
  });
}
