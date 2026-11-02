import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'busy.dart';
import 'field.dart';
import 'pressable.dart';
import 'suite.dart';
import 'surface_transition.dart';

/// Search input with suggestions.
///
/// - The panel opens from the input with the suite's menu entrance the
///   first time results appear; while it stays open, new results replace
///   the list in place (typing never replays the entrance).
/// - Every query gets a sequence number; a response for an older query is
///   dropped, so a slow earlier request can never overwrite a newer one.
/// - ↑/↓ move the highlight instantly, Enter picks, Esc closes (instantly).
/// - A clear button appears while there is text; clearing keeps focus in
///   the field.
/// - Waiting shows a short "searching" label above the previous results,
///   which stay listed and pickable; an empty result says so instead of
///   closing silently.
///
/// [search] is called for every change; debouncing, if any, belongs to the
/// caller.
class SuiteSearchBox extends StatefulWidget {
  const SuiteSearchBox({
    required this.search,
    required this.onPicked,
    this.hint = '搜索',
    this.panelWidth,
    super.key,
  });

  final Future<List<String>> Function(String query) search;
  final ValueChanged<String> onPicked;
  final String hint;
  final double? panelWidth;

  @override
  State<SuiteSearchBox> createState() => SuiteSearchBoxState();
}

class SuiteSearchBoxState extends State<SuiteSearchBox>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'search');
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final _anim = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s != AnimationStatus.dismissed) return;
      if (_portal.isShowing) _portal.hide();
      if (_controller.text.trim().isEmpty && mounted) {
        setState(() {
          _results = const [];
          _highlight = -1;
        });
      }
    });

  int _seq = 0;
  bool _waiting = false;
  List<String> _results = const [];
  int _highlight = -1;

  /// Replaces the query as if typed (lab demos and tests).
  void typeQuery(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Shown results (tests and lab).
  List<String> get results => _results;
  bool get isOpen =>
      _portal.isShowing && _anim.status != AnimationStatus.reverse;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
    _focus.addListener(() {
      if (!_focus.hasFocus) _close(instant: false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates && _anim.isAnimating) {
      _anim.value = _anim.status == AnimationStatus.reverse ? 0 : 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _anim.dispose();
    super.dispose();
  }

  String _lastQuery = '';

  void _onText() {
    final q = _controller.text.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;
    if (q.isEmpty) {
      // Close with the current content; it is cleared once fully closed so
      // the exit never flashes a "no results" state.
      _seq++;
      setState(() => _waiting = false);
      _close(instant: false);
      return;
    }
    final seq = ++_seq;
    setState(() => _waiting = true);
    _open();
    widget.search(q).then((r) {
      if (!mounted || seq != _seq) return; // stale response
      setState(() {
        _results = r;
        _waiting = false;
        _highlight = r.isEmpty ? -1 : _highlight.clamp(-1, r.length - 1);
      });
    });
  }

  void _open() {
    if (isOpen) return;
    final data = InteractionScope.of(context);
    final d = surfaceDurations(data, SurfaceKind.menu);
    _anim
      ..duration = d.enter
      ..reverseDuration = d.exit;
    _portal.show();
    data.animates ? _anim.forward() : _anim.value = 1;
  }

  void _close({required bool instant}) {
    if (!_portal.isShowing) return;
    if (instant || !InteractionScope.of(context).animates) {
      _anim.value = 0;
      if (_portal.isShowing) _portal.hide();
    } else {
      _anim.reverse();
    }
  }

  void _pick(int i) {
    final v = _results[i];
    widget.onPicked(v);
    _close(instant: true);
  }

  void _move(int d) {
    if (_results.isEmpty) return;
    setState(() => _highlight = (_highlight + d).clamp(0, _results.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final field = SuiteFieldFrame(
      focusNode: _focus,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(Icons.search, size: 16, color: p.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _move(-1),
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _close(instant: true),
                const SingleActivator(LogicalKeyboardKey.enter): () {
                  if (_highlight >= 0 && isOpen) _pick(_highlight);
                },
              },
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                style: TextStyle(fontSize: 13, color: p.textPrimary),
                decoration: InputDecoration.collapsed(
                  hintText: widget.hint,
                  hintStyle: TextStyle(fontSize: 13, color: p.textSecondary),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.text.isEmpty
                ? const SizedBox(width: 8)
                : SuitePressable(
                    kind: PressableKind.icon,
                    minHeight: 24,
                    padding: const EdgeInsets.all(4),
                    semanticLabel: '清空',
                    onPressed: () {
                      _controller.clear();
                      _focus.requestFocus();
                    },
                    child: const Icon(Icons.close, size: 14),
                  ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 4),
        child: Align(
          alignment: Alignment.topLeft,
          child: InteractionScope(
            data: data,
            child: TapRegion(
              groupId: _link,
              onTapOutside: (_) => _close(instant: false),
              child: SuiteSurfaceTransition(
                animation: _anim,
                kind: SurfaceKind.menu,
                radius: 7,
                child: _Panel(
                  width: widget.panelWidth ?? 260,
                  waiting: _waiting,
                  results: _results,
                  highlight: _highlight,
                  onPick: _pick,
                ),
              ),
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: TapRegion(groupId: _link, child: field),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.width,
    required this.waiting,
    required this.results,
    required this.highlight,
    required this.onPick,
  });

  final double width;
  final bool waiting;
  final List<String> results;
  final int highlight;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    return Container(
      width: width,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: suiteRadius(data.suite, 7),
        border: Border.all(color: p.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (waiting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: SuiteBusyLabel('正在搜索…'),
            ),
          // While a newer query runs, the previous results stay listed
          // (still pickable) under the searching line.
          if (!waiting && results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                '没有匹配的结果',
                style: TextStyle(fontSize: 12.5, color: p.textSecondary),
              ),
            ),
          for (var i = 0; i < results.length; i++)
            SuitePressable(
              key: ValueKey(results[i]),
              kind: PressableKind.menuItem,
              selected: i == highlight,
              baseRadius: 4,
              minHeight: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: () => onPick(i),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(results[i], style: const TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }
}
