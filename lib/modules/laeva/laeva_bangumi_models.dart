import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/roads/road_module.dart';

const String laevaBangumiSourceName = 'LaevaBangumi';

class LaevaBangumiMetadata {
  static const String _prefix = 'laeva-bangumi:';

  static String encodeId(int id) => '$_prefix$id';

  static bool isLaevaItem(BangumiItem item) => item.info.startsWith(_prefix);

  static int apiIdFromItem(BangumiItem item) {
    if (!isLaevaItem(item)) {
      return item.id;
    }
    final parsed = int.tryParse(item.info.substring(_prefix.length));
    return parsed ?? item.id;
  }
}

class LaevaBangumiSearchItem {
  LaevaBangumiSearchItem({
    required this.id,
    required this.title,
    required this.coverUrl,
  });

  factory LaevaBangumiSearchItem.fromJson(Map<String, dynamic> json) {
    return LaevaBangumiSearchItem(
      id: _parseInt(json['id']) ?? 0,
      title: _string(json['title']),
      coverUrl: _string(json['coverUrl']),
    );
  }

  final int id;
  final String title;
  final String coverUrl;

  BangumiItem toBangumiItem() {
    return BangumiItem(
      id: id,
      type: 2,
      name: title,
      nameCn: title,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: _imageMap(coverUrl),
      tags: [],
      alias: [],
      ratingScore: 0.0,
      votes: 0,
      votesCount: [],
      info: LaevaBangumiMetadata.encodeId(id),
    );
  }
}

class LaevaBangumiUpdateItem {
  LaevaBangumiUpdateItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.summary,
    required this.latestEp,
    required this.latestEpisode,
    required this.updatedAt,
  });

  factory LaevaBangumiUpdateItem.fromJson(Map<String, dynamic> json) {
    return LaevaBangumiUpdateItem(
      id: _parseInt(json['id']) ?? 0,
      title: _string(json['title']),
      coverUrl: _nullableString(json['coverUrl']),
      summary: _nullableString(json['summary']),
      latestEp: _parseInt(json['latestEp']),
      latestEpisode: _nullableString(json['latestEpisode']),
      updatedAt: _nullableString(json['updatedAt']),
    );
  }

  final int id;
  final String title;
  final String? coverUrl;
  final String? summary;
  final int? latestEp;
  final String? latestEpisode;
  final String? updatedAt;

  BangumiItem toBangumiItem() {
    return BangumiItem(
      id: id,
      type: 2,
      name: title,
      nameCn: title,
      summary: summary ?? '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: _imageMap(coverUrl ?? ''),
      tags: [],
      alias: [],
      ratingScore: 0.0,
      votes: 0,
      votesCount: [],
      info: LaevaBangumiMetadata.encodeId(id),
    );
  }
}

class LaevaBangumiCalendarDay {
  LaevaBangumiCalendarDay({
    required this.weekdayId,
    required this.items,
  });

  factory LaevaBangumiCalendarDay.fromJson(Map<String, dynamic> json) {
    final weekday = json['weekday'];
    return LaevaBangumiCalendarDay(
      weekdayId: weekday is Map ? _parseInt(weekday['id']) ?? 0 : 0,
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => LaevaBangumiCalendarItem.fromJson(
                Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  final int weekdayId;
  final List<LaevaBangumiCalendarItem> items;

  List<BangumiItem> toBangumiItems() {
    return items.map((item) => item.toBangumiItem(weekdayId)).toList();
  }
}

class LaevaBangumiCalendarItem {
  LaevaBangumiCalendarItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.ratingScore,
    required this.eps,
    required this.totalEpisodes,
    required this.latestEp,
    required this.lastUpdated,
    required this.airDate,
  });

  factory LaevaBangumiCalendarItem.fromJson(Map<String, dynamic> json) {
    return LaevaBangumiCalendarItem(
      id: _parseInt(json['id']) ?? 0,
      title: _string(json['title']),
      coverUrl: _nullableString(json['coverUrl']),
      ratingScore: _parseDouble(json['ratingScore']),
      eps: _parseInt(json['eps']),
      totalEpisodes: _parseInt(json['totalEpisodes']),
      latestEp: _parseInt(json['latestEp']),
      lastUpdated: _nullableString(json['lastUpdated']),
      airDate: _nullableString(json['airDate']),
    );
  }

  final int id;
  final String title;
  final String? coverUrl;
  final double? ratingScore;
  final int? eps;
  final int? totalEpisodes;
  final int? latestEp;
  final String? lastUpdated;
  final String? airDate;

  BangumiItem toBangumiItem(int weekdayId) {
    return BangumiItem(
      id: id,
      type: 2,
      name: title,
      nameCn: title,
      summary: latestEp == null ? '' : '更新至第$latestEp集',
      airDate: airDate ?? '',
      airWeekday: weekdayId,
      rank: 0,
      images: _imageMap(coverUrl ?? ''),
      tags: [],
      alias: [],
      ratingScore: ratingScore ?? 0.0,
      votes: 0,
      votesCount: [],
      info: LaevaBangumiMetadata.encodeId(id),
    );
  }
}

class LaevaBangumiDetail {
  LaevaBangumiDetail({
    required this.id,
    required this.title,
    required this.summary,
    required this.coverUrl,
    required this.eps,
    required this.totalEpisodes,
    required this.airDate,
    required this.platform,
    required this.ratingScore,
    required this.rank,
    required this.votes,
    required this.votesCount,
    required this.tags,
    required this.channels,
  });

