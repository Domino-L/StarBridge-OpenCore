import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'guide_controller.dart';
import 'guide_tour_layer.dart';
import 'guide_tours.dart';
import 'guide_windows_notice.dart';

/// A running tour: which spec, which step, and what it belongs to — the
/// profile context ([epoch]) and the page it started on ([route]).
@immutable
final class GuideTourRun {
  const GuideTourRun(this.spec, this.index, {required this.epoch, this.route});
  final GuideTourSpec spec;
  final int index;
  final int epoch;
  final String? route;
  GuideTourStep get step => spec.steps[index];
  bool get last => index == spec.steps.length - 1;
  GuideTourRun at(int index) =>
      GuideTourRun(spec, index, epoch: epoch, route: route);
}

/// Page visits that complete a checklist item.
const _visitDone = {
  '/fleet': 'fleet',
  '/overlay': 'overlay',
  '/tools': 'tools',
  '/achievements': 'achievements',
};

/// App-wide guide state: anchors on screen, the running tour and the current
/// route. Never acts on behalf of the user; it only highlights and navigates.
final class GuideHub {
  GuideHub({
    required this.controller,
    required this.online,
    required this.navigate,
    ValueListenable<bool>? localMode,
    this.windowsNotice,
  }) : localMode = localMode ?? ValueNotifier(false) {
    controller.addListener(_stateChanged);
    _epoch = controller.epoch;
  }

  final GuideController controller;
  final ValueListenable<bool> online;

  /// The device is in local mode (not merely signed out of an online account).
  final ValueListenable<bool> localMode;
  final void Function(String route) navigate;

  /// Windows notifications switch; null when this device has none.
  final GuideWindowsNoticePort? windowsNotice;

  /// Session only: the checklist sent the user to the notifications card.
  final windowsNoticeRequested = ValueNotifier(false);

  /// Session only: the card turned it on, so it stays to offer a test.
  final windowsNoticeEnabledHere = ValueNotifier(false);
  final run = ValueNotifier<GuideTourRun?>(null);
  final _anchors = <String, GlobalKey>{};

  /// Auto-starts already attempted during the current visit and context.
  final _autoTried = <String>{};
  String? _route;
  int _epoch = 0;
  Set<String> _seen = const {};

  /// Bumps when anchors come or go so the layer re-measures.
  final anchorsChanged = ValueNotifier<int>(0);

  GlobalKey? anchor(String id) => _anchors[id];

  bool _disposed = false;

  void register(String id, GlobalKey key) {
    if (_disposed) return;
    _anchors[id] = key;
    anchorsChanged.value++;
  }

  void unregister(String id, GlobalKey key) {
    if (_disposed || _anchors[id] != key) return;
    _anchors.remove(id);
    anchorsChanged.value++;
  }

  void visit(String route) {
    if (route != _route) {
      _autoTried.clear();
      // The notifications card is for this visit; leaving retires it.
      if (_route == '/notifications') {
        windowsNoticeRequested.value = false;
        windowsNoticeEnabledHere.value = false;
      }
      // Leaving the page a tour belongs to ends it: a page tour counts as
      // seen (the user moved on), a do-it tour does not (its flow is gone).
      final current = run.value;
      if (current != null && current.route != null && current.route != route) {
        current.spec.kind == GuideTourKind.tour ? finish() : _drop();
      }
    }
    _route = route;
    final done = _visitDone[route];
    if (done != null) controller.markDone(done);
    _maybeAutoStart();
  }

  void _stateChanged() {
    final state = controller.value;
    // A profile switch or an unavailable Host ends whatever was running for
    // the old profile and forgets its attempts; nothing carries over.
    if (controller.epoch != _epoch || !state.available) {
      _epoch = controller.epoch;
      _autoTried.clear();
      _drop();
      windowsNoticeRequested.value = false;
      windowsNoticeEnabledHere.value = false;
    }
    // "Show tips again" in Settings brings automatic tours back too.
    if (!state.seen.containsAll(_seen)) _autoTried.clear();
    _seen = state.seen;
    _maybeAutoStart();
  }

  /// Whether [spec] may start now for the current profile and page. Checked
  /// again when a deferred start runs, so nothing queued for an old context
  /// or page can start later.
  bool _mayAutoStart(GuideTourSpec spec, int epoch, String? route) {
    final state = controller.value;
    return !_disposed &&
        controller.epoch == epoch &&
        state.available &&
        state.eligible &&
        !state.seen.contains(spec.seenId) &&
        run.value == null &&
        _route == route;
  }

