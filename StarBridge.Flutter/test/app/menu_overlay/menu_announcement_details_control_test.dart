import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_announcement_details_control.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_announcement_details_view.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_details.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, capture, loadFonts;

Map<String, Object?> fixture({
  bool loading = false,
  bool failed = false,
  String key = 'd1',
  String? photo,
  bool long = false,
}) {
  Map<String, Object?> person(String name) => {
    'callsign': name,
    'gameId': '',
    'roleTitle': '成员',
    'roleColor': '#abcdef',
    'hasAvatar': photo != null,
  };
  return {
    'key': key,
    'loading': loading,
    'failed': failed,
    'authorAvatar': photo,
    'editorAvatar': photo,
    'entry': {
      'title': '巡航行动说明',
      'content': long
          ? List.filled(35, '行动开始前请确认集合位置与通信频道。').join('\n')
          : '请准时集合。',
      'state': 'withdrawn',
      'revision': 4,
      'publishedAt': '2026-10-01T10:00:00Z',
      'updatedAt': '2026-10-01T11:00:00Z',
      'archivedAt': '2026-10-01T12:00:00Z',
      'withdrawnAt': '2026-10-01T13:00:00Z',
      'author': person('作者甲'),
      'editor': person('编辑乙'),
    },
  };
}

void main() {
  setUpAll(() async {
    if (Platform.environment['STARBRIDGE_CAPTURE_SOCIAL'] == '1') {
      await loadFonts();
    }
  });
  for (final width in [1280.0, 700.0]) {
    testWidgets('shared selectable details scroll at $width', (tester) async {
      size(tester, Size(width, 900));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: app(
            Center(
              child: MenuAnnouncementDetailsControl(
                view: MenuAnnouncementDetailsView.parse(fixture(long: true))!,
                action: 'a1',
                enabled: true,
                dispatch: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAnnouncementDetailsBody), findsOneWidget);
      expect(find.byType(SelectableText), findsNWidgets(2));
      await capture(
        tester,
        boundary,
        'menu-announcement-details-${width.toInt()}',
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      expect(find.text('作者甲'), findsOneWidget);
      expect(find.text('编辑乙'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message?.startsWith('2026-10-01') ?? false),
        ),
        findsNWidgets(4),
      );
      await capture(
        tester,
        boundary,
        'menu-announcement-details-${width.toInt()}-metadata',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
    'refresh retains dialog and equal photo byte identity; hide closes',
    (tester) async {
      size(tester, const Size(1280, 900));
      // Invalid image bytes are sufficient to verify identity stability without
      // putting any real user's image into a fixture.
      const photo = 'data:image/png;base64,AA==';
      final state = ValueNotifier(fixture(photo: photo));
      final active = ValueNotifier(true);
      addTearDown(state.dispose);
      addTearDown(active.dispose);
      final calls = <String>[];
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, shown, _) =>
                ValueListenableBuilder<Map<String, Object?>>(
                  valueListenable: state,
                  builder: (_, value, _) => Center(
                    child: MenuAnnouncementDetailsControl(
                      view: MenuAnnouncementDetailsView.parse(value)!,
                      action: 'a1',
                      enabled: true,
                      active: shown,
                      dispatch: (key, _) => calls.add(key),
                    ),
                  ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      final first = tester
          .widget<CommunityAnnouncementDetailsBody>(
            find.byType(CommunityAnnouncementDetailsBody),
          )
          .author;
      state.value = fixture(photo: photo);
      await tester.pumpAndSettle();
      expect(
        identical(
          first,
          tester
              .widget<CommunityAnnouncementDetailsBody>(
                find.byType(CommunityAnnouncementDetailsBody),
              )
              .author,
        ),
        isTrue,
      );
      expect(calls, ['a1']);
      active.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scope retirement removes open detail and retry uses latest action',
    (tester) async {
      final state = ValueNotifier(fixture(failed: true));
      addTearDown(state.dispose);
      var action = 'a1';
      final calls = <String>[];
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<Map<String, Object?>>(
            valueListenable: state,
            builder: (_, raw, _) {
              final view = MenuAnnouncementDetailsView.parse(raw)!;
              return Center(
                child: MenuAnnouncementDetailsControl(
                  key: ValueKey(view.key),
                  view: view,
                  action: action,
                  enabled: true,
                  dispatch: (key, _) => calls.add(key),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      action = 'a2';
      state.value = fixture(failed: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).first);
      await tester.pump();
      expect(calls, ['a1', 'a2']);
      state.value = fixture(key: 'd2');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
