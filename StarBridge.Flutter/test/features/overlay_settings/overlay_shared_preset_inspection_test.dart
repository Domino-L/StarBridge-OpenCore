import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_inspection_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_import_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_transfer.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import '../communities/community_preset_test.dart' show PresetFake;
import '../communities/community_preset_dialog_test.dart' show open;
import 'overlay_settings_ux_a_test.dart' show settings;
import 'overlay_preset_transfer_test.dart' show layout;

class _InspectingPort extends PresetFake implements OverlayPresetInspectionPort {
  int inspections = 0;
  bool failInspection = false;
  Completer<OverlayPresetTransfer>? pending;
  @override
  Future<OverlayPresetTransfer> inspectPreset(String package, int revision) async {
    inspections++;
    if (failInspection) throw const FormatException();
    return pending?.future ?? OverlayPresetTransfer(name: 'Shared fixture', settings: settings(), layout: layout,
      sources: OverlayPresetSources(binding: const OverlaySourceBinding.room()), removedOrganizationBindings: true);
  }
}

void main() {
  testWidgets('chat inspection cancel has no writes; confirm imports only once', (tester) async {
    final port = _InspectingPort();
    addTearDown(port.changes.close);
    await open(tester, port, importing: true);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导入为新预设'));
    // The blocked parent keeps its progress indicator while the modal is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(port.inspections, 1);
    expect(port.imports, 0);
    expect(find.byType(OverlayPresetImportPreview), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(port.imports, 0);
    await tester.tap(find.widgetWithText(FilledButton, '导入为新预设'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const Key('overlay-import-confirm')));
    await tester.pumpAndSettle();
    expect(port.inspections, 2);
    expect(port.imports, 1);
    expect(find.text('已新增预设: Fixture'), findsOneWidget);
  });
  testWidgets('account invalidation rejects late inspection before any write', (tester) async {
    final port = _InspectingPort()..pending = Completer();
    addTearDown(port.changes.close);
    await open(tester, port, importing: true);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导入为新预设'));
    await tester.pump();
    port.changes.add(null);
    port.pending!.complete(OverlayPresetTransfer(name: 'Late', settings: settings(), layout: layout));
    await tester.pumpAndSettle();
    expect(port.imports, 0);
    expect(find.byType(OverlayPresetImportPreview), findsNothing);
  });
  testWidgets('failed read-only inspection permits retry and does not claim uncertain import', (tester) async {
    final port = _InspectingPort()..failInspection = true;
    addTearDown(port.changes.close);
    await open(tester, port, importing: true);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导入为新预设'));
    await tester.pumpAndSettle();
    expect(port.imports, 0);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('避免重复导入'), findsNothing);
  });
}
