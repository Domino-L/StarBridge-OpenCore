import '../../design_system/icons/standard_icon.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_invitation_attachment.dart';

class CommunityInvitationCard extends StatelessWidget {
  const CommunityInvitationCard({
    required this.value,
    this.onOpen,
    this.busy = false,
    super.key,
  });
  final CommunityInvitationAttachment value;
  final VoidCallback? onOpen;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.of(context).text('direct.$key');
    final expired =
        value.expiresAt != null && !value.expiresAt!.isAfter(DateTime.now());
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.tokens.surfaces.panel.fill,
        border: Border.all(color: context.tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StandardIcon(StandardIconSemantic.groups, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('attachment.fleet_invitation'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value.title,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(value.summary, style: Theme.of(context).textTheme.bodyMedium),
          if (expired)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t('inviteExpired'),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : onOpen,
            child: Text(t('viewInvite')),
          ),
          if (onOpen == null)
            Text(
              t('attachmentReadOnly'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
