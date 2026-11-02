import '../../features/communities/community_member_runtime.dart';

import 'dart:ui' show Locale;

import '../../app/localization/app_strings.dart';
import '../../features/common/organization_member_copy.dart';
import '../../features/common/organization_member_runtime_cells.dart';
import '../../features/communities/community_workspace_port.dart';
import 'menu_organization_view.dart';
import 'menu_member_field_keys.dart';
import 'menu_overlay_text.dart';

({Map<String, Object?> row, Map<String, Object?> presentation})
organizationMemberPresentation(
  CommunityWorkspaceMember member,
  String? avatar,
  String profileKey,
) {
  const locale = Locale('zh', 'CN');
  final runtime = communityMemberRuntimeCells(
    member,
    text: (key) => memberBoardTextForLocale(locale, key),
    regionText: (value) =>
        AppStrings.resolve(locale).text('rooms.region.$value'),
    locale: locale,
  );
  final semantic = communityMemberRuntimeCells(
    member,
    text: (key) => key,
    regionText: (value) => value,
    locale: locale,
  );
  String fieldKey(String value) =>
      menuMemberFieldKeys.contains(value) ? value : '';
  final presence = organizationPresence(member.online, member.liveStatus);
  MemberRuntimeCells localizedRuntime(AppStrings strings) =>
      communityMemberRuntimeCells(
        member,
        text: (key) => memberBoardTextForLocale(strings.locale, key),
        regionText: (value) => strings.text('rooms.region.$value'),
        locale: strings.locale,
      );
  return (
    row: {
      'title': member.displayName,
      'detail': MenuOverlayComputed((strings) {
        final cells = localizedRuntime(strings);
        final details = [
          cells.server.text,
          cells.ship.text,
          cells.location.text,
        ].where((text) => text.isNotEmpty).join(' · ');
        final status = strings.text(
          const {'online', 'inGame', 'away', 'offline'}.contains(presence)
              ? 'presence.$presence'
              : 'menu.overlay.organizations.presencePrivate',
        );
        return '${member.roleTitle} · $status${details.isEmpty ? '' : '\n$details'}';
      }),
    },
    presentation: {
      'handle': member.gameName,
      'role': member.roleTitle,
      'roleColor': member.roleColor.toUpperCase() == '#9DAAB3'
          ? ''
          : member.roleColor,
      'presence': presence,
      'isSelf': member.isSelf,
      'avatar': avatar,
      'profileKey': profileKey,
      'ship': MenuOverlayComputed(
        (strings) => localizedRuntime(strings).ship.text,
      ),
      'location': MenuOverlayComputed(
        (strings) => localizedRuntime(strings).location.text,
      ),
      'server': MenuOverlayComputed(
        (strings) => localizedRuntime(strings).server.text,
      ),
      'serverTextKey': semantic.server.isPlaceholder ? fieldKey(semantic.server.text) : '',
      'shipTextKey': semantic.ship.isPlaceholder ? fieldKey(semantic.ship.text) : '',
      'locationTextKey': semantic.location.isPlaceholder ? fieldKey(semantic.location.text) : '',
      'shipKind': runtime.ship.isPlaceholder ? 'placeholder' : 'value',
      'locationKind': runtime.location.isPlaceholder ? 'placeholder' : 'value',
      'serverKind': runtime.server.isPlaceholder ? 'placeholder' : 'value',
    },
  );
}
