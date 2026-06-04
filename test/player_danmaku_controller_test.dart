import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';

void main() {
  group('PlayerDanmakuController', () {
    test('ignores canvas operations before the screen creates a controller', () {
      final controller = PlayerDanmakuController(
        setting: _MemorySettings(),
        isLocalPlayback: () => false,
      );

      expect(controller.hasCanvasController, isFalse);
      expect(controller.pauseCanvas, returnsNormally);
      expect(controller.resumeCanvas, returnsNormally);
      expect(controller.clearCanvas, returnsNormally);
      expect(() => controller.updateDanmakuSpeed(1.0), returnsNormally);
      expect(controller.clearAndInvalidateScheduledDanmakus, returnsNormally);
      expect(controller.scheduledDanmakuGeneration, 1);
    });
  });
}

class _MemorySettings extends Box<dynamic> {
  final Map<dynamic, dynamic> _values = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) {
    return _values.containsKey(key) ? _values[key] : defaultValue;
  }

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
