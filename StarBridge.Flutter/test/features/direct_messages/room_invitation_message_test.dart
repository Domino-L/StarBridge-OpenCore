import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/bridge_direct_messages.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_codec.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';

import 'bridge_direct_messages_test.dart' as data;
import 'direct_messages_test.dart' as ui;

class Port implements DirectMessagesPort {
  final row = Conversation(
    data.reference,
    'Fixture',
    '',
    DateTime(2026),
    0,
    'friend',
  );
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<List<Conversation>> directory() async => [row];
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    final value = data.history();
    final message = (value['messages'] as List).single as Map;
    message['attachmentKind'] = 'party_room_invitation';
    message['roomInvitation'] = {
      'title': 'Synthetic Room',
      'summary': 'Synthetic purpose',
      'invitationId': 'fixture-invitation',
      'expiresAt': '2099-01-01T00:00:00Z',
    };
    final page = parseDirectPage(value);
    // Exercise the detached-window serialization path as well as bridge parsing.
    return DirectPage(
      ref,
      page.messages.map((m) => decodeMessage(encodeMessage(m))).toList(),
      page.oldest,
      page.latest,
      page.hasOlder,
      page.state,
    );
  }

  @override
  void cancel() {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets(
    'private room card survives bridge and detached codec and opens its invitation',
    (tester) async {
      final port = Port();
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      await module.open(module.rows.single);
      final base = ui.app(const Locale('en'), () => port) as MaterialApp;
      String? route;
      await tester.pumpWidget(
        MaterialApp(
          theme: base.theme,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          home: Actions(
            actions: {
              OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                onInvoke: (i) {
                  route = i.route;
                  return null;
                },
              ),
            },
            child: Scaffold(
              body: DirectMessagesPage(
                createPort: () => port,
                sharedModule: module,
                onBack: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic Room'), findsOneWidget);
      await tester.tap(find.text('View invitation'));
      expect(route, '/rooms/invitations?invitation=fixture-invitation');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
