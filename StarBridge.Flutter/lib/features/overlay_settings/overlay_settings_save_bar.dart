import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Shared save affordance for the information and menu settings workspaces.
class OverlaySettingsSaveBar extends StatefulWidget {
  const OverlaySettingsSaveBar({
    required this.busy,
    required this.onUndo,
    required this.onRedo,
    required this.onDiscard,
    required this.onSave,
    this.dirty = true,
    this.saveKey,
    this.discardKey,
    super.key,
  });
  final bool busy, dirty;
  final VoidCallback? onUndo, onRedo, onDiscard;
  final FutureOr<void> Function()? onSave;
  final Key? saveKey, discardKey;

  @override
  State<OverlaySettingsSaveBar> createState() => _SaveBarState();
}

class _SaveBarState extends State<OverlaySettingsSaveBar> {
  bool _saving = false;
  InteractionSource Function() _commandSource = () =>
      InteractionSource.programmatic;

  Future<void> _save(InteractionSource source) async {
    if (widget.busy || _saving || widget.onSave == null) return;
    setState(() => _saving = true);
    try {
      await runStarBridgeActivation(source, () {
        _commandSource = captureStarBridgeActivationSource();
        return widget.onSave!();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String text(String key) =>
        AppStrings.of(context).text('overlay.workspace.$key');
    return Material(
      elevation: 12,
      color: tokens.surfaces.floating.fill,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.xl,
            vertical: tokens.space.sm,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: tokens.space.xs,
              runSpacing: tokens.space.xs,
              children: [
                if (widget.busy)
                  StarBridgeInteractionRegion(
                    child: Builder(
                      builder: (context) {
                        final data = InteractionScope.of(context);
                        final source = _saving
                            ? _commandSource()
                            : resolveStarBridgeInitialReadSource(
                                context,
                                InteractionSource.programmatic,
                              );
                        return InteractionScope(
                          data: data.copyWith(
                            reduceMotion:
                                data.reduceMotion ||
                                source == InteractionSource.keyboard,
                          ),
                          child: Semantics(
                            liveRegion: true,
                            child: SuiteBusyFrame(
                              busy: true,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: SuiteBusyLabel(
                                  text(_saving ? 'saving' : 'working'),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: EdgeInsetsDirectional.only(end: tokens.space.md),
                  child: Text(text(widget.dirty ? 'dirty' : 'saved')),
                ),
                StarBridgeIconAction(
                  controlKey: const Key('overlay-save-bar-undo'),
                  label: text('undo'),
                  onActivate: widget.busy || widget.onUndo == null
                      ? null
                      : (_) => widget.onUndo!(),
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.undo),
                ),
                StarBridgeIconAction(
                  controlKey: const Key('overlay-save-bar-redo'),
                  label: text('redo'),
                  onActivate: widget.busy || widget.onRedo == null
                      ? null
                      : (_) => widget.onRedo!(),
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.redo),
                ),
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: widget.discardKey,
                  onActivate: widget.busy || widget.onDiscard == null
                      ? null
                      : (_) => widget.onDiscard!(),
                  child: Text(text('discard')),
                ),
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.primary,
                  controlKey: widget.saveKey,
                  onActivate: widget.busy || _saving || widget.onSave == null
                      ? null
                      : (source) => unawaited(_save(source)),
                  child: Text(text('save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
