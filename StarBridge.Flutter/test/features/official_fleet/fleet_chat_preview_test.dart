import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_chat_preview.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_chat_attention.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';

import '../communities/community_chat_controller_test.dart' show page;
import '../communities/community_unread_attention_test.dart' show UnreadPort;

CommunityChatMessage _message(
  int sequence, {
  String text = 'text',
  bool isSelf = false,
  bool attachment = false,
  String callsign = '',
}) => CommunityChatMessage.parse({
  'sequence': sequence,
  'messageRef': sequence.toRadixString(16).padLeft(32, '0'),
  'senderRef': 'd' * 32,
  'senderCallsign': callsign,
  'senderGameId': '',
  'senderRoleTitle': '',
  'senderRoleColor': '#9DAAB3',
  'text': text,
  'createdAt': '2026-10-30T00:00:00Z',
  'isSelf': isSelf,
  'hasAvatar': false,
  'hasAttachment': attachment,
});

Future<void> _pump(
  WidgetTester tester,
  List<CommunityChatMessage> messages, {
  required double height,
  int unread = 0,
  double textScale = 1,
}) async {
  await tester.pumpWidget(_app(messages, height, unread, textScale));
  await tester.pump();
}

Widget _app(
  List<CommunityChatMessage> messages,
  double height,
  int unread,
  double textScale,
) => MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: const [
      AppStringsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(AppearanceMode.dark),
      const Locale('zh', 'CN'),
    ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 240,
            child: OrganizationChatPreview(
              key: const Key('preview'),
              messages: messages,
              unread: unread,
              height: height,
            ),
          ),
        ),
      ),
    ),
);

void main() {
  group('attention keeps the newest messages it already read', () {
    Future<void> drain() => Future<void>.delayed(Duration.zero);
    final target = 'a' * 32;
    late UnreadPort source;
    late CommunityChatAttention attention;
    setUp(() {
      source = UnreadPort();
      attention = CommunityChatAttention(source);
    });
    tearDown(() async {
      attention.dispose();
      await source.close();
    });
    List<int> sequences() =>
        attention.recent(target).map((m) => m.sequence).toList();

    test('oldest first, bounded, with no extra read', () async {
      source.previews[target] = _page(List.generate(12, (i) => i + 1));
      attention.bind([target]);
      await drain();
      expect(sequences(), [5, 6, 7, 8, 9, 10, 11, 12]);
      expect(source.previewReads, 1);
    });

    test('each read replaces the list, so a removed message goes', () async {
      source.previews[target] = _page([1, 2, 3]);
      attention.bind([target]);
      await drain();
      source.previews[target] = _page([1, 3], latest: 3);
      attention.refresh();
      await drain();
      expect(sequences(), [1, 3]);
      source.previews[target] = _page([], latest: 3);
      attention.refresh();
      await drain();
      expect(sequences(), isEmpty);
    });

    test('a transient failure keeps them; lost access clears them', () async {
      source.previews.clear();
      source.chat.next = _page([1, 2]);
      attention.bind([target]);
      await drain();
      expect(sequences(), [1, 2]);
      source.chat.failure = const CommunityFailure('unavailable');
      attention.refresh();
      await drain();
      expect(sequences(), [1, 2]);
      for (final code in ['notAllowed', 'notFound', 'identityUnavailable']) {
        source.chat.failure = null;
        source.chat.next = _page([1, 2]);
        attention.refresh();
        await drain();
        expect(sequences(), [1, 2]);
        source.chat.failure = CommunityFailure(code);
        attention.refresh();
        await drain();
        expect(sequences(), isEmpty, reason: code);
      }
    });
  });

  group('the tile fits what the height allows', () {
    final messages = [for (var i = 1; i <= 8; i++) _message(i, text: 'M$i')];
    double lineHeight(WidgetTester tester) =>
        tester.getSize(find.byType(RichText).last).height;

    testWidgets('a tight tile still shows the newest message', (tester) async {
      await _pump(tester, messages, height: 4);
      expect(find.textContaining('M8', findRichText: true), findsOneWidget);
      expect(find.textContaining('M7', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('more room shows more, newest last, and never overflows', (
      tester,
    ) async {
      await _pump(tester, messages, height: 200);
      final line = lineHeight(tester);
      for (final height in <double>[
        line,
        line * 2 + 6,
        line * 3 + 12,
        line * 4 + 11.9,
        line * 8 + 42,
      ]) {
        await _pump(tester, messages, height: height);
        final preview = tester.getSize(find.byKey(const Key('preview')));
        expect(preview.height, lessThanOrEqualTo(height), reason: '$height');
        expect(tester.takeException(), isNull);
        expect(find.textContaining('M8', findRichText: true), findsOneWidget);
      }
      await _pump(tester, messages, height: line * 2 + 6);
      expect(find.textContaining('M7', findRichText: true), findsOneWidget);
      expect(find.textContaining('M6', findRichText: true), findsNothing);
      await _pump(tester, messages, height: 2000);
      expect(find.textContaining('M1', findRichText: true), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining('M7', findRichText: true)).dy,
        lessThan(tester.getTopLeft(find.textContaining('M8', findRichText: true)).dy),
      );
    });

    testWidgets('large text fits fewer messages instead of overflowing', (
      tester,
    ) async {
      await _pump(tester, messages, height: 100);
      final normal = find.byType(RichText).evaluate().length;
      await _pump(tester, messages, height: 100, textScale: 2);
      expect(find.byType(RichText).evaluate().length, lessThan(normal));
      expect(
        tester.getSize(find.byKey(const Key('preview'))).height,
        lessThanOrEqualTo(100),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a lone long message may take two lines', (tester) async {
      final long = [_message(1, text: '很长的消息' * 40)];
      await _pump(tester, long, height: 200);
      final two = tester.getSize(find.byKey(const Key('preview'))).height;
      await _pump(tester, long, height: 18);
      final one = tester.getSize(find.byKey(const Key('preview'))).height;
      expect(two, greaterThan(one));
      expect(tester.takeException(), isNull);
    });

    testWidgets('authors, own messages and attachments read correctly', (
      tester,
    ) async {
      await _pump(tester, [
        _message(1, text: 'named', callsign: 'Pilot'),
        _message(2, text: 'mine', isSelf: true),
        _message(3, text: 'nobody'),
        _message(4, text: '', attachment: true, callsign: 'Pilot'),
      ], height: 400);
      expect(find.text('Pilot：named', findRichText: true), findsOneWidget);
      expect(find.text('我：mine', findRichText: true), findsOneWidget);
      expect(find.text('nobody', findRichText: true), findsOneWidget);
      expect(find.textContaining('Pilot：', findRichText: true), findsNWidgets(2));
    });

    testWidgets('only the unread messages are emphasized', (tester) async {
      await _pump(tester, messages, height: 2000, unread: 2);
      TextStyle styleOf(String text) => tester
          .widget<RichText>(find.textContaining(text, findRichText: true))
          .text
          .style!;
      expect(styleOf('M8').color, styleOf('M7').color);
      expect(styleOf('M6').color, isNot(styleOf('M7').color));
    });

    testWidgets('no messages reads plainly', (tester) async {
      await _pump(tester, const [], height: 100);
      expect(find.byType(RichText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

CommunityChatPage _page(List<int> sequences, {int? latest}) => page(
  sequences,
  latest: latest ?? (sequences.isEmpty ? 0 : sequences.last),
  unread: 0,
  older: false,
);
