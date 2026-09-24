import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_port.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

CommunityShipReportIntent intent({
  String reason = 'spam',
  String details = '',
}) => CommunityShipReportIntent(
  targetRef: 'a' * 32,
  shipRef: 'b' * 32,
  version: 'c' * 64,
  requestId: 'd' * 32,
  reason: reason,
  details: details,
);
Map<String, Object?> receipt() => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'shipRef': 'b' * 32,
  'requestId': 'd' * 32,
  'status': 'accepted',
  'error': null,
};
void main() {
  test(
    'recovery sends a read-only flag for the unchanged original intent',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.reportShipImage'],
        responses: {'communities.reportShipImage': receipt()},
      );
      addTearDown(host.close);
      expect((await host.adapter.checkShipReport(intent())).status, 'accepted');
      final request = host.requests
          .where((r) => r.name == 'communities.reportShipImage')
          .single;
      expect(request.payload, {
        'schemaVersion': 1,
        ...intent().toPayload(),
        'checkOnly': true,
      });
    },
  );
  test(
    'formal report sends current scoped image version and no media identity',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.reportShipImage'],
        responses: {'communities.reportShipImage': receipt()},
      );
      addTearDown(host.close);
      expect(host.adapter.shipReportAvailable, isTrue);
      expect((await host.adapter.reportShipImage(intent())).status, 'accepted');
      final request = host.requests
          .where((r) => r.name == 'communities.reportShipImage')
          .single;
      expect(request.payload, {'schemaVersion': 1, ...intent().toPayload()});
      expect(request.accountContext?.subject, 'test-subject');
    },
  );
  test('missing capability never sends a report', () async {
    final host = CommunityHarness(capabilities: []);
    addTearDown(host.close);
    expect(host.adapter.shipReportAvailable, isFalse);
    expect((await host.adapter.reportShipImage(intent())).status, 'rejected');
    expect(host.requests, isEmpty);
  });
  for (final key in [
    'schemaVersion',
    'targetRef',
    'shipRef',
    'requestId',
    'status',
    'error',
  ]) {
    test('malformed $key receipt is unknown and never retried', () async {
      final row = receipt()..[key] = 'bad';
      final host = CommunityHarness(
        capabilities: ['communities.reportShipImage'],
        responses: {'communities.reportShipImage': row},
      );
      addTearDown(host.close);
      expect((await host.adapter.reportShipImage(intent())).status, 'unknown');
      expect(
        host.requests
            .where((r) => r.name == 'communities.reportShipImage')
            .length,
        1,
      );
    });
  }
  for (final status in ['rejected', 'unknown']) {
    test('$status remains explicit', () {
      final row = receipt()
        ..['status'] = status
        ..['error'] = status == 'unknown' ? 'outcomeUnknown' : 'notAllowed';
      expect(CommunityShipReportOutcome.parse(row, intent()).status, status);
    });
  }
  test('reason and details bounds use existing report contract', () {
    expect(() => intent(reason: 'invalid'), throwsFormatException);
    expect(() => intent(details: 'a' * 1001), throwsFormatException);
    expect(() => intent(details: '\u0000'), throwsFormatException);
    expect(intent(details: ' note\ntext ').details, 'note\ntext');
  });
}
