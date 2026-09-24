import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'party_rooms_module.dart';
import '../../app/localization/app_strings.dart';

ActionTone roomLeaveTone(PartyRoom? room) =>
    room?.members.length == 1 ? ActionTone.danger : ActionTone.warning;

ActionTone roomFeedbackTone(String code) => switch (code) {
  'joined' ||
  'left' ||
  'closed' ||
  'updated' ||
  'approved' ||
  'declined' ||
  'invited' ||
  'revoked' ||
  'invitationDeclined' => ActionTone.success,
  'pending' => ActionTone.info,
  'outcomeUnknown' ||
  'refreshRequired' ||
  'contextChanged' ||
  'presetChanged' ||
  'presetImportUnknown' => ActionTone.warning,
  _ => ActionTone.danger,
};

class RoomFeedback extends StatelessWidget {
  const RoomFeedback(this.code, {super.key});
  final String code;
  @override
  Widget build(BuildContext context) {
    final tone = roomFeedbackTone(code), colors = context.tokens.colors;
    final (foreground, background, icon) = switch (tone) {
      ActionTone.info => (
        colors.info,
        colors.infoSoft,
        StarBridgeIconSemantic.pending,
      ),
      ActionTone.success => (
        colors.success,
        colors.successSoft,
        StarBridgeIconSemantic.connected,
      ),
      ActionTone.warning => (
        colors.warning,
        colors.warningSoft,
        StarBridgeIconSemantic.pending,
      ),
      ActionTone.danger => (
        colors.danger,
        colors.dangerSoft,
        StarBridgeIconSemantic.warning,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          border: Border(left: BorderSide(color: foreground, width: 2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StarBridgeIcon(icon, size: 16, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppStrings.of(context).text('rooms.action.$code'),
                style: TextStyle(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
