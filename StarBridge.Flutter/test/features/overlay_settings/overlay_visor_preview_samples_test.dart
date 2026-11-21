import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preview_identity.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_layout.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_preview_content.dart';

import '../friends/social_layout_test.dart' show app;
import 'overlay_settings_ux_a_test.dart' show settings;

/// 11-11 user ("预览示例和文案对齐面罩"): the editor's samples look like the
/// visor: the members block has the fleet overview on top and several members
/// in fixed columns, and the chat list shows no time.
void main() {
  Widget preview(String key, Map<String, Object?> values) => app(
    SizedBox(
      width: 360,
      height: 320,
      child: OverlayPreviewContent(
        moduleKey: key,
        settings: settings(values),
        referenceSize: const Size(360, 320),
        previewIdentity: const OverlayPreviewIdentity(
          callSign: 'Domino',
          gameHandle: 'domino_CN',
        ),
        simulate: true,
      ),
    ),
  );

  testWidgets('the members sample shows the fleet overview and several rows', (
    tester,
  ) async {
    expect(OverlayVisorLayout.active(settings(const {})), isTrue);
    await tester.pumpWidget(preview('Members', const {'showMembers': true}));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-preview-members-fleet-overview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-preview-member-status-dot')),
      findsAtLeastNWidgets(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chat sample shows no time on the visor', (tester) async {
    await tester.pumpWidget(
      preview('Chat', const {
        'showChat': true,
        'chatShowSender': true,
        'chatShowTimestamp': true,
      }),
    );
    await tester.pumpAndSettle();
    // the sample sender is still shown; its time is not
    expect(find.text('发送者'), findsOneWidget);
    expect(find.text('21:14'), findsNothing);
    expect(find.text('21:15'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
