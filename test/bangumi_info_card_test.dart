import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/bangumi_info_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

void main() {
  testWidgets(
    'BangumiInfoCardV renders Laeva detail data without rating distribution',
    (tester) async {
      final item = BangumiItem(
        id: 547888,
        type: 2,
        name: 'Test Anime',
        nameCn: '测试番剧',
        summary: 'summary',
        airDate: '2026-06-01',
        airWeekday: 1,
        rank: 0,
        images: const {},
        tags: const [],
        alias: const [],
        ratingScore: 0,
        votes: 0,
        votesCount: const [],
        info: 'laeva-bangumi:547888',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 400,
              child: BangumiInfoCardV(
                bangumiItem: item,
                isLoading: false,
                showRating: true,
                showCollectButton: false,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('测试番剧'), findsOneWidget);
    },
  );
}
