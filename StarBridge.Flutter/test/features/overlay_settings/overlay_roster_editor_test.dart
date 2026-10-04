import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_roster_editor.dart';

class _Port implements OverlayRosterPort {
  final events = StreamController<void>.broadcast();
  final writes = <String>[];
  String mode = 'auto';
  bool revoked = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<Map<String, Object?>> request([
    int? revision,
    String? key,
    String? next,
  ]) async {
    if (revision != null) {
      writes.add('$revision:$key:$next');
      mode = next!;
    }
    return {
      'schemaVersion': 1,
      'revision': writes.length,
      'rows': revoked
          ? []
          : [
              {'key': 'synthetic-key', 'name': 'Visible member', 'mode': mode},
            ],
    };
  }
}

void main() {
  testWidgets(
    'member choice persists through the port and account invalidation clears rows',
    (tester) async {
      final port = _Port();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OverlayRosterButton(port: port)),
        ),
      );
      await tester.tap(find.text('Choose visible members'));
      await tester.pumpAndSettle();
      expect(find.text('Visible member'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin').last);
      await tester.pumpAndSettle();
      expect(port.writes, ['0:synthetic-key:pin']);
      port.revoked = true;
      port.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Visible member'), findsNothing);
      expect(
        find.text('No members are available in this scene.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await port.events.close();
    },
  );
}
