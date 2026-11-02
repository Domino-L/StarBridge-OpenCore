import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The four interaction suites. Content, layout and hit areas are identical
/// across suites; only the feedback differs.
enum InteractionSuite {
  /// The current client behaviour: Material ink ripple and plain fades.
  standard,

  /// Lines travel along a track, stretch, then settle onto the target.
  rail,

  /// Align, sweep and lock: corner brackets, a passing beam, line reveals.
  scan,

  /// Light up locally, ripple once, settle into a quiet glow.
  glow,
}

/// Colours the suites paint with. The host maps its own design tokens onto
/// this so the package never depends on the client's token classes.
@immutable
class InteractionPalette {
  const InteractionPalette({
    required this.brightness,
    required this.accent,
    required this.accentBright,
    required this.onAccent,
    required this.selectedFill,
    required this.surface,
    required this.raised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.focusRing,
    required this.success,
    required this.onSuccess,
    required this.danger,
    required this.onDanger,
    required this.warning,
  });

  final Brightness brightness;

  /// Primary accent (buttons, rails, selected markers).
  final Color accent;

  /// Brighter accent used for lit edges and beams on dark surfaces. On light
  /// surfaces hosts usually pass a deeper accent here so lines stay crisp.
  final Color accentBright;
  final Color onAccent;
  final Color selectedFill;
  final Color surface;
  final Color raised;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color focusRing;
  final Color success;
  final Color onSuccess;
  final Color danger;
  final Color onDanger;
  final Color warning;

  bool get isDark => brightness == Brightness.dark;

  /// Accent at [alpha] for soft light. Light themes get a stronger base
  /// because faint blue disappears on pale surfaces.
  Color light(double alpha) =>
      accent.withValues(alpha: (isDark ? alpha : alpha * 0.75).clamp(0, 1));

  /// Lit-edge colour at [alpha].
  Color edge([double alpha = 1]) => accentBright.withValues(alpha: alpha);
}

/// Timing for one suite. Values follow the design brief ranges; navigation
/// keeps the approved 300 ms slide.
@immutable
class SuiteMotion {
  const SuiteMotion({
    required this.hover,
    required this.press,
    required this.select,
    required this.navigate,
    required this.stretch,
    required this.fade,
    required this.sweep,
    required this.ring,
    required this.ringDelay,
    required this.enter,
    required this.exit,
    required this.flash,
  });

  /// Hover colour and short line hand-off (brief: 80–160 ms).
  final Duration hover;

  /// Press highlight release. The highlight itself appears on the next frame.
  final Duration press;

  /// Small control hand-off: switch, checkbox, tabs, segmented. All four
  /// suites sit in 160–200 ms (QualityPass ⑤, user 2026-10-29).
  final Duration select;

  /// Side navigation indicator slide (approved 300 ms).
  final Duration navigate;

  /// Rail: first phase where the indicator stretches over old and new.
  final Duration stretch;

  /// Scan: the old indicator fades before the new one locks.
  final Duration fade;

  /// Scan: beam and scan line pass (tail, never blocks input).
  final Duration sweep;

  /// Glow: ripple ring tail.
  final Duration ring;

  /// Glow: delay from slide start to the landing ripple.
  final Duration ringDelay;

  /// Menu, dialog and toast entrance (180–320 ms).
  final Duration enter;

  /// Closing (90–160 ms).
  final Duration exit;

  /// Row and panel data-update flash tail.
  final Duration flash;

  static const curve = Cubic(0.2, 0, 0, 1);
  static const exitCurve = Cubic(0.4, 0, 1, 1);

  static const standard = SuiteMotion(
    hover: Duration(milliseconds: 120),
    press: Duration(milliseconds: 120),
    select: Duration(milliseconds: 160),
    navigate: Duration.zero,
    stretch: Duration.zero,
    fade: Duration.zero,
    sweep: Duration.zero,
    ring: Duration.zero,
    ringDelay: Duration.zero,
    enter: Duration(milliseconds: 220),
    exit: Duration(milliseconds: 140),
    flash: Duration.zero,
  );

  static const rail = SuiteMotion(
    hover: Duration(milliseconds: 140),
    press: Duration(milliseconds: 140),
    select: Duration(milliseconds: 200),
    navigate: Duration(milliseconds: 300),
    stretch: Duration(milliseconds: 150),
    fade: Duration.zero,
    sweep: Duration.zero,
    ring: Duration.zero,
    ringDelay: Duration.zero,
    enter: Duration(milliseconds: 260),
    exit: Duration(milliseconds: 140),
    flash: Duration(milliseconds: 900),
  );

