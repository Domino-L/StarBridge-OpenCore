import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import 'privacy_scope_editor.dart';

/// Mirrors Core SharedEventChoice. Never derives consent from realtime fields.
final class EventSharingChoice {
  const EventSharingChoice({required this.enabled, required this.selectedTypes})
    : assert(selectedTypes >= 0 && selectedTypes & ~allTypes == 0);

  static const allTypes = 47; // S2: retired squad bit 16 stays reserved.
  static const unconfirmed = EventSharingChoice(
    enabled: false,
    selectedTypes: allTypes,
  );
  final bool enabled;
  final int selectedTypes;
  @override
  bool operator ==(Object other) =>
      other is EventSharingChoice &&
      enabled == other.enabled &&
      selectedTypes == other.selectedTypes;
  @override
  int get hashCode => Object.hash(enabled, selectedTypes);
  int get effectiveTypes => enabled ? selectedTypes & allTypes : 0;

  EventSharingChoice copyWith({bool? enabled, int? selectedTypes}) =>
      EventSharingChoice(
        enabled: enabled ?? this.enabled,
        selectedTypes: selectedTypes ?? this.selectedTypes,
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'selectedTypes': selectedTypes,
  };

  factory EventSharingChoice.fromJson(Map<String, Object?> json) {
    final mask = json['selectedTypes'];
    if (json.length != 2 ||
        json['enabled'] is! bool ||
        mask is! int ||
        mask < 0 ||
        mask & ~allTypes != 0) {
      throw const FormatException('Invalid event sharing choice');
    }
    return EventSharingChoice(
      enabled: json['enabled'] as bool,
      selectedTypes: mask,
    );
  }
}

/// Draft-only editor. The caller owns revisioned saving and publication status.
/// Not mounted in the product until the event publication capability is present.
class EventScopeEditor extends StatelessWidget {
  const EventScopeEditor({
    required this.scopeKey,
    required this.title,
    required this.description,
    required this.choice,
    required this.canEdit,
    required this.onChanged,
    this.leading,
    super.key,
  });

  final String scopeKey, title, description;
  final Widget? leading;
  final EventSharingChoice choice;
  final bool canEdit;
  final ValueChanged<EventSharingChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return PrivacyScopeEditor(
      scopeKey: scopeKey,
      tone: PrivacyScopeTone.room,
      icon: StarBridgeIconSemantic.activity,
      leading: leading,
      title: title,
      description: description,
      audience: PrivacyAudienceEditor(
        scopeKey: scopeKey,
        label: strings.text('settings.privacy.events.title'),
        choices: [
          PrivacyAudienceChoice(
            id: 'events-enabled',
            label: strings.text('settings.privacy.events.enabled'),
            description: strings.text(
              'settings.privacy.events.enabledDescription',
            ),
            selected: choice.enabled,
            enabled: canEdit,
            onChanged: (value) => onChanged(choice.copyWith(enabled: value)),
          ),
        ],
      ),
      fieldsLabel: strings.text('privacy.scope.fields'),
      fields: [
        for (final entry in const {
          'presence': 1,
          'server': 2,
          'ship': 4,
          'location': 8,
          'life': 32,
        }.entries)
          PrivacyFieldChoice(
            id: entry.key,
            icon: StarBridgeIconSemantic.activity,
            label: strings.text('settings.privacy.events.${entry.key}'),
            description: strings.text(
              'settings.privacy.events.${entry.key}Description',
            ),
            selected: choice.selectedTypes & entry.value != 0,
            enabled: canEdit && choice.enabled,
            onChanged: (value) => onChanged(
              choice.copyWith(
                selectedTypes: value
                    ? choice.selectedTypes | entry.value
                    : choice.selectedTypes & ~entry.value,
              ),
            ),
          ),
      ],
    );
  }
}
