import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../platform/window/menu_exec_hangar_game_overlay.dart';
import '../../design_system/icons/image_tool_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../localization/app_strings.dart';

/// Display placement only. Monitoring and reminder preferences stay in the tool.
class MenuExecHangarGamePin extends StatefulWidget {
  const MenuExecHangarGamePin({
    super.key,
    required this.port,
    required this.active,
  });
  final MenuExecHangarGameOverlayPort port;
  final bool active;
  @override
  State<MenuExecHangarGamePin> createState() => _PinState();
}

class _PinState extends State<MenuExecHangarGamePin> {
  MenuExecHangarGameState? _state;
  var _selected = MenuExecHangarGamePosition.topLeft;
  bool _busy = false, _failed = false, _choosing = false;
  InteractionSource _source = InteractionSource.programmatic;
  String? _pending;
  int _request = 0;
  String t(String key) => AppStrings.of(context).text('execHangar.$key');
  @override
  void initState() {
    super.initState();
    if (widget.active) _run(widget.port.readGameOverlay);
  }

  @override
  void didUpdateWidget(MenuExecHangarGamePin old) {
    super.didUpdateWidget(old);
    if (!widget.active && old.active || old.port != widget.port) {
      ++_request;
      _busy = false;
      _source = InteractionSource.programmatic;
      _pending = null;
    }
    if (widget.active && (!old.active || old.port != widget.port)) {
      _run(widget.port.readGameOverlay);
    }
  }

  Future<void> _run(
    Future<MenuExecHangarGameState> Function() action, {
    InteractionSource source = InteractionSource.programmatic,
    String pending = 'gameReadPending',
  }) async {
    if (_busy || !widget.active) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _failed = false;
      _source = source;
      _pending = pending;
    });
    try {
      final state = await action();
      if (!mounted || !widget.active || request != _request) return;
      setState(() {
        _state = state;
        _selected = state.position;
        _choosing = false;
      });
    } on Object {
      if (mounted && widget.active && request == _request) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _busy = false;
          _source = InteractionSource.programmatic;
          _pending = null;
        });
      }
    }
  }

  @override
  void dispose() {
    ++_request;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          StarBridgeActionButton(
            controlKey: const Key('menu-hangar-game-pin'),
            onActivate: _busy || _state == null
                ? null
                : _state!.pinned
                ? (source) => _run(
                    widget.port.unpinFromGame,
                    source: source,
                    pending: 'gameUnpinPending',
                  )
                : (_) => setState(() => _choosing = !_choosing),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: FittedBox(child: ImageToolIcon(ImageToolGlyph.pin)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    t(_state?.pinned == true ? 'gameUnpin' : 'gamePin'),
                  ),
                ),
              ],
            ),
          ),
          if (_state?.pinned == true)
            StarBridgeActionButton(
              controlKey: const Key('menu-hangar-game-position'),
              kind: StarBridgeActionKind.quiet,
              onActivate: _busy
                  ? null
                  : (_) => setState(() => _choosing = !_choosing),
              child: Text(t('gameChangePosition')),
            ),
          if (_failed)
            StarBridgeActionButton(
              controlKey: const Key('menu-hangar-game-retry'),
              kind: StarBridgeActionKind.quiet,
              onActivate: _busy
                  ? null
                  : (source) =>
                        _run(widget.port.readGameOverlay, source: source),
              child: Text(t('gameRetry')),
            ),
        ],
      ),
      if (_busy && _pending != null)
        StarBridgeInteractionRegion(
          child: Builder(
            builder: (context) {
              final data = InteractionScope.of(context);
              return InteractionScope(
                data: data.copyWith(
                  reduceMotion:
                      data.reduceMotion || _source != InteractionSource.pointer,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: RepaintBoundary(
                    key: const Key('menu-hangar-game-paint'),
                    child: SuiteBusyFrame(
                      key: const Key('menu-hangar-game-pending'),
                      busy: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 10,
                        ),
                        child: SuiteBusyLabel(t(_pending!)),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      if (_state?.pinned == true && !_choosing)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${t('gamePinned')} · ${t('gamePosition.${_state!.position.name}')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (_failed)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(t('gamePinFailed')),
        ),
      if (_choosing) ...[
        const SizedBox(height: 12),
        Text(t('gameChoosePosition')),
        const SizedBox(height: 8),
        for (final row in const [
          [
            MenuExecHangarGamePosition.topLeft,
            MenuExecHangarGamePosition.topCenter,
            MenuExecHangarGamePosition.topRight,
          ],
          [
            MenuExecHangarGamePosition.bottomLeft,
            MenuExecHangarGamePosition.bottomCenter,
            MenuExecHangarGamePosition.bottomRight,
          ],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final position in row)
                  StarBridgeChoiceChip(
                    controlKey: ValueKey('menu-hangar-game-${position.name}'),
                    label: t('gamePosition.${position.name}'),
                    selected: position == _selected,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _selected = position),
                  ),
              ],
            ),
          ),
        Text(t('gamePinHint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: [
            StarBridgeActionButton(
              controlKey: const Key('menu-hangar-game-confirm'),
              kind: StarBridgeActionKind.primary,
              onActivate: _busy
                  ? null
                  : (source) => _run(
                      () => widget.port.pinToGame(_selected),
                      source: source,
                      pending: 'gamePinPending',
                    ),
              child: Text(t('gameShow')),
            ),
            StarBridgeActionButton(
              controlKey: const Key('menu-hangar-game-cancel'),
              kind: StarBridgeActionKind.quiet,
              onActivate: _busy
                  ? null
                  : (_) => setState(() => _choosing = false),
              child: Text(t('gameCancel')),
            ),
          ],
        ),
      ],
    ],
  );
}
