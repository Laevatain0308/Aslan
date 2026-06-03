import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/laeva/laeva_bangumi_models.dart';
import 'package:kazumi/request/config/api_endpoints.dart';

void main() {
  group('LaevaBangumi', () {
    test('uses the www.laevatain.top API as the default server', () {
      expect(
        ApiEndpoints.laevaBangumiDefaultApiBase,
        'https://www.laevatain.top/anime/api',
      );
    });

    test('uses the search result id as the Bangumi subject id', () {
      final item = LaevaBangumiSearchItem.fromJson({
        'id': 456079,
        'title': '和班上第二可爱的女孩成为朋友',
        'name': 'クラスで2番目に可愛い女の子と友だちになった',
        'nameCn': '和班上第二可爱的女孩成为朋友',
        'coverUrl': 'https://img.laevatain.top/cover/456079.jpg',
        'summary': '搜索简介',
        'airDate': '2026-04-01',
        'airWeekday': 3,
        'platform': 'TV',
        'eps': 12,
        'totalEpisodes': 12,
        'ratingScore': 7.1,
        'rank': 1234,
        'votes': 420,
        'votesCount': [1, 2, 3],
        'tags': [
          {'name': '恋爱', 'count': 20, 'totalCount': 30},
        ],
      });

      final bangumiItem = item.toBangumiItem();

      expect(item.id, 456079);
      expect(item.name, 'クラスで2番目に可愛い女の子と友だちになった');
      expect(item.nameCn, '和班上第二可爱的女孩成为朋友');
      expect(item.ratingScore, 7.1);
      expect(item.votesCount, [1, 2, 3]);
      expect(item.tags.single.name, '恋爱');
      expect(bangumiItem.id, 456079);
      expect(bangumiItem.airDate, '2026-04-01');
      expect(bangumiItem.airWeekday, 3);
      expect(bangumiItem.rank, 1234);
      expect(bangumiItem.summary, '搜索简介');
      expect(bangumiItem.ratingScore, 7.1);
      expect(bangumiItem.votes, 420);
      expect(bangumiItem.votesCount, [1, 2, 3]);
      expect(bangumiItem.tags.single.name, '恋爱');
      expect(LaevaBangumiMetadata.apiIdFromItem(bangumiItem), 456079);
    });

    test('maps update items to Bangumi cards for home page', () {
      final item = LaevaBangumiUpdateItem.fromJson({
        'id': 580133,
        'title': '欺诈游戏',
        'coverUrl': 'https://img.laevatain.top/cover/580133.jpg',
        'summary': '突然届けられた1億円と謎の招待状',
        'name': 'ライアーゲーム',
        'nameCn': '欺诈游戏',
        'airDate': '2026-04-01',
        'airWeekday': 3,
        'platform': 'TV',
        'eps': 12,
        'totalEpisodes': 12,
        'ratingScore': 7.6,
        'rank': 1000,
        'votes': 420,
        'votesCount': [0, 1, 2],
        'tags': [
          {'name': '智斗', 'count': 8, 'totalCount': 12},
        ],
        'latestEp': 9,
        'latestEpisode': '更新至第09集',
        'updatedAt': '2026-06-01T16:43:24.000Z',
        'source': 'ffzy',
        'sourceAid': 123,
      });

      final bangumiItem = item.toBangumiItem();

      expect(item.id, 580133);
      expect(item.latestEpisode, '更新至第09集');
      expect(item.name, 'ライアーゲーム');
      expect(item.nameCn, '欺诈游戏');
      expect(item.ratingScore, 7.6);
      expect(item.tags.single.name, '智斗');
      expect(item.source, 'ffzy');
      expect(item.sourceAid, 123);
      expect(bangumiItem.id, 580133);
      expect(bangumiItem.nameCn, '欺诈游戏');
      expect(bangumiItem.summary, '突然届けられた1億円と謎の招待状');
      expect(LaevaBangumiMetadata.apiIdFromItem(bangumiItem), 580133);
    });

    test('maps calendar days to Laeva Bangumi timeline items', () {
      final day = LaevaBangumiCalendarDay.fromJson({
        'weekday': {
          'en': 'Tue',
          'cn': '星期二',
          'ja': '火曜日',
          'id': 2,
        },
        'items': [
          {
            'id': 377130,
            'title': '尖帽子的魔法工房',
            'name': 'とんがり帽子のアトリエ',
            'nameCn': '尖帽子的魔法工房',
            'coverUrl': 'https://img.laevatain.top/cover/377130.jpg',
            'summary': '魔法工房简介',
            'ratingScore': 7.6,
            'rank': 900,
            'votes': 300,
            'votesCount': [0, 1, 1],
            'tags': [
              {'name': '奇幻', 'count': 9, 'totalCount': 10},
            ],
            'airWeekday': 2,
            'platform': 'TV',
            'eps': 12,
            'totalEpisodes': 12,
            'latestEp': 10,
            'lastUpdated': '2026-06-01T14:57:08.000Z',
            'airDate': '2026-04-01',
          },
        ],
      });

      final bangumiItems = day.toBangumiItems();

      expect(day.weekdayId, 2);
      expect(bangumiItems, hasLength(1));
      expect(bangumiItems.single.id, 377130);
      expect(bangumiItems.single.airWeekday, 2);
      expect(bangumiItems.single.ratingScore, 7.6);
      expect(bangumiItems.single.votes, 300);
      expect(bangumiItems.single.votesCount, [0, 1, 1]);
      expect(bangumiItems.single.tags.single.name, '奇幻');
      expect(bangumiItems.single.summary, '更新至第10集');
      expect(day.items.single.name, 'とんがり帽子のアトリエ');
      expect(day.items.single.rank, 900);
      expect(day.items.single.votes, 300);
      expect(day.items.single.tags.single.name, '奇幻');
      expect(LaevaBangumiMetadata.isLaevaItem(bangumiItems.single), isTrue);
      expect(LaevaBangumiMetadata.apiIdFromItem(bangumiItems.single), 377130);
    });

    test('maps detail contract to Bangumi item and roads', () {
      final detail = LaevaBangumiDetail.fromJson({
        'id': 547888,
        'title': '中文标题',
        'name': '原名',
        'nameCn': '中文标题',
        'summary': '简介',
        'coverUrl': 'https://img.laevatain.top/cover/547888.jpg',
        'eps': 12,
        'totalEpisodes': 12,
        'airDate': '2026-04-01',
        'airWeekday': 3,
        'platform': 'TV',
        'ratingScore': 7.6,
        'rank': 1234,
        'votes': 420,
        'votesCount': [0, 0, 1, 2, 3, 10, 20, 30, 5, 1],
        'tags': [
          {'name': '原创', 'count': 10, 'totalCount': 20},
        ],
        'aliases': ['别名1', '别名2'],
        'channels': [
          {
            'id': 'ffzy:123',
            'name': '非凡资源',
            'source': 'ffzy',
            'sourceAid': 123,
            'resourceTitle': '资源站标题',
            'episodes': [
              {
                'index': 1,
                'sourceIndex': 2,
                'name': '第01集',
                'playUrl': '/anime/api/play?id=547888&ch=1&ep=1',
                'updatedAt': '2026-06-01T16:43:24.000Z',
              },
            ],
          },
        ],
      });

      final bangumiItem = LaevaBangumiSearchItem.fromJson({
        'id': 547888,
        'title': '中文标题',
        'coverUrl': '',
      }).toBangumiItem();
      detail.applyToBangumiItem(bangumiItem);

      expect(detail.channels.single.episodes.single.playUrl,
          '/anime/api/play?id=547888&ch=1&ep=1');
      expect(detail.name, '原名');
      expect(detail.nameCn, '中文标题');
      expect(detail.airWeekday, 3);
      expect(detail.aliases, ['别名1', '别名2']);
      expect(detail.channels.single.id, 'ffzy:123');
      expect(detail.channels.single.source, 'ffzy');
      expect(detail.channels.single.resourceTitle, '资源站标题');
      expect(detail.channels.single.episodes.single.sourceIndex, 2);
      expect(detail.channels.single.episodes.single.updatedAt,
          '2026-06-01T16:43:24.000Z');
      expect(detail.toRoads().single.data.single,
          '/anime/api/play?id=547888&ch=1&ep=1');
      expect(bangumiItem.votes, 420);
      expect(bangumiItem.votesCount, [0, 0, 1, 2, 3, 10, 20, 30, 5, 1]);
      expect(bangumiItem.tags.single.name, '原创');
      expect(bangumiItem.tags.single.count, 10);
      expect(bangumiItem.tags.single.totalCount, 20);
    });

    test('maps play response videoUrl without legacy casing', () {
      final playData = LaevaBangumiPlayData.fromJson({
        'videoUrl': 'https://example.invalid/1.m3u8',
        'directPlay': false,
        'headers': {'Referer': 'https://example.invalid/'},
        'expiresAt': '2026-06-03T12:00:00.000Z',
      });

      expect(playData.videoUrl, 'https://example.invalid/1.m3u8');
      expect(playData.directPlay, isFalse);
      expect(playData.headers['Referer'], 'https://example.invalid/');
      expect(playData.expiresAt, '2026-06-03T12:00:00.000Z');
    });

    test('parses API envelope metadata without requiring UI consumption', () {
      final meta = LaevaBangumiApiMeta.fromJson({
        'freshness': 'cache',
        'resourceStatus': 'ready',
        'resourceSources': [
          {
            'source': 'ffzy',
            'name': '非凡资源',
            'status': 'ready',
            'sourceAid': 123,
            'note': null,
          },
        ],
        'warnings': [],
      });

      expect(meta.freshness, 'cache');
      expect(meta.resourceStatus, 'ready');
      expect(meta.resourceSources.single.source, 'ffzy');
      expect(meta.resourceSources.single.sourceAid, 123);
    });
  });
}
