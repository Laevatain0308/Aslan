import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/laeva/laeva_bangumi_models.dart';

void main() {
  group('LaevaBangumiDetail episode mapping', () {
    test('maps actual API episode numbers to playlist positions', () {
      final detail = _detail([
        _episode(name: '第0话', index: 0, playUrl: '/api/play?id=1&ch=1&ep=0'),
        _episode(name: '第1话', index: 1, playUrl: '/api/play?id=1&ch=1&ep=1'),
        _episode(name: '第3话', index: 3, playUrl: '/api/play?id=1&ch=1&ep=3'),
      ]);

      expect(
        detail.episodePositionForActualEpisode(road: 0, actualEpisode: 3),
        3,
      );
    });

    test(
        'clamps unknown actual episode numbers to an existing playlist position',
        () {
      final detail = _detail([
        _episode(name: '第1话', index: 1, playUrl: '/api/play?id=1&ch=1&ep=1'),
        _episode(name: '第2话', index: 2, playUrl: '/api/play?id=1&ch=1&ep=2'),
      ]);

      expect(
        detail.episodePositionForActualEpisode(road: 0, actualEpisode: 99),
        2,
      );
    });
  });
}

LaevaBangumiDetail _detail(List<LaevaBangumiEpisode> episodes) {
  return LaevaBangumiDetail(
    id: 1,
    title: 'subject',
    name: null,
    nameCn: null,
    summary: '',
    coverUrl: null,
    eps: null,
    totalEpisodes: null,
    airDate: null,
    airWeekday: null,
    platform: null,
    ratingScore: null,
    rank: null,
    votes: 0,
    votesCount: const [],
    tags: const [],
    aliases: const [],
    channels: [
      LaevaBangumiChannel(
        id: 'channel',
        name: '线路',
        source: null,
        sourceAid: null,
        resourceTitle: null,
        episodes: episodes,
      ),
    ],
  );
}

LaevaBangumiEpisode _episode({
  required String name,
  required int index,
  required String playUrl,
}) {
  return LaevaBangumiEpisode(
    name: name,
    playUrl: playUrl,
    index: index,
    sourceIndex: null,
    updatedAt: null,
  );
}
