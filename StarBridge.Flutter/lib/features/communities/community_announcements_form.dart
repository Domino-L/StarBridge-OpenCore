import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_announcements_copy.dart';

/// Shared presentation only. Controllers retain drafts and every write owner.
class CommunityAnnouncementsForm extends StatelessWidget {
  const CommunityAnnouncementsForm({
    required this.title,
    required this.content,
    required this.creating,
    required this.saving,
    required this.confirming,
    required this.stale,
    required this.canSave,
    required this.onChanged,
    required this.onSave,
    required this.onDiscard,
    super.key,
  });
  final TextEditingController title, content;
  final bool creating, saving, confirming, stale, canSave;
  final VoidCallback onChanged;
  final Future<void> Function() onSave;
  final Future<bool> Function() onDiscard;
  @override
  Widget build(BuildContext context) {
    String t(String key) => communityAnnouncementText(context, key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(creating ? 'create' : 'edit'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (creating)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(t('publishBody')),
          ),
        const SizedBox(height: 12),
        StarBridgeFieldFrame(
          builder: (_, focus) => TextField(
            key: const ValueKey('announcement-title'),
            focusNode: focus,
            controller: title,
            style: Theme.of(context).textTheme.bodyMedium,
            enabled: !saving && !confirming,
            maxLength: 48,
            decoration: InputDecoration(labelText: t('title')),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(height: 12),
        StarBridgeFieldFrame(
          builder: (_, focus) => TextField(
            key: const ValueKey('announcement-content'),
            focusNode: focus,
            controller: content,
            style: Theme.of(context).textTheme.bodyMedium,
            enabled: !saving && !confirming,
            minLines: 7,
            maxLines: 14,
            maxLength: 1200,
            decoration: InputDecoration(labelText: t('content')),
            onChanged: (_) => onChanged(),
          ),
        ),
        if (stale)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              t('announcementsChanged'),
              style: TextStyle(color: context.tokens.colors.warning),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StarBridgeActionButton(
              controlKey: const Key('announcement-save'),
              kind: StarBridgeActionKind.primary,
              onActivate: canSave && !stale && !confirming
                  ? (_) => onSave()
                  : null,
              child: Text(
                t(
                  saving
                      ? 'saving'
                      : creating
                      ? 'publish'
                      : 'save',
                ),
              ),
            ),
            StarBridgeActionButton(
              controlKey: const Key('announcement-discard'),
              onActivate: !saving && !confirming ? (_) => onDiscard() : null,
              child: Text(t('discard')),
            ),
          ],
        ),
      ],
    );
  }
}
