import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';

import 'community_workspace_test.dart' show WorkspaceTestPort, workspacePayload;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'hovered roster updates fields but defers reorder until pointer leaves',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      var ids = ['b', 'c'];
      var suffix = '';
      port.reader = (_, query, _) async {
        final payload = workspacePayload(query: query);
        final template = Map<String, Object?>.from(
          (payload['members'] as List).single as Map,
        );
        payload['members'] = [
          for (final id in ids)
            {
              ...template,
              'memberRef': id * 32,
              'callsign': 'Member $id$suffix',
              'isSelf': false,
            },
        ];
        payload['totalCount'] = ids.length;
        payload['matchedCount'] = ids.length;
        return CommunityWorkspace.parse(payload);
      };
      await tester.pumpWidget(host(port, const Locale('en')));
      await tester.pumpAndSettle();
      final state = tester.state<CommunityWorkspaceViewState>(
        find.byType(CommunityWorkspaceView),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Member b')));
      await tester.pump();
      ids = ['c', 'b'];
      suffix = ' updated';
      await state.model.load();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Member b updated')).dy,
        lessThan(tester.getTopLeft(find.text('Member c updated')).dy),
      );
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Member c updated')).dy,
        lessThan(tester.getTopLeft(find.text('Member b updated')).dy),
      );
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