  factory LaevaBangumiDetail.fromJson(Map<String, dynamic> json) {
    return LaevaBangumiDetail(
      id: _parseInt(json['id']) ?? 0,
      title: _string(json['title']),
      summary: _string(json['summary']),
      coverUrl: _nullableString(json['coverUrl']),
      eps: _parseInt(json['eps']),
      totalEpisodes: _parseInt(json['totalEpisodes']),
      airDate: _nullableString(json['airDate']),
      platform: _nullableString(json['platform']),
      ratingScore: _parseDouble(json['ratingScore']),
      rank: _parseInt(json['rank']),
      votes: _parseInt(json['votes']) ?? 0,
      votesCount: (json['votesCount'] as List<dynamic>? ?? const [])
          .map((value) => _parseInt(value) ?? 0)
          .toList(),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map(_parseBangumiTag)
          .where((tag) => tag.name.isNotEmpty)
          .toList(),
      channels: (json['channels'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                LaevaBangumiChannel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  final int id;
  final String title;
  final String summary;
  final String? coverUrl;
  final int? eps;
  final int? totalEpisodes;
  final String? airDate;
  final String? platform;
  final double? ratingScore;
  final int? rank;
  final int votes;
  final List<int> votesCount;
  final List<BangumiTag> tags;
  final List<LaevaBangumiChannel> channels;

  bool get hasPlayableEpisodes =>
      channels.any((channel) => channel.episodes.isNotEmpty);

  List<Road> toRoads() {
    return channels
        .map(
          (channel) => Road(
            name: channel.name,
            data: channel.episodes.map((episode) => episode.playUrl).toList(),
            identifier:
                channel.episodes.map((episode) => episode.name).toList(),
          ),
        )
        .where((road) => road.data.isNotEmpty)
        .toList();
  }

  void applyToBangumiItem(BangumiItem item) {
    item.name = title;
    item.nameCn = title;
    item.summary = summary;
    item.airDate = airDate ?? '';
    item.rank = rank ?? 0;
    item.images = _imageMap(coverUrl ?? '');
    item.tags = tags;
    item.ratingScore = ratingScore ?? 0.0;
    item.votes = votes;
    item.votesCount = votesCount;
    item.info = LaevaBangumiMetadata.encodeId(id);
  }
}

class LaevaBangumiChannel {
  LaevaBangumiChannel({
    required this.name,
    required this.sourceAid,
    required this.episodes,
  });

  factory LaevaBangumiChannel.fromJson(Map<String, dynamic> json) {
    return LaevaBangumiChannel(
      name: _string(json['name'], fallback: '播放线路'),
      sourceAid: _parseInt(json['sourceAid']),
      episodes: (json['episodes'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                LaevaBangumiEpisode.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  final String name;
  final int? sourceAid;
  final List<LaevaBangumiEpisode> episodes;
}

class LaevaBangumiEpisode {
  LaevaBangumiEpisode({
    required this.name,
    required this.playUrl,
    required this.index,
  });

  factory LaevaBangumiEpisode.fromJson(Map<String, dynamic> json) {
    return LaevaBangumiEpisode(
      name: _string(json['name'], fallback: '未命名剧集'),
      playUrl: _string(json['playUrl']),
      index: _parseInt(json['index']) ?? 0,
    );
  }

  final String name;
  final String playUrl;
  final int index;
}

class LaevaBangumiPlayData {
  LaevaBangumiPlayData({required this.videoUrl, required this.directPlay});

  factory LaevaBangumiPlayData.fromJson(Map<String, dynamic> json) {
    return LaevaBangumiPlayData(
      videoUrl: _string(json['videoUrl']),
      directPlay: json['directPlay'] == true,
    );
  }

  final String videoUrl;
  final bool directPlay;
}

Map<String, String> _imageMap(String coverUrl) {
  return {
    'large': coverUrl,
    'common': coverUrl,
    'medium': coverUrl,
    'small': coverUrl,
    'grid': coverUrl,
  };
}

String _string(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _nullableString(dynamic value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

BangumiTag _parseBangumiTag(dynamic value) {
  if (value is Map) {
    final json = Map<String, dynamic>.from(value);
    return BangumiTag(
      name: _string(json['name']),
      count: _parseInt(json['count']) ?? 0,
      totalCount: _parseInt(json['totalCount']) ?? 0,
    );
  }
  return BangumiTag(name: _string(value), count: 0, totalCount: 0);
}
