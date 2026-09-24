import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import 'personal_profile_models.dart';
import 'personal_profile_collaboration.dart';

/// Owns selection drafts only; persistence stays at the profile port.
class PersonalProfilePlayStyleEditor extends StatefulWidget {
  const PersonalProfilePlayStyleEditor({
    required this.projection,
    required this.enabled,
    required this.onChanged,
    super.key,
  });
  final PersonalProfileProjection projection;
  final bool enabled;
  final ValueChanged<PersonalProfilePlayStyle> onChanged;
  @override
  State<PersonalProfilePlayStyleEditor> createState() =>
      PersonalProfilePlayStyleEditorState();
}

class PersonalProfilePlayStyleEditorState
    extends State<PersonalProfilePlayStyleEditor> {
  final _controllers = <String, ExpansibleController>{
    for (final group in _titles.keys) group: ExpansibleController(),
  };
  void openAll() {
    for (final controller in _controllers.values) {
      controller.expand();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  late final Map<String, List<String>> _selections = {
    'roles': ProfileCollaboration.ids(widget.projection.roles, 'roles'),
    'interests': ProfileCollaboration.ids(
      widget.projection.participationInterests,
      'interests',
    ),
    'support': ProfileCollaboration.ids(
      widget.projection.supportCapabilities,
      'support',
    ),
  };
  final _changed = <String>{};
  final _expanded = <String>{};
  static const _titles = {
    'roles': 'profile.roles.title',
    'interests': 'profile.participation.title',
    'support': 'profile.support.title',
  };
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (final group in _titles.keys)
            FormField<List<String>>(
              key: Key('profile-$group-validation'),
              validator: (_) =>
                  !_changed.contains(group) ||
                      ProfileCollaboration.validGroup(_selections[group], group)
                  ? null
                  : strings.text('profile.collab.selectionInvalid'),
              builder: (field) => ExpansionTile(
                controller: _controllers[group],
                key: Key('profile-$group-editor'),
                onExpansionChanged: (value) => setState(() {
                  value ? _expanded.add(group) : _expanded.remove(group);
                }),
                trailing: StarBridgeIcon(
                  _expanded.contains(group)
                      ? StarBridgeIconSemantic.menuDown
                      : StarBridgeIconSemantic.forward,
                ),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  strings.text(_titles[group]!),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  '${strings.text('profile.local.selected')} '
                  '${_selections[group]!.length} / ${ProfileCollaboration.limit(group)}',
                ),
                childrenPadding: EdgeInsets.only(
                  bottom: context.tokens.space.md,
                ),
                children: [
                  if (field.hasError)
                    Text(
                      field.errorText!,
                      style: TextStyle(color: context.tokens.colors.warning),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: context.tokens.space.xs,
                      runSpacing: context.tokens.space.xs,
                      children: [
                        for (final id in {
                          ...ProfileCollaboration.options[group]!.keys,
                          ..._selections[group]!,
                        })
                          FilterChip(
                            key: Key('profile-$group-$id'),
                            label: Text(
                              strings.text(
                                ProfileCollaboration
                                        .options[group]![id]
                                        ?.labelKey ??
                                    id,
                              ),
                            ),
                            selected: _selections[group]!.contains(id),
                            onSelected:
                                !widget.enabled ||
                                    (!_selections[group]!.contains(id) &&
                                        _selections[group]!.length >=
                                            ProfileCollaboration.limit(group))
                                ? null
                                : (selected) {
                                    setState(() {
                                      _changed.add(group);
                                      selected
                                          ? _selections[group]!.add(id)
                                          : _selections[group]!.remove(id);
                                    });
                                    field.didChange(
                                      List.of(_selections[group]!),
                                    );
                                    widget.onChanged(
                                      PersonalProfilePlayStyle(
                                        roles: _changed.contains('roles')
                                            ? List.of(_selections['roles']!)
                                            : null,
                                        interests:
                                            _changed.contains('interests')
                                            ? List.of(_selections['interests']!)
                                            : null,
                                        support: _changed.contains('support')
                                            ? List.of(_selections['support']!)
                                            : null,
                                      ),
                                    );
                                  },
                          ),
                      ],
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
