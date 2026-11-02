import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_activation_origin.dart';
import 'starbridge_interaction_theme.dart';

/// Delete-only chips. Selection/order/limits stay with the caller. Reuses the
/// package's identity-safe exit and focus repair, never adds a body toggle.
class StarBridgeRemovableChipGroup extends StatefulWidget {
  const StarBridgeRemovableChipGroup({
    required this.chips,
    required this.onRemove,
    this.fallbackFocus,
    this.changeSource,
    super.key,
  });
  final List<SuiteChipData> chips;
  final void Function(String, InteractionSource) onRemove;
  final FocusNode? fallbackFocus;
  final InteractionSource? changeSource;
  @override
  State<StarBridgeRemovableChipGroup> createState() => _GroupState();
}

class _GroupState extends State<StarBridgeRemovableChipGroup> {
  final _focus = <String, FocusNode>{};
  InteractionSource _nativeSource = InteractionSource.keyboard;
  FocusNode node(String id) => _focus.putIfAbsent(id, () {
    final focus = FocusNode(debugLabel: 'remove-$id');
    focus.addListener(() {
      if (mounted) setState(() {});
    });
    return focus;
  });
  void remove(String id, InteractionSource source) {
    _nativeSource = InteractionSource.keyboard;
    unawaited(
      runStarBridgeActivation<void>(source, () => widget.onRemove(id, source)),
    );
  }

  @override
  void didUpdateWidget(StarBridgeRemovableChipGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final remaining = widget.chips.map((c) => c.id).toSet();
    for (var i = 0; i < oldWidget.chips.length; i++) {
      final id = oldWidget.chips[i].id;
      if (remaining.contains(id) || _focus[id]?.hasFocus != true) continue;
      final neighbours = [
        ...oldWidget.chips.skip(i + 1),
        ...oldWidget.chips.take(i).toList().reversed,
      ];
      final next = neighbours
          .where((c) => remaining.contains(c.id))
          .firstOrNull;
      final target = next == null ? widget.fallbackFocus : node(next.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) target?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        if (data.suite != InteractionSuite.standard) {
          return SuiteChipGroup(
            chips: widget.chips,
            onToggle: null,
            onRemoveWithSource: remove,
            changeSource: widget.changeSource,
            focusNodeForId: node,
            fallbackFocus: widget.fallbackFocus,
          );
        }
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in widget.chips)
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.delete): () =>
                      remove(c.id, InteractionSource.keyboard),
                  const SingleActivator(LogicalKeyboardKey.backspace): () =>
                      remove(c.id, InteractionSource.keyboard),
                  const SingleActivator(LogicalKeyboardKey.enter): () =>
                      remove(c.id, InteractionSource.keyboard),
                  const SingleActivator(LogicalKeyboardKey.space): () =>
                      remove(c.id, InteractionSource.keyboard),
                },
                child: Listener(
                  onPointerDown: (_) {
                    _nativeSource = InteractionSource.pointer;
                    node(c.id).requestFocus();
                  },
                  onPointerCancel: (_) =>
                      _nativeSource = InteractionSource.keyboard,
                  onPointerUp: (_) => scheduleMicrotask(() {
                    if (mounted) _nativeSource = InteractionSource.keyboard;
                  }),
                  child: Focus(
                    focusNode: node(c.id),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: node(c.id).hasFocus
                            ? Border.all(
                                color: data.palette.focusRing,
                                width: 2,
                              )
                            : null,
                      ),
                      child: ExcludeFocus(
                        child: InputChip(
                          key: ValueKey(c.id),
                          label: suiteChipLabel(c, Text(c.label)),
                          side: c.side,
                          backgroundColor: c.backgroundColor,
                          labelStyle: c.foregroundColor == null
                              ? null
                              : TextStyle(color: c.foregroundColor),
                          deleteButtonTooltipMessage:
                              c.removeLabel ??
                              '${MaterialLocalizations.of(context).deleteButtonTooltip} ${c.label}',
                          onDeleted: () => remove(c.id, _nativeSource),
                          chipAnimationStyle: data.reduceMotion
                              ? ChipAnimationStyle(
                                  enableAnimation: AnimationStyle.noAnimation,
                                  selectAnimation: AnimationStyle.noAnimation,
                                  avatarDrawerAnimation:
                                      AnimationStyle.noAnimation,
                                  deleteDrawerAnimation:
                                      AnimationStyle.noAnimation,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
