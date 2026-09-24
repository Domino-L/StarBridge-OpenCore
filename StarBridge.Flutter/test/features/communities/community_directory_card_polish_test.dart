import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_directory_card.dart';

import '../personal_profile/profile_polish_regression_test.dart' show app;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final width in [340.0, 520.0]) {
    testWidgets(
      'directory card retains all information and actions at $width',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var details = 0;
        String? action;
        const description = '一起探索、运输和协作。欢迎新成员，周末开展团体活动。';
        final capture = GlobalKey();
        await tester.pumpWidget(
          app(
            RepaintBoundary(
              key: capture,
              child: SizedBox(
                width: width,
                child: CommunityDirectoryCard(
                  row: const CommunityCard(
                    targetRef: 'fixture',
                    name: '北辰探索协作组织 · Northstar',
                    description: description,
                    memberCount: 128,
                    language: 'zh-CN',
                    activeTime: '工作日 19:00–23:00；周末 08:00–22:00',
                    recruiting: true,
                    recruitingTarget: '新手友好',
                    recruitingNote: '欢迎周末参与多人舰船协作，不要求每天上线。',
                    tags: '探索 · 运输 · 社交 · 新手友好',
                    joinMode: 'application',
                    actions: ['apply'],
                  ),
                  text: (key) =>
                      AppStrings.resolve(const Locale('zh', 'CN'))
                          .text('communities.$key'),
                  onDetails: () => details++,
                  onAction: (value) => action = value,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(description), findsOneWidget);
        expect(find.text('128'), findsOneWidget);
        expect(tester.getSize(find.byType(CommunityDirectoryCard)).height, 464);
        expect(find.textContaining('简体中文'), findsOneWidget);
        for (final tag in ['探索', '运输', '社交']) {
          expect(
            find.byKey(ValueKey('community-gameplay-tag-$tag')),
            findsOneWidget,
          );
        }
        await tester.tap(find.byType(TextButton));
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(details, 1);
        expect(action, 'apply');
        expect(tester.takeException(), isNull);
        if (Platform.environment['STARBRIDGE_CAPTURE_POLISH'] == '1') {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('../.artifacts/directory-card-${width.toInt()}.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}