  static const scan = SuiteMotion(
    hover: Duration(milliseconds: 140),
    press: Duration(milliseconds: 140),
    select: Duration(milliseconds: 160),
    navigate: Duration.zero,
    stretch: Duration.zero,
    fade: Duration(milliseconds: 90),
    sweep: Duration(milliseconds: 460),
    ring: Duration.zero,
    ringDelay: Duration.zero,
    enter: Duration(milliseconds: 300),
    exit: Duration(milliseconds: 160),
    flash: Duration(milliseconds: 700),
  );

  static const glow = SuiteMotion(
    hover: Duration(milliseconds: 140),
    press: Duration(milliseconds: 140),
    select: Duration(milliseconds: 200),
    navigate: Duration(milliseconds: 300),
    stretch: Duration.zero,
    fade: Duration.zero,
    sweep: Duration.zero,
    ring: Duration(milliseconds: 560),
    ringDelay: Duration(milliseconds: 200),
    enter: Duration(milliseconds: 280),
    exit: Duration(milliseconds: 130),
    flash: Duration(milliseconds: 900),
  );

  static SuiteMotion of(InteractionSuite suite) => switch (suite) {
    InteractionSuite.standard => standard,
    InteractionSuite.rail => rail,
    InteractionSuite.scan => scan,
    InteractionSuite.glow => glow,
  };
}

/// Resolved interaction settings for a subtree.
@immutable
class InteractionData {
  const InteractionData({
    required this.suite,
    required this.palette,
    this.reduceMotion = false,
  });

  final InteractionSuite suite;
  final InteractionPalette palette;

  /// True when the system or the app asks for reduced motion. Every effect
  /// then jumps to its final static state.
  final bool reduceMotion;

  SuiteMotion get motion => SuiteMotion.of(suite);

  /// Whether decorative movement may play.
  bool get animates => !reduceMotion;

  /// [d] or zero under reduced motion.
  Duration timed(Duration d) => reduceMotion ? Duration.zero : d;

  /// For [AnimatedSize]: [d], or a single-frame resize under reduced motion.
  /// AnimatedSize cannot take [Duration.zero] (it would finish inside its
  /// own layout), and switching it out would remount its child.
  Duration sizeDuration(Duration d) =>
      reduceMotion ? const Duration(microseconds: 1) : d;

  InteractionData copyWith({
    InteractionSuite? suite,
    InteractionPalette? palette,
    bool? reduceMotion,
  }) => InteractionData(
    suite: suite ?? this.suite,
    palette: palette ?? this.palette,
    reduceMotion: reduceMotion ?? this.reduceMotion,
  );

  @override
  bool operator ==(Object other) =>
      other is InteractionData &&
      other.suite == suite &&
      other.palette == palette &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(suite, palette, reduceMotion);
}

/// Provides [InteractionData] to the controls below it. Reduced motion is
/// also forced on when [MediaQueryData.disableAnimations] is set.
///
/// Surfaces mounted outside this subtree (dialog routes, overlay menus)
/// follow it live through [InteractionScope.relay], so a suite, palette or
/// reduced-motion change reaches a surface that is already open.
class InteractionScope extends StatefulWidget {
  const InteractionScope({required this.data, required this.child, super.key});

  final InteractionData data;
  final Widget child;

  static InteractionData of(BuildContext context) {
    final data = maybeOf(context);
    assert(data != null, 'No InteractionScope above this control.');
    return data!;
  }

  /// Like [of] but returns null when there is no scope above [context].
  static InteractionData? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ScopeData>();
    if (scope == null) return null;
    final data = scope.data;
    final systemReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return systemReduced && !data.reduceMotion
        ? data.copyWith(reduceMotion: true)
        : data;
  }

  /// The live, effective settings at [context], without depending on it:
  /// the scope's data merged with the reduced-motion setting of the
  /// [MediaQuery] around [context] (which may be a local one below the
  /// navigator). Follows both while anything listens. Null when there is no
  /// scope above [context].
  static ValueListenable<InteractionData>? linkOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_ScopeData>();
    if (scope == null) return null;
    return _OriginLink(scope.link, context);
  }

  /// Number of origin links currently following their caller. For tests:
  /// returns to zero once every relayed surface has closed.
  @visibleForTesting
  static int get debugLiveLinks => _OriginLink._live;

  /// Caller-setting checks run by all origin links so far. For tests: while
  /// one surface is open, exactly one runs per drawn frame.
  @visibleForTesting
  static int get debugLinkChecks => _OriginLink.debugChecks;

  /// Re-provides the scope around [origin] to [child], which is mounted
  /// somewhere else (an overlay entry, a route), and keeps following it.
  /// Without a scope around [origin] nothing is added.
  static Widget relay(BuildContext origin, {required Widget child}) {
    final link = linkOf(origin);
    if (link == null) return child;
    return follow(link, child: child);
  }

  /// Provides the live value of [link] (from [linkOf]) to [child].
  static Widget follow(
    ValueListenable<InteractionData> link, {
    required Widget child,
  }) => _ScopeRelay(link: link, child: child);

  @override
  State<InteractionScope> createState() => _InteractionScopeState();
}

