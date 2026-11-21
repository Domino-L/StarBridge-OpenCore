import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/interaction_batch3aq_test.dart'
    show Port, moduleFor, disposePage;
import '../../design_system/interaction/interaction_batch3ae_test.dart'
    show mount;

void main() {
  testWidgets(
    'the organization invitation entry follows the account after the page is shown',
    (t) async {
      final module = await moduleFor(Port(), open: true);
      final available = ValueNotifier(true);
      try {
        await mount(
          t,
          DirectMessagesPage(
            createPort: () => module.port,
            sharedModule: module,
            onBack: () {},
            sendCommunityInvite: (_, _) async {},
            communityInviteAvailable: available,
          ),
          InteractionSuite.values.first,
        );
        const entry = ValueKey('chat-send-organization-invitation');
        expect(find.byKey(entry), findsOneWidget);
        available.value = false;
        await t.pump();
        expect(find.byKey(entry), findsNothing);
        available.value = true;
        await t.pump();
        expect(find.byKey(entry), findsOneWidget);
      } finally {
        await disposePage(t, module);
        available.dispose();
      }
    },
  );
}
