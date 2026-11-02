import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_select_field.dart';
import 'overlay_workspace_models.dart';
import 'overlay_appearance_preview_copy.dart';

/// Trial selection is not application, saving, or entitlement authorization.
class OverlayAppearanceTryOnSelector extends StatelessWidget {
  const OverlayAppearanceTryOnSelector({
    required this.appearances,
    required this.skin,
    this.onSelected,
    super.key,
  });
  final List<OverlayWorkspaceAppearance> appearances;
  final String skin;
  final ValueChanged<String>? onSelected;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StarBridgeSelectField<String>(
        key: const Key('appearance-preview-skin'),
        identity: 'appearance-preview-skin',
        value: appearances.any((a) => a.id == skin) ? skin : null,
        decoration: InputDecoration(
          labelText: overlayAppearancePreviewText(
            context,
            '试装外观',
            '試裝外觀',
            'Preview appearance',
          ),
        ),
        options: [
          for (final a in appearances)
            StarBridgeSelectOption(
              value: a.id,
              label: Localizations.localeOf(context).languageCode == 'zh'
                  ? a.displayNameZh
                  : a.displayNameEn,
            ),
        ],
        onSelected: onSelected == null
            ? null
            : (value, _) => onSelected!(value),
      ),
      const SizedBox(height: 12),
      Text(
        overlayAppearancePreviewText(
          context,
          '只试装，不切换已应用的外观；修改保留为草稿。',
          '僅試裝，不切換已套用的外觀；修改保留為草稿。',
          'Preview only. Your applied appearance stays unchanged; edits remain a draft.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
    ],
  );
}
