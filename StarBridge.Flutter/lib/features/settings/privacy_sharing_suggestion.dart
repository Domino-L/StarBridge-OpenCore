import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'help_support_action.dart';

Future<bool> confirmPrivacySharingSuggestion(
  BuildContext context,
  List<String> items,
) async {
  final strings = AppStrings.of(context);
  String t(String key) => strings.text('settings.privacy.suggestion.$key');
  return await showStarBridgeDialog<bool>(
        context,
        builder: (context) => AlertDialog(
          key: const Key('privacy-sharing-suggestion-dialog'),
          scrollable: true,
          title: Text(t('confirmTitle')),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('confirmList')),
              for (final item in items)
                Padding(
                  padding: EdgeInsets.only(top: context.tokens.space.xs),
                  child: Text(item),
                ),
            ],
          ),
          actions: [
            HelpSupportAction(
              controlKey: const Key('privacy-sharing-suggestion-cancel'),
              onActivate: (source) =>
                  dismissStarBridgeDialog<bool>(context, source: source),
              child: Text(t('cancel')),
            ),
            HelpSupportAction(
              controlKey: const Key('privacy-sharing-suggestion-confirm'),
              kind: StarBridgeActionKind.primary,
              onActivate: (source) => dismissStarBridgeDialog<bool>(
                context,
                source: source,
                result: true,
              ),
              child: Text(t('confirm')),
            ),
          ],
        ),
      ) ??
      false;
}

typedef PrivacySuggestionVisibilityChanged = void Function(
  Object suggestion,
  bool visible,
);

class PrivacySharingSuggestion extends StatefulWidget {
  const PrivacySharingSuggestion({
    required this.adoptKey,
    required this.onAdopt,
    this.onVisibilityChanged,
    super.key,
  });

  final Key adoptKey;
  final VoidCallback? onAdopt;
  final PrivacySuggestionVisibilityChanged? onVisibilityChanged;

  @override
  State<PrivacySharingSuggestion> createState() =>
      _PrivacySharingSuggestionState();
}

class _PrivacySharingSuggestionState extends State<PrivacySharingSuggestion> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisibilityChanged?.call(this, true);
    });
  }

  @override
  void dispose() {
    final onVisibilityChanged = widget.onVisibilityChanged;
    if (onVisibilityChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onVisibilityChanged(this, false);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final onAdopt = widget.onAdopt;
    return Wrap(
      spacing: context.tokens.space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(strings.text('settings.privacy.suggestion.unsaved')),
        HelpSupportAction(
          controlKey: widget.adoptKey,
          onActivate: onAdopt == null ? null : (_) => onAdopt(),
          child: Text(strings.text('settings.privacy.suggestion.adopt')),
        ),
      ],
    );
  }
}
