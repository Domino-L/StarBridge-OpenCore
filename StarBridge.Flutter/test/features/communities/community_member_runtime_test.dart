import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_member_runtime.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_copy.dart';

import 'community_workspace_test.dart' show workspacePayload;

void main() {
  for (var language = 0; language < 3; language++) {
    test('WPF session matrix, privacy and placeholders locale $language', () {
      String text(String key) {
        final value = communityWorkspaceCopy[key]!;
        return [value.$1, value.$2, value.$3][language];
      }

      ({String server, String ship, String location}) render(
        Map<String, Object?> overrides,
      ) {
        final payload = workspacePayload();
        final row = (payload['members'] as List).single as Map<String, Object?>;
        row.addAll({
          'ship': 'Unknown',
          'location': 'Unknown',
          'arrivalPendingConfirmation': false,
          ...overrides,
        });
        return communityMemberRuntime(
          CommunityWorkspaceMember.parse(row),
          text: text,
          regionText: (value) => value,
        );
      }

      for (final state in ['Offline', 'AppOnline', 'Away']) {
        final values = render({'liveStatus': state});
        expect(
          (values.server, values.ship, values.location),
          (text('notInGame'), text('notInGame'), text('notInGame')),
        );
      }
      expect(render({'hasServerSession': false}).ship, text('notInServer'));
      expect(render({}).ship, text('waitingRecognition'));
      expect(render({'serverRegion': null}).ship, text('waitingServerSync'));
      expect(render({'ship': '  C2 Hercules  '}).ship, 'C2 Hercules');
      expect(render({'ship': null}).ship, text('hidden'));
      expect(
        render({'liveStatus': 'Paused', 'ship': 'C2 Hercules'}).ship,
        text('hidden'),
      );
      expect(
        render({'arrivalPendingConfirmation': true}).location,
        text('locationPending'),
      );
      for (final placeholder in [
        'unknown',
        'NONE',
        'N/A',
        '未知',
        '未进入服务器',
        '等待识别',
      ]) {
        expect(render({'ship': placeholder}).ship, text('waitingRecognition'));
      }
    });
  }
}
