import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/menu_social_notice_source.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_notice_banner.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/platform/window/menu_notice.dart';
import 'package:starbridge_flutter/platform/window/menu_live_presentation_feeds.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

NotificationSettingsProjection projection(
  NotificationPreviewMode mode, {
  bool enabled = true,
}) {
  final value = NotificationSettingsValue.reviewDefaults(sourceRules: []);
  return NotificationSettingsProjection.fromSnapshot(
    NotificationSettingsSnapshot.available(
      settings: value.copyWith(
        previewMode: mode,
        channels: value.channels.copyWith(inAppEnabled: enabled),
      ),
      revision: 4,
    ),
  );
}

const event = LocalRoomReminder(
  4,
  1,
  0,
  kind: 'direct',
  senderName: 'Fixture Sender',
  messagePreview: 'Synthetic private body',
);

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'feed binds live reading identity without dropping other senders',
    (tester) async {
      final events = StreamController<LocalRoomReminder?>.broadcast(sync: true);
      final settings = ValueNotifier(
        projection(NotificationPreviewMode.sourceOnly),
      );
      final auth = ValueNotifier(true);
      final source = MenuSocialNoticeSource(
        events: events.stream,
        settings: settings,
        authorization: auth,
        isCurrent: () => true,
        strings: () => AppStrings.resolve(const Locale('en')),
      );
      String? visible = 'reading';
      final feeds = MenuLivePresentationFeeds();
      feeds.start(
        notices: () => source,
        visibleConversationKey: () => visible,
        isCurrent: () => true,
        publish: (_, _) {},
      );
      void emit(List<String> keys) => events.add(
        LocalRoomReminder(4, 1, 0, kind: 'direct', conversationKeys: keys),
      );
      emit(['reading']);
      expect(source.value, isNull);
      emit(['reading', 'other']);
      expect(source.value, isNotNull);
      emit([]);
      expect(source.value, isNotNull);
      visible = null;
      emit(['reading']);
      expect(source.value, isNotNull);
      feeds.stop();
      await events.close();
      settings.dispose();
      auth.dispose();
    },
  );
  test('wire payload contains only bounded presentation text', () {
    expect(
      MenuNotice.parse(jsonEncode(const MenuNotice('Title', 'Body').toMap()))!
          .message,
      'Body',
    );
    for (final raw in [
      null,
      '{',
      jsonEncode({'title': 'T', 'message': 'M', 'account': 'forbidden'}),
      jsonEncode({'title': 'x' * 1025, 'message': ''}),
      jsonEncode({'title': '', 'message': 3}),
    ]) {
      expect(MenuNotice.parse(raw), isNull);
    }
  });
  testWidgets('saved menu policy changes apply without restarting the stream', (
    tester,
  ) async {
    final events = StreamController<LocalRoomReminder?>.broadcast(sync: true);
    final settings = ValueNotifier(
      projection(NotificationPreviewMode.fullContent),
    );
    final auth = ValueNotifier(true);
    final source = MenuSocialNoticeSource(
      events: events.stream,
      settings: settings,
      authorization: auth,
      isCurrent: () => true,
      strings: () => AppStrings.resolve(const Locale('en')),
    );
    Map policy(bool enabled, String preview) => {
      'social': {
        'friendSort': 'onlineFirst',
        'notifications': enabled,
        'preview': preview,
      },
    };
    final feeds = MenuLivePresentationFeeds();
    feeds.start(
      notices: () => source,
      settings: policy(true, 'fullContent'),
      isCurrent: () => true,
      publish: (_, _) {},
    );
    events.add(event);
    expect(source.value!.message, contains('Synthetic private body'));
    feeds.updateSettings(policy(false, 'fullContent'));
    expect(source.value, isNull);
    events.add(event);
    expect(source.value, isNull);
    feeds.updateSettings(policy(true, 'sourceOnly'));
    expect(source.value, isNull);
    events.add(event);
    expect(source.value!.message, isNot(contains('Synthetic private body')));
    settings.value = projection(NotificationPreviewMode.hiddenDetails);
    feeds.updateSettings(policy(true, 'fullContent'));
    events.add(event);
    expect(
      jsonEncode(source.value!.toMap()),
      isNot(contains('Fixture Sender')),
    );
    feeds.stop();
    await events.close();
    settings.dispose();
    auth.dispose();
  });
  for (final global in NotificationPreviewMode.values) {
    for (final local in NotificationPreviewMode.values) {
      testWidgets('privacy cannot broaden global=$global local=$local', (
        tester,
      ) async {
        final events = StreamController<LocalRoomReminder?>.broadcast(
          sync: true,
        );
        final settings = ValueNotifier(projection(global));
        final auth = ValueNotifier(true);
        final source = MenuSocialNoticeSource(
          events: events.stream,
          settings: settings,
          authorization: auth,
          isCurrent: () => auth.value,
          strings: () => AppStrings.resolve(const Locale('en')),
          preview: () => local,
        );
        events.add(event);
        final text = jsonEncode(source.value!.toMap());
        final hidden =
            global == NotificationPreviewMode.hiddenDetails ||
            local == NotificationPreviewMode.hiddenDetails;
        final full =
            global == NotificationPreviewMode.fullContent &&
            local == NotificationPreviewMode.fullContent;
        expect(text.contains('Fixture Sender'), !hidden);
        expect(text.contains('Synthetic private body'), full);
        settings.value = projection(global, enabled: false);
        expect(source.value, isNull);
        events.add(event);
        expect(source.value, isNull);
        source.dispose();
        settings.dispose();
        auth.dispose();
        await events.close();
      });
    }
  }
  testWidgets(
    'expiry revocation null events and disposal never replay content',
    (tester) async {
      final events = StreamController<LocalRoomReminder?>.broadcast(sync: true);
      final invalidations = StreamController<void>.broadcast(sync: true);
      final settings = ValueNotifier(
        projection(NotificationPreviewMode.fullContent),
      );
      final auth = ValueNotifier(true);
      final source = MenuSocialNoticeSource(
        events: events.stream,
        settings: settings,
        invalidations: invalidations.stream,
        authorization: auth,
        isCurrent: () => auth.value,
        strings: () => AppStrings.resolve(const Locale('en')),
      );
      events.add(event);
      expect(source.value, isNotNull);
      expect(source.value!.message, isNot(contains('Synthetic private body')));
      await tester.pump(const Duration(seconds: 4));
      expect(source.value, isNull);
      events.add(event);
      events.add(null);
      expect(source.value, isNull);
      events.add(const LocalRoomReminder(3, 1, 0, kind: 'direct'));
      expect(source.value, isNull);
      events.add(
        const LocalRoomReminder(4, 1, 0, kind: 'direct', overlayHandled: true),
      );
      expect(source.value, isNull);
      events.add(
        const LocalRoomReminder(4, 1, 0, kind: 'direct', desktopEligible: true),
      );
      expect(source.value, isNull);
      events.add(event);
      invalidations.add(null);
      expect(source.value, isNull);
      events.add(event);
      expect(source.value, isNull);
      source.dispose();
      events.add(event);
      expect(source.value, isNull);
      settings.dispose();
      auth.dispose();
      await events.close();
      await invalidations.close();
    },
  );
  testWidgets(
    'visible-opening feed stops subscription and refuses late publication',
    (tester) async {
      final events = StreamController<LocalRoomReminder?>.broadcast(sync: true);
      final settings = ValueNotifier(
            projection(NotificationPreviewMode.fullContent),
          ),
          auth = ValueNotifier(true);
      final feeds = MenuLivePresentationFeeds();
      final published = <Map<String, Object?>>[];
      var current = true;
      feeds.start(
        notices: () => MenuSocialNoticeSource(
          events: events.stream,
          settings: settings,
          authorization: auth,
          isCurrent: () => auth.value,
          strings: () => AppStrings.resolve(const Locale('en')),
        ),
        isCurrent: () => current,
        publish: (value, method) {
          expect(method, 'noticeView');
          published.add(value);
        },
      );
      expect(feeds.hasNotices, true);
      events.add(event);
      final count = published.length;
      current = false;
      events.add(event);
      expect(published.length, count);
      feeds.stop();
      expect(feeds.hasNotices, false);
      expect(events.hasListener, false);
      events.add(event);
      expect(published.length, count);
      settings.dispose();
      auth.dispose();
      await events.close();
    },
  );
  testWidgets(
    'banner fits narrow large text and expires without primary reply',
    (tester) async {
      size(tester, const Size(320, 900));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: RepaintBoundary(
              key: key,
              child: const MenuNoticeBanner(
                notice: MenuNotice('新的好友申请', '你有新的社交消息，请前往对应页面查看。'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'menu-social-notice-narrow');
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('新的好友申请'), findsNothing);
    },
  );
}
