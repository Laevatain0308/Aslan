import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/laeva/laeva_bangumi_sort.dart';

void main() {
  group('LaevaBangumi sorting', () {
    test('sorts by air date descending for time sort', () {
      final sorted = sortLaevaBangumiItems([
        _item(1, airDate: '2024-01-01'),
        _item(2, airDate: '2026-04-01'),
        _item(3, airDate: '2025-07-01'),
      ], sort: 'time');

      expect(sorted.map((item) => item.id), [2, 3, 1]);
    });

    test('sorts mixed air date formats on the same timeline', () {
      final sorted = sortLaevaBangumiItems([
        _item(1, airDate: '2025年'),
        _item(2, airDate: '2024-12-31'),
        _item(3, airDate: '2026-01-01'),
      ], sort: 'time');

      expect(sorted.map((item) => item.id), [3, 1, 2]);
    });

    test('sorts by rating score descending for score sort', () {
      final sorted = sortLaevaBangumiItems([
        _item(1, ratingScore: 6.8),
        _item(2, ratingScore: 8.2),
        _item(3, ratingScore: 7.6),
      ], sort: 'score');

      expect(sorted.map((item) => item.id), [2, 3, 1]);
    });

    test('sorts by vote total descending for heat sort', () {
      final sorted = sortLaevaBangumiItems([
        _item(1, votes: 120),
        _item(2, votes: 560),
        _item(3, votes: 300),
      ], sort: 'heat');

      expect(sorted.map((item) => item.id), [2, 3, 1]);
    });
  });
}

BangumiItem _item(
  int id, {
  String airDate = '',
  double ratingScore = 0,
  int votes = 0,
}) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'item$id',
    nameCn: 'item$id',
    summary: '',
    airDate: airDate,
    airWeekday: 0,
    rank: 0,
    images: const {},
    tags: const [],
    alias: const [],
    ratingScore: ratingScore,
    votes: votes,
    votesCount: const [],
    info: '',
  );
}