class _InteractionScopeState extends State<InteractionScope> {
  late final _link = ValueNotifier<InteractionData>(widget.data);

  @override
  void didUpdateWidget(InteractionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _link.value = widget.data;
  }

  // The link is deliberately not disposed: a relay in a dialog may outlive
  // this scope (the page behind it switched) and simply keeps the last value.

  @override
  Widget build(BuildContext context) =>
      _ScopeData(data: widget.data, link: _link, child: widget.child);
}

class _ScopeData extends InheritedWidget {
  const _ScopeData({
    required this.data,
    required this.link,
    required super.child,
  });

  final InteractionData data;
  final ValueListenable<InteractionData> link;

  @override
  bool updateShouldNotify(_ScopeData oldWidget) => data != oldWidget.data;
}

/// The effective settings at one caller: scope data (pushed by the scope)
/// plus the caller's MediaQuery reduced-motion flag. MediaQuery has no
/// listener API from outside the caller's subtree, so while listened to the
/// link re-reads it after every drawn frame (a MediaQuery change always
/// rebuilds, hence draws a frame); it never schedules frames itself, so an
/// idle window costs nothing.
class _OriginLink extends ChangeNotifier
    implements ValueListenable<InteractionData> {
  _OriginLink(this._scope, this._origin) : _reduced = _read(_origin) ?? false;

  static int _live = 0;

  final ValueListenable<InteractionData> _scope;
  final BuildContext _origin;
  bool _reduced;
  bool _watching = false;

  /// A post-frame check is pending. At most one is ever queued, so a quick
  /// unsubscribe → resubscribe (before the pending one ran) does not start
  /// a second chain.
  bool _scheduled = false;

  static int debugChecks = 0;

  static bool? _read(BuildContext origin) {
    if (!origin.mounted) return null;
    return origin.getInheritedWidgetOfExactType<MediaQuery>()?.data
            .disableAnimations ??
        false;
  }

  @override
  InteractionData get value {
    final data = _scope.value;
    return _reduced && !data.reduceMotion
        ? data.copyWith(reduceMotion: true)
        : data;
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_watching) return;
    _watching = true;
    _live++;
    _reduced = _read(_origin) ?? _reduced;
    _scope.addListener(notifyListeners);
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback(_check);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!_watching || hasListeners) return;
    _watching = false;
    _live--;
    _scope.removeListener(notifyListeners);
  }

  void _check(Duration _) {
    _scheduled = false;
    if (!_watching) return;
    debugChecks++;
    // The caller left the tree: keep the last known setting.
    final now = _read(_origin);
    if (now != null && now != _reduced) {
      _reduced = now;
      notifyListeners();
    }
    _schedule();
  }
}

class _ScopeRelay extends StatefulWidget {
  const _ScopeRelay({required this.link, required this.child});

  final ValueListenable<InteractionData> link;
  final Widget child;

  @override
  State<_ScopeRelay> createState() => _ScopeRelayState();
}

class _ScopeRelayState extends State<_ScopeRelay> {
  @override
  void initState() {
    super.initState();
    widget.link.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ScopeRelay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link) {
      oldWidget.link.removeListener(_changed);
      widget.link.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.link.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    // The scope changes while its own subtree builds; this relay sits
    // elsewhere in the tree, so it rebuilds right after that frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      SchedulerBinding.instance.ensureVisualUpdate();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => _ScopeData(
    data: widget.link.value,
    link: widget.link,
    child: widget.child,
  );
}

/// Where an interaction came from. Keyboard-initiated changes go straight to
/// their final state; focus feedback stays.
enum InteractionSource { pointer, keyboard, programmatic }

/// Corner radius per suite: scan is deliberately harder-edged.
BorderRadius suiteRadius(InteractionSuite suite, double base) =>
    BorderRadius.circular(suite == InteractionSuite.scan ? 2 : base);
