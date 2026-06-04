import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';

class PrivateSyncVersion {
  const PrivateSyncVersion._();

  static String of({
    required int updatedAt,
    required String eventId,
  }) {
    return '${updatedAt.toString().padLeft(16, '0')}|$eventId';
  }
}

class PrivateSyncEvent {
  const PrivateSyncEvent({
    required this.eventId,
    required this.deviceId,
    required this.seq,
    required this.domain,
    required this.op,
    required this.updatedAt,
    this.entityKey,
    this.bangumiId,
    required this.payload,
  });

  final String eventId;
  final String deviceId;
  final int seq;
  final String domain;
  final String op;
  final int updatedAt;
  final String? entityKey;
  final int? bangumiId;
  final Map<String, dynamic> payload;

  factory PrivateSyncEvent.watchUpsert({
    required String eventId,
    required String deviceId,
    required int seq,
    required int updatedAt,
    required String entityKey,
    required String adapterName,
    required BangumiItem bangumiItem,
    required int episode,
    required int road,
    required int progressMs,
    required String lastSrc,
    required String lastWatchEpisodeName,
  }) {
    return PrivateSyncEvent(
      eventId: eventId,
      deviceId: deviceId,
      seq: seq,
      domain: 'watch',
      op: 'watch.upsertProgress',
      updatedAt: updatedAt,
      entityKey: entityKey,
      bangumiId: bangumiItem.id,
      payload: {
        'entityKey': entityKey,
        'adapterName': adapterName,
        'bangumiId': bangumiItem.id,
        'bangumiItem': PrivateSyncBangumiCodec.toJson(bangumiItem),
        'episode': episode,
        'road': road,
        'progressMs': progressMs,
        'lastSrc': lastSrc,
        'lastWatchEpisodeName': lastWatchEpisodeName,
      },
    );
  }

  factory PrivateSyncEvent.watchDelete({
    required String eventId,
    required String deviceId,
    required int seq,
    required int updatedAt,
    required String entityKey,
  }) {
    return PrivateSyncEvent(
      eventId: eventId,
      deviceId: deviceId,
      seq: seq,
      domain: 'watch',
      op: 'watch.deleteHistory',
      updatedAt: updatedAt,
      entityKey: entityKey,
      payload: {'entityKey': entityKey},
    );
  }

  factory PrivateSyncEvent.watchClearAll({
    required String eventId,
    required String deviceId,
    required int seq,
    required int updatedAt,
  }) {
    return PrivateSyncEvent(
      eventId: eventId,
      deviceId: deviceId,
      seq: seq,
      domain: 'watch',
      op: 'watch.clearAll',
      updatedAt: updatedAt,
      payload: const {},
    );
  }

  factory PrivateSyncEvent.collectionUpsert({
    required String eventId,
    required String deviceId,
    required int seq,
    required int updatedAt,
    required BangumiItem bangumiItem,
    required int type,
    required int collectedAt,
  }) {
    return PrivateSyncEvent(
      eventId: eventId,
      deviceId: deviceId,
      seq: seq,
      domain: 'collection',
      op: 'collection.upsert',
      updatedAt: updatedAt,
      bangumiId: bangumiItem.id,
      payload: {
        'bangumiId': bangumiItem.id,
        'type': type,
        'bangumiItem': PrivateSyncBangumiCodec.toJson(bangumiItem),
        'collectedAt': collectedAt,
      },
    );
  }

  factory PrivateSyncEvent.collectionDelete({
    required String eventId,
    required String deviceId,
    required int seq,
    required int updatedAt,
    required int bangumiId,
  }) {
    return PrivateSyncEvent(
      eventId: eventId,
      deviceId: deviceId,
      seq: seq,
      domain: 'collection',
      op: 'collection.delete',
      updatedAt: updatedAt,
      bangumiId: bangumiId,
      payload: {'bangumiId': bangumiId},
    );
  }