  void _defer(bool Function() valid, VoidCallback start) {
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (valid()) start();
    });
  }

  void _maybeAutoStart() {
    final epoch = controller.epoch, route = _route;
    for (final spec in guideTours.values) {
      // Do-it tours have no route: their first business event starts them.
      if (spec.route == null || spec.route != route) continue;
      if (!_mayAutoStart(spec, epoch, route)) continue;
      if (!_autoTried.add(spec.id)) continue;
      _defer(() => _mayAutoStart(spec, epoch, route), () => start(spec.id));
    }
  }

  /// A page reports a business event after it really happened (reader
  /// opened, read finished, saved, created). The running tour jumps to the
  /// step after the one this event completes — also when it arrives early
  /// (e.g. the form was filled and created in one go). Without a tour, the
  /// first event of a do-it tour starts it at step 2 (eligible, unseen only).
  void report(String event) {
    if (_disposed) return;
    final current = run.value;
    if (current != null) {
      final steps = current.spec.steps;
      for (var k = current.index; k < steps.length; k++) {
        if (steps[k].until != event) continue;
        _defer(
          () => !_disposed && identical(run.value, current),
          () =>
              k + 1 >= steps.length ? finish() : run.value = current.at(k + 1),
        );
        return;
      }
      return;
    }
    final epoch = controller.epoch, route = _route;
    for (final spec in guideTours.values) {
      if (spec.kind != GuideTourKind.doIt) continue;
      if (spec.steps.first.until != event) continue;
      if (!_mayAutoStart(spec, epoch, route)) return;
      // The start belongs to this flow instance: closing the flow before the
      // deferred start runs (reader left, form cancelled) voids it.
      final flow = spec.steps.length > 1 ? spec.steps[1].flow : null;
      final instance = _flowInstance[flow] ?? 0;
      _defer(
        () =>
            _mayAutoStart(spec, epoch, route) &&
            (_flowInstance[flow] ?? 0) == instance,
        () => start(spec.id, at: 1),
      );
      return;
    }
  }

  /// Bumps each time a flow instance closes; deferred starts compare it.
  final _flowInstance = <String?, int>{};

  /// A business flow instance went away without finishing (form cancelled,
  /// reader left): a tour step that needs it ends the tour, unseen.
  void flowClosed(String flow) {
    if (_disposed) return;
    _flowInstance[flow] = (_flowInstance[flow] ?? 0) + 1;
    final current = run.value;
    if (current != null && current.step.flow == flow) _drop();
  }

  void start(String tourId, {int at = 0}) {
    final spec = guideTours[tourId];
    if (spec == null || _disposed || !controller.value.available) return;
    run.value = GuideTourRun(
      spec,
      at.clamp(0, spec.steps.length - 1),
      epoch: controller.epoch,
      route: _route,
    );
  }

  void next() {
    final current = run.value;
    if (current == null) return;
    if (current.last) return finish();
    run.value = current.at(current.index + 1);
  }

  void back() {
    final current = run.value;
    if (current == null || current.index == 0) return;
    run.value = current.at(current.index - 1);
  }

  /// Skip, exit and finish all retire the tour and its page tip.
  void finish() {
    final current = run.value;
    if (current == null) return;
    run.value = null;
    controller.markSeen(current.spec.seenId);
    controller.markSeen('tip.${current.spec.id}');
  }

  /// Ends the tour without recording it (its context or flow is gone).
  void _drop() => run.value = null;

  void dispose() {
    _disposed = true;
    controller.removeListener(_stateChanged);
    run.dispose();
    anchorsChanged.dispose();
    windowsNoticeRequested.dispose();
    windowsNoticeEnabledHere.dispose();
  }
}

class GuideScope extends StatelessWidget {
  const GuideScope({required this.hub, required this.child, super.key});
  final GuideHub? hub;
  final Widget child;

  static GuideHub? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GuideInherited>()?.hub;

  @override
  Widget build(BuildContext context) {
    final hub = this.hub;
    if (hub == null) return child;
    return _GuideInherited(
      hub: hub,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          GuideTourLayer(hub: hub),
        ],
      ),
    );
  }
}

class _GuideInherited extends InheritedWidget {
  const _GuideInherited({required this.hub, required super.child});
  final GuideHub hub;
  @override
  bool updateShouldNotify(_GuideInherited old) => old.hub != hub;
}

/// Marks a widget a tour can highlight. Position only: completing a step is
/// reported by the page's own success callbacks ([GuideHub.report]).
class GuideAnchor extends StatefulWidget {
  const GuideAnchor({required this.id, required this.child, super.key});
  final String id;
  final Widget child;

  @override
  State<GuideAnchor> createState() => _GuideAnchorState();
}

class _GuideAnchorState extends State<GuideAnchor> {
  final _key = GlobalKey();
  GuideHub? _hub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hub = GuideScope.maybeOf(context);
    if (identical(hub, _hub)) return;
    _hub?.unregister(widget.id, _key);
    _hub = hub?..register(widget.id, _key);
  }

  @override
  void didUpdateWidget(GuideAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _hub?.unregister(old.id, _key);
      _hub?.register(widget.id, _key);
    }
  }

  @override
  void dispose() {
    _hub?.unregister(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hub == null) return widget.child;
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

/// Reports a guide event from a page's success path; no-op without a guide.
/// Safe from async callbacks: no dependency, ignored once unmounted.
void guideReport(BuildContext context, String event) {
  if (!context.mounted) return;
  context.getInheritedWidgetOfExactType<_GuideInherited>()?.hub.report(event);
}

/// A flow instance (form, reader) closed without finishing; see
/// [GuideHub.flowClosed]. Safe from dispose (no dependency lookup).
void guideFlowClosed(GuideHub? hub, String flow) => hub?.flowClosed(flow);

/// Completes a checklist item once [when] is true (e.g. the hangar has ships).
class GuideSignal extends StatefulWidget {
  const GuideSignal({
    required this.id,
    required this.when,
    required this.child,
    super.key,
  });
  final String id;
  final bool when;
  final Widget child;

  @override
  State<GuideSignal> createState() => _GuideSignalState();
}

class _GuideSignalState extends State<GuideSignal> {
  @override
  Widget build(BuildContext context) {
    if (widget.when) {
      final controller = GuideScope.maybeOf(context)?.controller;
      if (controller != null && !controller.value.done.contains(widget.id)) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => controller.markDone(widget.id),
        );
      }
    }
    return widget.child;
  }
}
