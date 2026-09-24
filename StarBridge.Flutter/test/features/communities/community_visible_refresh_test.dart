import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_visible_refresh.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.refresh);
  final Future<void> Function() refresh;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with CommunityVisibleRefresh<_Probe> {
  @override
  Future<void> refreshVisibleCommunity() => widget.refresh();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('visible cadence is bounded and timer ends on disposal', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _Probe(() async {
          reads++;
        }),
      ),
    );
    await tester.pump(const Duration(seconds: 14));
    expect(reads, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 15));
    expect(reads, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden native viewport, menu and ticker mode pause reads', (
    tester,
  ) async {
    var reads = 0;
    final active = ValueNotifier(true);
    final ticking = ValueNotifier(true);
    addTearDown(active.dispose);
    addTearDown(ticking.dispose);
    addTearDown(() {
      nativeViewportMenus.value = 0;
    });
    final probe = _Probe(() async {
      reads++;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, visible, _) => NativeViewportScope(
            active: visible,
            child: ValueListenableBuilder<bool>(
              valueListenable: ticking,
              builder: (context, enabled, _) =>
                  TickerMode(enabled: enabled, child: probe),
            ),
          ),
        ),
      ),
    );
    active.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(reads, 0);
    active.value = true;
    ticking.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(reads, 0);
    ticking.value = true;
    nativeViewportMenus.value = 1;
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(reads, 0);
    nativeViewportMenus.value = 0;
    await tester.pump(const Duration(seconds: 15));
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inactive app pauses reads until resumed', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _Probe(() async {
          reads++;
        }),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 15));
    expect(reads, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(reads, 1); // Resume immediately; do not wait for a manual refresh.
    await tester.pump(const Duration(seconds: 15));
    expect(reads, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('modal detail refreshes while the covered list pauses', (
    tester,
  ) async {
    var listReads = 0, detailReads = 0;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: _Probe(() async {
          listReads++;
        }),
      ),
    );
    final dialog = showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => Dialog(
        child: _Probe(() async {
          detailReads++;
        }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 15));
    expect(listReads, 0);
    expect(detailReads, 1);
    navigator.currentState!.pop();
    await dialog;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 15));
    expect(listReads, 1);
    expect(detailReads, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
