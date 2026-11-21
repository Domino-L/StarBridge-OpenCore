import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'tools_style.dart';
import 'cached_exec_hangar.dart';
import 'exec_hangar_overview.dart';
import 'mission_records_controller.dart';

import 'tools_snapshot_cache.dart';

/// Only the cached hangar display ticks; sibling cards keep their widgets.
class ToolsHangarCardData extends StatefulWidget {
  const ToolsHangarCardData({super.key, this.hangar, required this.records});
  final CachedExecHangar? hangar;
  final MissionRecordsController records;

  @override
  State<ToolsHangarCardData> createState() => _ToolsHangarCardDataState();
}

class _ToolsHangarCardDataState extends State<ToolsHangarCardData> {
  late final Timer _ticker;
  bool _loading = false, _failed = false;
  int _generation = 0;
  DateTime? _boundary, _attemptedBoundary;

  @override
  void initState() {
    super.initState();
    _scheduleBoundary();
    if (widget.hangar != null && !widget.hangar!.fresh) unawaited(_read());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ModalRoute.of(context)?.isCurrent == false) return;
      final hangar = widget.hangar, boundary = _boundary;
      if (hangar?.snapshot == null) return;
      final now = hangar!.snapshot!.now.add(hangar.age);
      if (!_loading && boundary != null && !now.isBefore(boundary)) {
        // Consume before reading: failure or a repeated old window must not
        // turn the local countdown ticker into a once-per-second request loop.
        _attemptedBoundary = boundary;
        _boundary = null;
        unawaited(_read());
      }
      setState(() {});
    });
  }

  void _scheduleBoundary() {
    final hangar = widget.hangar, snapshot = widget.hangar?.snapshot;
    _boundary = null;
    if (snapshot == null || !snapshot.reliable || snapshot.refreshFailed) {
      return;
    }
    final now = snapshot.now.add(hangar!.age);
    // Lamps can change between phases already in the snapshot. Refresh only
    // at open/close boundaries. Skip consumed boundaries, not the whole schedule
    // when a reply still describes the window we just crossed.
    bool unattempted(DateTime boundary) =>
        boundary.isAfter(now) &&
        (_attemptedBoundary == null || boundary.isAfter(_attemptedBoundary!));
    final boundaries =
        snapshot.windows
            .expand((w) => [w.open, w.close])
            .where(unattempted)
            .toList()
          ..sort();
    final phase = snapshot.phases
        .where((p) => !now.isBefore(p.start) && now.isBefore(p.end))
        .firstOrNull;
    _boundary =
        boundaries.firstOrNull ??
        (phase != null && unattempted(phase.end) ? phase.end : null);
  }

  Future<void> _read() async {
    if (_loading || widget.hangar == null || !mounted) return;
    final generation = _generation, hangar = widget.hangar!;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      // Use the same normal read as the dedicated page; the cache coalesces it.
      await hangar.read();
      if (!mounted || generation != _generation) return;
      _scheduleBoundary();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _failed = true;
      _scheduleBoundary();
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void didUpdateWidget(ToolsHangarCardData oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hangar == widget.hangar) return;
    _generation++;
    _loading = _failed = false;
    _attemptedBoundary = null;
    _scheduleBoundary();
    if (widget.hangar != null && !widget.hangar!.fresh) unawaited(_read());
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ToolsCardData(
    id: 'exec-hangar',
    hangar: widget.hangar,
    records: widget.records,
    hangarLoading: _loading,
    hangarFailed: _failed,
    onHangarRetry: widget.hangar == null ? null : _read,
  );
}

class ToolsCardData extends StatelessWidget {
  const ToolsCardData({
    super.key,
    required this.id,
    required this.records,
    this.hangar,
    this.cache,
    this.hangarLoading = false,
    this.hangarFailed = false,
    this.onHangarRetry,
  });
  final String id;
  final MissionRecordsController records;
  final CachedExecHangar? hangar;
  final ToolsSnapshotCache? cache;
  final bool hangarLoading, hangarFailed;
  final VoidCallback? onHangarRetry;

  /// One live value per tool (user 11-11: a tile is its name and one figure).
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context), p = context.tokens;
    String t(String key) => strings.text('terminal.$key');
    final words = TextStyle(color: p.colors.textSecondary, fontSize: 13);
    Widget note(String text) => Text(text, style: words);
    // The words sit on the figure's baseline; a Wrap lets a wide figure take
    // its own line on a narrow tile or at a large text size.
    Widget value(List<Widget> children) => Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: children,
    );
    Widget beside(Widget child) =>
        Padding(padding: const EdgeInsets.only(bottom: 3), child: child);
    Widget figure(String text) =>
        Text(text, style: toolNumber(context, size: 22));
    Widget count(String key, int number) {
      final parts = t(key).split('{count}');
      return value([
        if (parts.first.trim().isNotEmpty) beside(note(parts.first.trim())),
        figure('$number'),
        if (parts.last.trim().isNotEmpty) beside(note(parts.last.trim())),
      ]);
    }

    if (id == 'exec-hangar') {
      final snapshot = hangar?.snapshot;
      final now = snapshot?.now.add(hangar!.age);
      final phase = snapshot?.phases
          .where((v) => !now!.isBefore(v.start) && now.isBefore(v.end))
          .firstOrNull;
      if (hangarLoading) return note(t('hangarLoading'));
      if (hangarFailed ||
          snapshot == null ||
          !snapshot.reliable ||
          snapshot.refreshFailed ||
          phase == null) {
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            note(t('hangarUnavailable')),
            ToolsAction(
              key: const Key('tools-hangar-retry'),
              label: t('retry'),
              onPressed: onHangarRetry,
            ),
          ],
        );
      }
      final next = phase.open
          ? snapshot.windows
                .where((w) => !now!.isBefore(w.open) && now.isBefore(w.close))
                .firstOrNull
                ?.close
          : snapshot.windows
                .where((w) => w.open.isAfter(now!))
                .firstOrNull
                ?.open;
      return value([
        beside(
          Text(
            // Same wording as the 行政机库 page itself.
            strings.text('execHangar.${phase.open ? 'open' : 'closed'}'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: phase.open ? p.colors.success : p.colors.textSecondary,
            ),
          ),
        ),
        figure(execHangarCountdown(next ?? phase.end, now!)),
      ]);
    }
    if (id == 'missions') {
      if (!records.loaded || !records.visible) {
        return note(t('recordsUnavailable'));
      }
      if (records.groups.isEmpty) return note(t('noRecords'));
      return count(
        'completedCount',
        records.groups.fold<int>(0, (n, g) => n + g.count),
      );
    }
    if (id == 'blueprints') {
      final total = cache?.blueprintTotal;
      return total == null
          ? note(t('openBlueprints'))
          : count('blueprintCount', total);
    }
    if (id == 'key-bindings') {
      final snapshot = cache?.keys;
      if (snapshot == null || snapshot.maps.isEmpty) return note(t('noKeys'));
      var bindings = 0;
      for (final map in snapshot.maps) {
        for (final action in map.actions) {
          bindings += action.bindings
              .where(
                (b) =>
                    !b.cleared &&
                    const {
                      'gamepad',
                      'joystick',
                      'keyboardMouse',
                    }.contains(b.device),
              )
              .length;
        }
      }
      return count('bindingCount', bindings);
    }
    return const SizedBox.shrink();
  }
}
