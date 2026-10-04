import '../common/user_avatar_menu.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'party_rooms_module.dart';
import 'room_tag_catalog.dart';
import 'room_tag_colors.dart';
import '../common/runtime_name_labels.dart';

String roomText(BuildContext context, String key) =>
    AppStrings.of(context).text('rooms.$key');
String roomChoice(BuildContext context, String group, String value) {
  final key = 'rooms.$group.$value';
  final result = AppStrings.of(context).text(key);
  return result == key ? roomText(context, 'unknown') : result;
}

String roomRegion(BuildContext context, PartyRoom room) =>
    roomServerRegion(context, room.leaderServerRegion);
String roomServerRegion(BuildContext context, String code) => roomText(
  context,
  'region.${const {'US', 'EU', 'AU', 'ASIA'}.contains(code) ? code : 'unknown'}',
);
String roomLocation(BuildContext context, RoomMember member) {
  if (member.location.trim().isNotEmpty &&
      member.presenceKey == 'presence.inGame' &&
      member.arrivalPendingConfirmation) {
    final locale = AppStrings.of(context).locale;
    final pending = roomText(context, 'locationPending');
    final target = member.arrivalTargetCode?.trim() ?? '';
    return target.isNotEmpty && target.toLowerCase() != 'unknown'
        ? '${runtimeNameLabel(target, member.arrivalTargetLabels, locale)} · $pending'
        : pending;
  }
  final original = member.location;
  if (member.locationHiddenReason == 'lowConfidence' &&
      member.presenceKey == 'presence.inGame' &&
      original.trim().toLowerCase() == 'unknown') {
    return roomText(context, 'lowConfidenceLocation');
  }
  if (original.isEmpty) return roomText(context, 'notShared');
  if (original.trim().toLowerCase() == 'unknown') {
    return roomText(context, 'factUnknown');
  }
  final locale = AppStrings.of(context).locale;
  final names = member.locationLabels;
  if (locale.languageCode == 'zh') {
    final traditional =
        locale.countryCode == 'TW' ||
        locale.countryCode == 'HK' ||
        locale.scriptCode == 'Hant';
    return names[traditional ? 'zhHant' : 'zhHans'] ??
        names['zhHans'] ??
        names['en'] ??
        original;
  }
  return names['en'] ?? original;
}

String roomShip(BuildContext context, RoomMember member) {
  final ship = member.ship.trim();
  if (ship.isEmpty) return roomText(context, 'notShared');
  if (ship.toLowerCase() == 'unknown') {
    return roomText(context, 'factUnknown');
  }
  return runtimeNameLabel(
    member.ship,
    member.shipLabels,
    AppStrings.of(context).locale,
  );
}

String roomDate(BuildContext context, DateTime value) {
  final local = value.toLocal(), locale = MaterialLocalizations.of(context);
  return '${locale.formatCompactDate(local)} ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
}

class RoomAvatar extends StatelessWidget {
  const RoomAvatar({super.key, required this.member, this.size = 44});
  final RoomMember member;
  final double size;
  @override
  Widget build(BuildContext context) => RoomIdentityAvatar(
    name: member.displayName,
    gameId: member.gameId,
    avatarData: member.avatarData,
    userRef: member.userRef,
    isSelf: member.isSelf,
    size: size,
  );
}

class RoomIdentityAvatar extends StatelessWidget {
  const RoomIdentityAvatar({
    super.key,
    required this.name,
    this.gameId = '',
    this.avatarData,
    this.userRef,
    this.isSelf = false,
    this.size = 44,
    this.includeSocialActions = true,
  });
  final String name, gameId;
  final String? avatarData, userRef;
  final bool isSelf, includeSocialActions;
  final double size;
  Uint8List? _bytes() {
    final data = avatarData;
    if (data == null ||
        data.length > ((512 * 1024 + 2) ~/ 3 * 4) + 24 ||
        !(data.startsWith('data:image/png;base64,') ||
            data.startsWith('data:image/jpeg;base64,'))) {
      return null;
    }
    try {
      return base64Decode(data.substring(data.indexOf(',') + 1));
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes();
    final fallback = Center(
      child: StarBridgeIcon(
        StarBridgeIconSemantic.account,
        size: size * .48,
        color: context.tokens.colors.textSecondary,
      ),
    );
    return UserAvatarMenu(
      name: name,
      avatarImageData: avatarData,
      isSelf: isSelf,
      includeSocialActions: includeSocialActions,
      target: userRef == null
          ? null
          : UserTarget('room', userRef!, query: gameId),
      child: Semantics(
        label: name,
        image: true,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: context.tokens.colors.accentSoft,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: context.tokens.colors.textSecondary.withValues(alpha: .25),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: bytes == null
              ? fallback
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: 128,
                  cacheHeight: 128,
                  gaplessPlayback: false,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class RoomFact extends StatelessWidget {
  const RoomFact(this.label, this.value, {super.key, this.emphasis = false});
  final String label, value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 300),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.tokens.colors.textSecondary),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          softWrap: true,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
            color: emphasis ? context.tokens.colors.accent : null,
          ),
        ),
      ],
    ),
  );
}

class RoomTags extends StatelessWidget {
  const RoomTags({super.key, required this.room});
  final PartyRoom room;
  @override
  Widget build(BuildContext context) => Wrap(
    key: const Key('room-tags'),
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final tag in RoomTagCatalog.ordered(room.tags))
        Tooltip(
          message: RoomTagCatalog.fullText(tag),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: roomTagColors(context, tag.id).soft,
              border: Border.all(
                color: roomTagColors(
                  context,
                  tag.id,
                ).foreground.withValues(alpha: .45),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              RoomTagCatalog.compactText(tag),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: roomTagColors(context, tag.id).foreground),
            ),
          ),
        ),
    ],
  );
}
