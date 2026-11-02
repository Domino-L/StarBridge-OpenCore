import 'guide_scope.dart';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'guide_copy.dart';

/// Guided empty state: what appears here and how to make it appear.
/// Buttons belong to the page and only open or refresh things.
/// Local mode only: an online-only page says why it is empty and links to
/// Account and recognition, where switching still asks for confirmation.
Widget? guideOnlineRequired(BuildContext context, String feature) {
  final hub = GuideScope.maybeOf(context);
  if (hub == null || !hub.localMode.value) return null;
  return GuideEmptyState(
    'online',
    feature: feature,
    onPrimary: () => hub.navigate('/settings/account'),
  );
}

class GuideEmptyState extends StatelessWidget {
  /// Pages swap their plain empty text for this only under a [GuideScope],
  /// i.e. in the product shell; isolated page tests keep their own copy.
  static bool active(BuildContext context) =>
      GuideScope.maybeOf(context) != null;

  const GuideEmptyState(
    this.id, {
    this.onPrimary,
    this.onSecondary,
    this.feature,
    this.primaryAnchor,
    super.key,
  });

  final String id;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;

  /// Replaces `{feature}` (local-mode "needs an online account" state).
  final String? feature;

  /// Wraps the primary button, e.g. a [GuideAnchor] that starts a tour.
  final Widget Function(Widget button)? primaryAnchor;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = GuideCopy.of(context);
    final text = Theme.of(context).textTheme;
    String? word(String part) =>
        copy.maybe('empty.$id.$part')?.replaceAll('{feature}', feature ?? '');
    final primary = word('primary');
    final secondary = word('secondary');
    final note = word('note');
    Widget primaryButton = StarBridgeActionButton(
      controlKey: Key('guide-empty-$id-primary'),
      kind: StarBridgeActionKind.primary,
      onActivate: (_) => onPrimary?.call(),
      child: Text(primary ?? ''),
    );
    if (primaryAnchor != null) primaryButton = primaryAnchor!(primaryButton);
    return Center(
      key: Key('guide-empty-$id'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: EdgeInsets.all(t.space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word('title')!,
                style: text.titleLarge,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: t.space.xs),
              Text(
                word('body')!,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: t.colors.textSecondary),
              ),
              if ((primary != null && onPrimary != null) ||
                  (secondary != null && onSecondary != null)) ...[
                SizedBox(height: t.space.lg),
                Wrap(
                  spacing: t.space.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    if (primary != null && onPrimary != null) primaryButton,
                    if (secondary != null && onSecondary != null)
                      StarBridgeActionButton(
                        controlKey: Key('guide-empty-$id-secondary'),
                        onActivate: (_) => onSecondary!(),
                        child: Text(secondary),
                      ),
                  ],
                ),
              ],
              if (note != null) ...[
                SizedBox(height: t.space.md),
                Text(
                  note,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: t.colors.textDisabled),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
