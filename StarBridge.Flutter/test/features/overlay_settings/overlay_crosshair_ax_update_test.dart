import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_settings_ux_a_test.dart' show settings;

void main() {
  final binding = _AxUpdateBinding();

  testWidgets(
    'SDK slider control reproduces missing reparented AX child data',
    (tester) async {
      final enabled = ValueNotifier(false);
      addTearDown(enabled.dispose);
      binding.resetProbe();
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, value, _) =>
                Slider(value: .5, onChanged: value ? (_) {} : null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      binding.violations.clear();
      enabled.value = true;
      await tester.pumpAndSettle();
      // This is an intentional unfixed SDK control, not a production widget.
      // If an SDK update fixes it, remove/revisit the bounded app workaround.
      expect(binding.violations, isNotEmpty);
    },
  );

  testWidgets(
    'real crosshair controls send complete native AX updates on repeated toggles',
    (tester) async {
      size(tester, const Size(1280, 900));
      final enabled = ValueNotifier(false);
      addTearDown(enabled.dispose);
      binding.resetProbe();
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: ValueListenableBuilder<bool>(
              valueListenable: enabled,
              builder: (_, value, _) => OverlayWorkspaceSettingsGroup(
                group: 'crosshair',
                fields: overlayWorkspaceFieldSpecs
                    .where((f) => f.group == 'crosshair')
                    .toList(),
                settings: settings({
                  'showCrosshair': value,
                  'crosshairShowCenterMark': true,
                }),
                onChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(binding.violations, isEmpty);
      for (var i = 0; i < 6; i++) {
        enabled.value = !enabled.value;
        await tester.pumpAndSettle();
        expect(binding.violations, isEmpty, reason: 'toggle $i');
      }
    },
  );
}

/// Captures the actual batches sent by SemanticsOwner, rather than only the
/// final Dart tree. Mirrors the Windows bridge requirement that moving an
/// existing child to another parent must include that child's data in the batch.
class _AxUpdateBinding extends AutomatedTestWidgetsFlutterBinding {
  final _tree = <int, List<int>>{};
  final violations = <String>[];

  void resetProbe() {
    _tree.clear();
    violations.clear();
  }

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _UpdateProbe((batch) {
        final parents = <int, int>{
          for (final node in _tree.entries)
            for (final child in node.value) child: node.key,
        };
        for (final node in batch.entries) {
          for (final child in node.value) {
            if (!batch.containsKey(child) &&
                (!_tree.containsKey(child) || parents[child] != node.key)) {
              violations.add(
                'AX child $child referenced by ${node.key} without data',
              );
            }
          }
        }
        _tree.addAll(batch);
        final reachable = <int>{};
        void visit(int id) {
          if (!reachable.add(id)) return;
          for (final child in _tree[id] ?? <int>[]) {
            visit(child);
          }
        }

        visit(0);
        _tree.removeWhere((id, _) => !reachable.contains(id));
      });
}

/// Like Flutter's own SemanticsUpdateBuilder test spy, this returns an empty
/// engine update. Only non-content IDs/child lists are recorded; no user text.
class _UpdateProbe extends Fake implements ui.SemanticsUpdateBuilder {
  _UpdateProbe(this.commit);
  final void Function(Map<int, List<int>>) commit;
  final nodes = <int, List<int>>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final args = invocation.namedArguments;
      nodes[args[#id] as int] = List<int>.from(
        args[#childrenInTraversalOrder] as Iterable<int>,
      );
      return null;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) {}

  @override
  ui.SemanticsUpdate build() {
    commit(nodes);
    return ui.SemanticsUpdateBuilder().build();
  }
}