  factory PrivateSyncEvent.collectionClearAll({
    required String eventId,
    required String deviceId,
    required int seq,
    required int updatedAt,
  }) {
    return PrivateSyncEvent(
      eventId: eventId,
      deviceId: deviceId,
      seq: seq,
      domain: 'collection',
      op: 'collection.clearAll',
      updatedAt: updatedAt,
      payload: const {},
    );
  }

  factory PrivateSyncEvent.fromJson(Map<String, dynamic> json) {
    return PrivateSyncEvent(
      eventId: json['eventId'] as String,
      deviceId: json['deviceId'] as String,
      seq: (json['seq'] as num).toInt(),
      domain: json['domain'] as String,
      op: json['op'] as String,
      updatedAt: (json['updatedAt'] as num).toInt(),
      entityKey: json['entityKey'] as String?,
      bangumiId: (json['bangumiId'] as num?)?.toInt(),
      payload: Map<String, dynamic>.from((json['payload'] as Map?) ?? const {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'deviceId': deviceId,
      'seq': seq,
      'domain': domain,
      'op': op,
      'updatedAt': updatedAt,
      if (entityKey != null) 'entityKey': entityKey,
      if (bangumiId != null) 'bangumiId': bangumiId,
      'payload': payload,
    };
  }
}

class PrivateSyncSnapshot {
  const PrivateSyncSnapshot({
    required this.generatedAt,
    required this.watch,
    required this.collection,
  });

  final int generatedAt;
  final PrivateSyncWatchSnapshot watch;
  final PrivateSyncCollectionSnapshot collection;

  factory PrivateSyncSnapshot.fromJson(Map<String, dynamic> json) {
    return PrivateSyncSnapshot(
      generatedAt: (json['generatedAt'] as num?)?.toInt() ?? 0,
      watch: PrivateSyncWatchSnapshot.fromJson(
        Map<String, dynamic>.from((json['watch'] as Map?) ?? const {}),
      ),
      collection: PrivateSyncCollectionSnapshot.fromJson(
        Map<String, dynamic>.from((json['collection'] as Map?) ?? const {}),
      ),
    );
  }
}

class PrivateSyncWatchSnapshot {
  const PrivateSyncWatchSnapshot({
    required this.clearVersion,
    required this.histories,
  });

  final String? clearVersion;
  final List<PrivateSyncWatchHistory> histories;

  factory PrivateSyncWatchSnapshot.fromJson(Map<String, dynamic> json) {
    return PrivateSyncWatchSnapshot(
      clearVersion: json['clearVersion'] as String?,
      histories: ((json['histories'] as List?) ?? const [])
          .map(
            (item) => PrivateSyncWatchHistory.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

class PrivateSyncWatchHistory {
  const PrivateSyncWatchHistory({
    required this.entityKey,
    required this.bangumiId,
    required this.adapterName,
    required this.lastWatchEpisode,
    required this.lastWatchTime,
    required this.lastSrc,
    required this.lastWatchEpisodeName,
    required this.bangumiItem,
    required this.itemVersion,
    required this.progresses,
  });

  final String entityKey;
  final int bangumiId;
  final String adapterName;
  final int lastWatchEpisode;
  final int lastWatchTime;
  final String lastSrc;
  final String lastWatchEpisodeName;
  final BangumiItem bangumiItem;
  final String itemVersion;
  final Map<int, PrivateSyncWatchProgress> progresses;

  factory PrivateSyncWatchHistory.fromJson(Map<String, dynamic> json) {
    final progressJson =
        Map<String, dynamic>.from((json['progresses'] as Map?) ?? const {});
    return PrivateSyncWatchHistory(
      entityKey: json['entityKey'] as String,
      bangumiId: (json['bangumiId'] as num).toInt(),
      adapterName: json['adapterName'] as String,
      lastWatchEpisode: (json['lastWatchEpisode'] as num).toInt(),
      lastWatchTime: (json['lastWatchTime'] as num).toInt(),
      lastSrc: json['lastSrc'] as String? ?? '',
      lastWatchEpisodeName: json['lastWatchEpisodeName'] as String? ?? '',
      bangumiItem: PrivateSyncBangumiCodec.fromJson(
        Map<String, dynamic>.from(json['bangumiItem'] as Map),
      ),
      itemVersion: json['itemVersion'] as String? ?? '',
      progresses: {
        for (final entry in progressJson.entries)
          int.parse(entry.key): PrivateSyncWatchProgress.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
    );
  }
}

class PrivateSyncWatchProgress {
  const PrivateSyncWatchProgress({
    required this.episode,
    required this.road,
    required this.progressMs,
    required this.version,
  });

  final int episode;
  final int road;
  final int progressMs;
  final String version;

  factory PrivateSyncWatchProgress.fromJson(Map<String, dynamic> json) {
    return PrivateSyncWatchProgress(
      episode: (json['episode'] as num).toInt(),
      road: (json['road'] as num).toInt(),
      progressMs: (json['progressMs'] as num).toInt(),
      version: json['version'] as String? ?? '',
    );
  }
}

class PrivateSyncCollectionSnapshot {
  const PrivateSyncCollectionSnapshot({
    required this.clearVersion,
    required this.items,
  });

  final String? clearVersion;
  final List<PrivateSyncCollectionItem> items;

  factory PrivateSyncCollectionSnapshot.fromJson(Map<String, dynamic> json) {
    return PrivateSyncCollectionSnapshot(
      clearVersion: json['clearVersion'] as String?,
      items: ((json['items'] as List?) ?? const [])
          .map(
            (item) => PrivateSyncCollectionItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

class PrivateSyncCollectionItem {
  const PrivateSyncCollectionItem({
    required this.bangumiId,
    required this.type,
    required this.collectedAt,
    required this.updatedAt,
    required this.bangumiItem,
    required this.itemVersion,
  });

  final int bangumiId;
  final int type;
  final int? collectedAt;
  final int updatedAt;
  final BangumiItem bangumiItem;
  final String itemVersion;

  factory PrivateSyncCollectionItem.fromJson(Map<String, dynamic> json) {
    return PrivateSyncCollectionItem(
      bangumiId: (json['bangumiId'] as num).toInt(),
      type: (json['type'] as num).toInt(),
      collectedAt: (json['collectedAt'] as num?)?.toInt(),
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      bangumiItem: PrivateSyncBangumiCodec.fromJson(
        Map<String, dynamic>.from(json['bangumiItem'] as Map),
      ),
      itemVersion: json['itemVersion'] as String? ?? '',
    );
  }
}

class PrivateSyncBangumiCodec {
  const PrivateSyncBangumiCodec._();

  static BangumiItem fromJson(Map<String, dynamic> json) {
    return BangumiItem(
      id: (json['id'] as num).toInt(),
      type: (json['type'] as num?)?.toInt() ?? 2,
      name: json['name'] as String? ?? '',
      nameCn: json['nameCn'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      airDate: json['airDate'] as String? ?? '',
      airWeekday: (json['airWeekday'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      images: Map<String, String>.from((json['images'] as Map?) ?? const {}),
      tags: ((json['tags'] as List?) ?? const [])
          .map((tag) => BangumiTag.fromJson(Map<String, dynamic>.from(tag)))
          .toList(),
      alias: ((json['alias'] as List?) ?? const [])
          .map((alias) => alias.toString())
          .toList(),
      ratingScore: (json['ratingScore'] as num?)?.toDouble() ?? 0,
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      votesCount: ((json['votesCount'] as List?) ?? const [])
          .map((vote) => (vote as num).toInt())
          .toList(),
      info: json['info'] as String? ?? '',
    );
  }

  static Map<String, dynamic> toJson(BangumiItem item) {
    return {
      'id': item.id,
      'type': item.type,
      'name': item.name,
      'nameCn': item.nameCn,
      'summary': item.summary,
      'airDate': item.airDate,
      'airWeekday': item.airWeekday,
      'rank': item.rank,
      'images': item.images,
      'tags': item.tags.map((tag) => tag.toJson()).toList(),
      'alias': item.alias,
      'ratingScore': item.ratingScore,
      'votes': item.votes,
      'votesCount': item.votesCount,
      'info': item.info,
    };
  }
}
