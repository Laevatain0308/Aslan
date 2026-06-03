import 'package:kazumi/modules/bangumi/bangumi_item.dart';

int _airDateValue(BangumiItem item) {
  final text = item.airDate.trim();
  if (text.isEmpty) return 0;
  final date = DateTime.tryParse(text);
  if (date != null) return date.millisecondsSinceEpoch;
  final match =
      RegExp(r'(\d{4})(?:\D+(\d{1,2}))?(?:\D+(\d{1,2}))?').firstMatch(text);
  if (match == null) return 0;
  final year = int.parse(match.group(1)!);
  final month = int.tryParse(match.group(2) ?? '') ?? 1;
  final day = int.tryParse(match.group(3) ?? '') ?? 1;
  if (month < 1 || month > 12 || day < 1 || day > 31) return 0;
  return DateTime(year, month, day).millisecondsSinceEpoch;
}

int _compareNumDesc(num a, num b) => b.compareTo(a);

List<BangumiItem> sortLaevaBangumiItems(
  Iterable<BangumiItem> items, {
  required String sort,
}) {
  final result = items.toList();
  result.sort((a, b) {
    final primary = switch (sort.toLowerCase()) {
      'heat' => _compareNumDesc(a.votes, b.votes),
      'score' || 'rank' => _compareNumDesc(a.ratingScore, b.ratingScore),
      _ => _compareNumDesc(_airDateValue(a), _airDateValue(b)),
    };
    if (primary != 0) return primary;
    return a.id.compareTo(b.id);
  });
  return result;
}
