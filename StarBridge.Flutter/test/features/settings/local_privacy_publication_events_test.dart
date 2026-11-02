import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';

import 'local_privacy_page_test.dart' show PublishingPrivacy;

class EventPublishingPrivacy extends PublishingPrivacy
    implements PrivacyPublicationChangePort {
  EventPublishingPrivacy({required this.publicationEventsSupported});
  final changes = StreamController<void>.broadcast();
  @override
  final bool publicationEventsSupported;
  @override
  Stream<void> get publicationChanges => changes.stream;
  int get statusReads => actions.where((a) => a == 'status').length;
}

void main() {
  testWidgets(
    'status light re-reads on Host change events instead of polling',
    (tester) async {
      final port = EventPublishingPrivacy(publicationEventsSupported: true);
      final controller = LocalPrivacyController(port);
      final release = controller.monitorPublication();
      await tester.pump(const Duration(seconds: 1));
      final settled = port.statusReads;

      await tester.pump(const Duration(seconds: 30));
      expect(
        port.statusReads,
        settled,
        reason: 'With change events there is no 5 s polling.',
      );

      port.changes
        ..add(null)
        ..add(null)
        ..add(null);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        port.statusReads,
        settled + 1,
        reason: 'A burst of change events causes one coalesced re-read.',
      );

      await tester.pump(const Duration(seconds: 61));
      expect(
        port.statusReads,
        settled + 2,
        reason: 'A slow fallback still covers a missed event.',
      );

      release();
      port.changes.add(null);
      await tester.pump(const Duration(seconds: 1));
      expect(
        port.statusReads,
        settled + 2,
        reason: 'Released monitoring ignores further events.',
      );
      controller.dispose();
      await port.changes.close();
    },
  );

  testWidgets('hosts without change events keep the 5 s status poll', (
    tester,
  ) async {
    final port = EventPublishingPrivacy(publicationEventsSupported: false);
    final controller = LocalPrivacyController(port);
    final release = controller.monitorPublication();
    await tester.pump(const Duration(seconds: 1));
    final settled = port.statusReads;
    await tester.pump(const Duration(seconds: 30));
    expect(port.statusReads, greaterThanOrEqualTo(settled + 5));
    release();
    controller.dispose();
    await port.changes.close();
  });
}
