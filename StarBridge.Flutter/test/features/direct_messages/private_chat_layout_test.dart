import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_codec.dart';
import 'package:starbridge_flutter/app/shell/chrome/presence_color.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';

import '../friends/social_layout_test.dart' show app, size, capture, loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final mode in AppearanceMode.values) {
    for (final entry in {
      'online': '在线',
      'inGame': '游戏中',
      'away': '暂离',
      'offline': '离线',
    }.entries) {
      testWidgets('chat shares ${entry.key} status color in ${mode.name}', (
        tester,
      ) async {
        size(tester, const Size(1000, 720));
        await tester.pumpWidget(
          app(
            DirectMessagesPage(
              createPort: () => _PresencePort(entry.key),
              onBack: () {},
            ),
            mode,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('示例好友  @Example'));
        await tester.pumpAndSettle();
        final expected = presenceColor(
          FutureRestraintStyle.resolve(mode).colors,
          'presence.${entry.key}',
        );
        final labels = find.text(entry.value);
        expect(labels, findsNWidgets(2));
        for (final element in labels.evaluate()) {
          final label = element.widget as Text;
          expect(label.style?.color, expected);
          final row = find
              .ancestor(of: find.byWidget(label), matching: find.byType(Row))
              .first;
          final dot = tester.widget<Container>(
            find.descendant(
              of: row,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).shape ==
                        BoxShape.circle,
              ),
            ),
          );
          expect((dot.decoration! as BoxDecoration).color, expected);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  for (final mode in AppearanceMode.values) {
    for (final width in [390.0, 680.0, 1000.0]) {
      testWidgets('private chat ${mode.name} at $width', (tester) async {
        size(tester, Size(width, 720));
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: app(
              DirectMessagesPage(
                createPort: ExampleDirectMessages.new,
                onBack: () {},
              ),
              mode,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('示例好友  @Example'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-search')),
          width >= 680 ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('在线'),
          width >= 680 ? findsNWidgets(2) : findsOneWidget,
        );
        expect(find.byType(TextFormField), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          key,
          'private-chat-${mode.name}-${width.toInt()}',
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  test('detached conversation wire retains only authorized coarse status', () {
    for (final presence in ['online', 'away', 'inGame', 'offline']) {
      for (final state in ['friend', 'accepted', 'request_incoming']) {
        final row = Conversation(
          'fixture',
          'Fixture',
          '',
          DateTime(2026),
          0,
          state,
          presence: presence,
        );
        expect(
          decodeConversation(encodeConversation(row)).presence,
          state == 'friend' ? presence : null,
        );
      }
    }
  });
}

final class _PresencePort implements DirectMessagesPort {
  _PresencePort(this.presence);
  final String presence;
  final _inner = ExampleDirectMessages();
  @override
  Stream<void> get invalidations => _inner.invalidations;
  @override
  Future<List<Conversation>> directory() async => [
    for (final row in await _inner.directory())
      Conversation(
        row.ref,
        row.name,
        row.preview,
        row.time,
        row.unread,
        row.state,
        gameId: row.gameId,
        conversationKey: row.conversationKey,
        presence: row.state == 'friend' ? presence : null,
      ),
  ];
  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) =>
      _inner.history(ref, before: before, after: after);
  @override
  void cancel() => _inner.cancel();
  @override
  Future<void> close() => _inner.close();
}
