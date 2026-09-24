import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_port.dart';

// Compatibility contract retained while catalog-only UI has no report entry.
class _Port implements CommunityShipReportPort {
  @override
  bool get shipReportAvailable => true;
  int reports = 0, checks = 0;
  CommunityShipReportIntent? submitted;
  @override
  Future<CommunityShipReportOutcome> reportShipImage(
    CommunityShipReportIntent intent,
  ) async {
    reports++;
    submitted = intent;
    return const CommunityShipReportOutcome('unknown', error: 'outcomeUnknown');
  }

  @override
  Future<CommunityShipReportOutcome> checkShipReport(
    CommunityShipReportIntent intent,
  ) async {
    checks++;
    expect(identical(intent, submitted), isTrue);
    return const CommunityShipReportOutcome('rejected', error: 'busy');
  }
}

void main() {
  test(
    'retained report protocol never resubmits an unknown legacy intent',
    () async {
      final port = _Port();
      final model = CommunityShipReportController(
        port,
        'a' * 32,
        'c' * 32,
        'd' * 64,
      );
      addTearDown(model.dispose);
      model.edit('spam', 'original');
      await model.submit();
      model.edit('other', 'changed');
      await model.submit();
      await model.check();
      expect(model.unknown, isTrue);
      expect(model.details, 'original');
      expect(port.reports, 1);
      expect(port.checks, 1);
    },
  );
}
