import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_collaboration.dart';
import 'personal_profile_models.dart';
import 'personal_profile_showcase_copy.dart';

/// The main role (user 11-05, plan B): one of the skilled roles, at most one,
/// set in the editor with words, never guessed from a colour or an icon.
abstract final class ProfileMainRole {
  /// Whether this page can save a main role. The local page always can; the
  /// HK page only once its server answered with the field (after the second
  /// HK release). Elsewhere the setting is not shown at all.
  static bool editable(PersonalProfileProjection projection) =>
      projection.showcaseData.mainRoleEditable;

  /// The stored main role id, or null.
  static String? idOf(PersonalProfileProjection projection) {
    for (final role in projection.roles) {
      if (role.isPrimary) return ProfileCollaboration.idOf(role, 'roles');
    }
    return null;
  }

  /// [roles] with the one matching [mainRole] marked; a main role that is not
  /// among them marks nothing.
  static List<PersonalProfileTagValue> mark(
    List<PersonalProfileTagValue> roles,
    Object? mainRole,
  ) {
    if (mainRole is! String) return roles;
    var found = false;
    return [
      for (final role in roles)
        if (mainRole.isNotEmpty &&
            !found &&
            ProfileCollaboration.idOf(role, 'roles') == mainRole)
          (() {
            found = true;
            return PersonalProfileTagValue(
              labelKey: role.labelKey,
              category: role.category,
              isPrimary: true,
              displayLabel: role.displayLabel,
            );
          })()
        else if (role.isPrimary)
          PersonalProfileTagValue(
            labelKey: role.labelKey,
            category: role.category,
            displayLabel: role.displayLabel,
          )
        else
          role,
    ];
  }
}

/// The editor part under the skilled roles: each ticked role says in words
/// whether it is the main role and what a click does.
class ProfileMainRolePicker extends StatelessWidget {
  const ProfileMainRolePicker({
    required this.selected,
    required this.mainRole,
    required this.label,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  /// The ticked role ids, in their saved order.
  final List<String> selected;
  final String? mainRole;
  final String Function(String id) label;
  final bool enabled;

  /// The new main role, or null to have none.
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String copy(String key) => profileShowcaseCopy(context, key);
    final caption = TextStyle(fontSize: 12, color: tokens.colors.textSecondary);
    return Padding(
      key: const Key('profile-main-role-picker'),
      padding: EdgeInsets.only(top: tokens.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy('mainRolePickTitle'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            copy(selected.isEmpty ? 'mainRolePickEmpty' : 'mainRolePickNote'),
            style: caption,
          ),
          for (final id in selected)
            Padding(
              padding: EdgeInsets.only(top: tokens.space.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label(id),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: id == mainRole ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.space.sm),
                  StarBridgeActionButton(
                    controlKey: Key('profile-main-role-$id'),
                    kind: id == mainRole
                        ? StarBridgeActionKind.primary
                        : StarBridgeActionKind.secondary,
                    onActivate: enabled
                        ? (_) => onChanged(id == mainRole ? null : id)
                        : null,
                    child: Text(
                      copy(id == mainRole ? 'mainRoleCancel' : 'setMainRole'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The owner's prompt in the header when no main role is set. Never shown to
/// visitors or in the visitor preview.
class ProfileMainRoleHint extends StatelessWidget {
  const ProfileMainRoleHint({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String copy(String key) => profileShowcaseCopy(context, key);
    return Column(
      key: const Key('profile-steam-main-role-hint'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          copy('mainRoleHint'),
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tokens.colors.textPrimary,
          ),
        ),
        Text(
          copy('mainRoleWhere'),
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: tokens.colors.textSecondary),
        ),
      ],
    );
  }
}
