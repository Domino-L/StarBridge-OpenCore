import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Shared save affordance for the information and menu settings workspaces.
class OverlaySettingsSaveBar extends StatelessWidget {
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
  final VoidCallback? onUndo, onRedo, onDiscard, onSave;
  final Key? saveKey, discardKey;

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
                if (busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                Padding(
                  padding: EdgeInsetsDirectional.only(end: tokens.space.md),
                  child: Text(text(dirty ? 'dirty' : 'saved')),
                ),
                IconButton(
                  tooltip: text('undo'),
                  onPressed: busy ? null : onUndo,
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.undo),
                ),
                IconButton(
                  tooltip: text('redo'),
                  onPressed: busy ? null : onRedo,
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.redo),
                ),
                TextButton(
                  key: discardKey,
                  onPressed: busy ? null : onDiscard,
                  child: Text(text('discard')),
                ),
                FilledButton(
                  key: saveKey,
                  onPressed: busy ? null : onSave,
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
