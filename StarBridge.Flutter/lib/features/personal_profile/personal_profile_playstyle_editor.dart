import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
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
    this.initial,
    super.key,
  });
  final PersonalProfileProjection projection;
  final PersonalProfilePlayStyle? initial;
  final bool enabled;
  final ValueChanged<PersonalProfilePlayStyle> onChanged;
  @override
  State<PersonalProfilePlayStyleEditor> createState() =>
      PersonalProfilePlayStyleEditorState();
}

class PersonalProfilePlayStyleEditorState
    extends State<PersonalProfilePlayStyleEditor> {
  bool _instantOpening = false;
  void openAll() {
    // This is presentation only, just as expanding the former controllers was.
    // Publish the keyboard's instantaneous policy for this expansion frame;
    // subsequent pointer selections keep their normal feedback.
    setState(() {
      _instantOpening =
          currentStarBridgeActivationSource == InteractionSource.keyboard;
      _expanded.addAll(_titles.keys);
    });
    if (_instantOpening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _instantOpening) {
          setState(() => _instantOpening = false);
        }
      });
    }
  }

  late final Map<String, List<String>> _selections = {
    'roles':
        widget.initial?.roles?.toList() ??
        ProfileCollaboration.ids(widget.projection.roles, 'roles'),
    'interests':
        widget.initial?.interests?.toList() ??
        ProfileCollaboration.ids(
          widget.projection.participationInterests,
          'interests',
        ),
    'support':
        widget.initial?.support?.toList() ??
        ProfileCollaboration.ids(
          widget.projection.supportCapabilities,
          'support',
        ),
  };
  final _changed = <String>{};
  late final Map<String, List<String>> _retained;
  @override
  void initState() {
    super.initState();
    _retained = {
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
    if (widget.initial?.roles != null) _changed.add('roles');
    if (widget.initial?.interests != null) _changed.add('interests');
    if (widget.initial?.support != null) _changed.add('support');
  }

  final _expanded = <String>{};
  static const _titles = {
    'roles': 'profile.roles.title',
    'interests': 'profile.participation.title',
    'support': 'profile.support.title',
  };
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final data = resolveStarBridgeInteraction(context);
    return InteractionScope(
      data: data.copyWith(reduceMotion: data.reduceMotion || _instantOpening),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final group in _titles.keys)
              FormField<List<String>>(
                key: Key('profile-$group-validation'),
                validator: (_) =>
                    !_changed.contains(group) ||
                        ProfileCollaboration.validGroup(
                          _selections[group],
                          group,
                          retained: _retained[group]!,
                        )
                    ? null
                    : strings.text('profile.collab.selectionInvalid'),
                builder: (field) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: SuiteExpander(
                    key: Key('profile-$group-editor'),
                    expanded: _expanded.contains(group),
                    maintainState: false,
                    onChanged: (value) => setState(() {
                      value ? _expanded.add(group) : _expanded.remove(group);
                    }),
                    title: strings.text(_titles[group]!),
                    subtitle:
                        '${strings.text('profile.local.selected')} '
                        '${_selections[group]!.length} / ${ProfileCollaboration.limit(group)}',
                    headerPadding: EdgeInsets.zero,
                    headerMinHeight: 0,
                    headerBuilder: (context, visual, open) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.text(_titles[group]!),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        '${strings.text('profile.local.selected')} '
                        '${_selections[group]!.length} / ${ProfileCollaboration.limit(group)}',
                      ),
                      trailing: StarBridgeIcon(
                        _expanded.contains(group)
                            ? StarBridgeIconSemantic.menuDown
                            : StarBridgeIconSemantic.forward,
                      ),
                    ),
                    bodyPadding: EdgeInsets.only(
                      bottom: context.tokens.space.md,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (field.hasError)
                          Text(
                            field.errorText!,
                            style: TextStyle(
                              color: context.tokens.colors.warning,
                            ),
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
                                StarBridgeChoiceChip.filter(
                                  controlKey: Key('profile-$group-$id'),
                                  label:
                                      ProfileCollaboration
                                              .options[group]![id] ==
                                          null
                                      ? id
                                      : strings.text(
                                          ProfileCollaboration
                                              .options[group]![id]!
                                              .labelKey,
                                        ),
                                  selected: _selections[group]!.contains(id),
                                  onSelected:
                                      !widget.enabled ||
                                          (!_selections[group]!.contains(id) &&
                                              _selections[group]!.length >=
                                                  ProfileCollaboration.limit(
                                                    group,
                                                  ))
                                      ? null
                                      : (selected) {
                                          setState(() {
                                            _changed.add(group);
                                            selected
                                                ? _selections[group]!.add(id)
                                                : _selections[group]!.remove(
                                                    id,
                                                  );
                                          });
                                          field.didChange(
                                            List.of(_selections[group]!),
                                          );
                                          widget.onChanged(
                                            PersonalProfilePlayStyle(
                                              roles: _changed.contains('roles')
                                                  ? List.of(
                                                      _selections['roles']!,
                                                    )
                                                  : null,
                                              interests:
                                                  _changed.contains('interests')
                                                  ? List.of(
                                                      _selections['interests']!,
                                                    )
                                                  : null,
                                              support:
                                                  _changed.contains('support')
                                                  ? List.of(
                                                      _selections['support']!,
                                                    )
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
                ),
              ),
          ],
        ),
      ),
    );
  }
}
