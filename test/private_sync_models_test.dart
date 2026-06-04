import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/sync/private_sync_models.dart';

void main() {
  group('PrivateSyncVersion', () {
    test('uses Kazumi-compatible lexicographic ordering', () {
      expect(
        PrivateSyncVersion.of(updatedAt: 42, eventId: 'device-a:1'),
        '0000000000000042|device-a:1',
      );
      expect(
        PrivateSyncVersion.of(updatedAt: 1000, eventId: 'b').compareTo(
          PrivateSyncVersion.of(updatedAt: 1000, eventId: 'a'),
        ),
        greaterThan(0),
      );
    });
  });

  group('PrivateSyncEvent', () {
    test('encodes watch upsert events for LaevaBangumi merge API', () {
      final event = PrivateSyncEvent.watchUpsert(
        eventId: 'device-a:1',
        deviceId: 'device-a',
        seq: 1,
        updatedAt: 1000,
        entityKey: 'LaevaBangumi1',
        adapterName: 'LaevaBangumi',
        bangumiItem: _item(1),
        episode: 2,
        lastWatchEpisode: 3,
        road: 0,
        progressMs: 12000,
        lastSrc: 'https://example.invalid/1',
        lastWatchEpisodeName: 'EP2',
      );

      final json = event.toJson();

      expect(json['domain'], 'watch');
      expect(json['op'], 'watch.upsertProgress');
      expect(json['updatedAt'], 1000);
      expect(json['entityKey'], 'LaevaBangumi1');
      expect(json['bangumiId'], 1);
      expect((json['payload'] as Map)['progressMs'], 12000);
      expect((json['payload'] as Map)['lastWatchEpisode'], 3);
      expect(
          ((json['payload'] as Map)['bangumiItem'] as Map)['nameCn'], '条目 1');
    });

    test('encodes collection upsert events', () {
      final event = PrivateSyncEvent.collectionUpsert(
        eventId: 'device-a:2',
        deviceId: 'device-a',
        seq: 2,
        updatedAt: 2000,
        bangumiItem: _item(2),
        type: 1,
        collectedAt: 1500,
      );

      final json = event.toJson();

      expect(json['domain'], 'collection');
      expect(json['op'], 'collection.upsert');
      expect(json['bangumiId'], 2);
      expect((json['payload'] as Map)['type'], 1);
      expect((json['payload'] as Map)['collectedAt'], 1500);
    });
  });

  group('PrivateSyncSnapshot', () {
    test('parses watch and collection snapshots', () {
      final snapshot = PrivateSyncSnapshot.fromJson({
        'generatedAt': 3000,
        'watch': {
          'clearVersion': null,
          'histories': [
            {
              'entityKey': 'LaevaBangumi1',
              'bangumiId': 1,
              'adapterName': 'LaevaBangumi',
              'lastWatchEpisode': 2,
              'lastWatchTime': 2000,
              'lastSrc': 'https://example.invalid/1',
              'lastWatchEpisodeName': 'EP2',
              'bangumiItem': PrivateSyncBangumiCodec.toJson(_item(1)),
              'itemVersion': '0000000000002000|device-a:1',
              'progresses': {
                '2': {
                  'episode': 2,
                  'road': 0,
                  'progressMs': 12000,
                  'version': '0000000000002000|device-a:1',
                }
              },
            }
          ],
        },
        'collection': {
          'clearVersion': null,
          'items': [
            {
              'bangumiId': 1,
              'type': 1,
              'collectedAt': 1500,
              'updatedAt': 2000,
              'bangumiItem': PrivateSyncBangumiCodec.toJson(_item(1)),
              'itemVersion': '0000000000002000|device-a:2',
            }
          ],
        },
      });

      expect(snapshot.generatedAt, 3000);
      expect(snapshot.watch.histories.single.lastWatchEpisode, 2);
      expect(snapshot.watch.histories.single.progresses[2]!.progressMs, 12000);
      expect(snapshot.collection.items.single.type, 1);
      expect(snapshot.collection.items.single.bangumiItem.id, 1);
    });
  });
}

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const <BangumiTag>[],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}
