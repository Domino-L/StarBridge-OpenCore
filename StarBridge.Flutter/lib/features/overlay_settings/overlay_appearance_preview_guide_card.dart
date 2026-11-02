import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

class OverlayAppearancePreviewGuideCard extends StatelessWidget {
  const OverlayAppearancePreviewGuideCard({required this.onDismiss, super.key});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    String copy(String cn, String tw, String en) {
      final locale = Localizations.localeOf(context);
      return locale.languageCode != 'zh'
          ? en
          : locale.scriptCode == 'Hant' || locale.countryCode == 'TW'
          ? tw
          : cn;
    }

    return Material(
      key: const Key('appearance-preview-guide'),
      color: context.tokens.surfaces.floating.fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.primary),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                copy('这里可以调整外观', '這裡可以調整外觀', 'Make the appearance your own'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              copy(
                '下方工具栏可以给设置面板换边、收起设置、保存更改或退出预览。',
                '下方工具列可以替設定面板換邊、收起設定、儲存變更或退出預覽。',
                'Use the toolbar below to move or hide settings, save changes, or exit preview.',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const StandardIcon(
                  StandardIconSemantic.arrowDownward,
                  size: 18,
                ),
                StarBridgeActionButton(
                  key: const Key('appearance-preview-guide-dismiss'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (_) => onDismiss(),
                  child: Text(copy('跳过', '略過', 'Skip')),
                ),
                StarBridgeActionButton(
                  key: const Key('appearance-preview-guide-confirm'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (_) => onDismiss(),
                  child: Text(copy('知道了', '知道了', 'Got it')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
