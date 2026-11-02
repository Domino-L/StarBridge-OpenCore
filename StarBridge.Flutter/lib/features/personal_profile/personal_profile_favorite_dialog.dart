import 'package:flutter/material.dart';

import '../hangar/local_hangar_copy.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_models.dart';
import 'personal_profile_ship_names.dart';

class ProfileFavoriteDialog extends StatefulWidget {
  const ProfileFavoriteDialog({
    required this.local,
    required this.selected,
    required this.capacity,
    required this.reserved,
    super.key,
  });
  final PersonalProfileLocalView local;
  final List<String> selected;
  final int capacity;
  final Set<String> reserved;
  @override
  State<ProfileFavoriteDialog> createState() => _FavoriteDialogState();
}

class _FavoriteDialogState extends State<ProfileFavoriteDialog> {
  late final _selected = widget.selected.toList();
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final retained = {
      for (final ship in widget.local.retainedChoices)
        ship.identity.runtimeId: ship,
    };
    // Local choices and saved favorites reference instances. Never substitute
    // a selected historical ID for another ship merely sharing its model.
    final effectiveChoices = widget.local.choices;
    final known = effectiveChoices.map((e) => e.identity.runtimeId).toSet();
    final missing = _selected.where((id) => !known.contains(id)).toList();
    final choices = effectiveChoices
        .where(
          (s) => [
            s.identity.nickname ?? '',
            s.identity.englishName,
            s.identity.simplifiedChineseName,
            s.identity.traditionalChineseName,
            s.manufacturer,
          ].join(' ').toLowerCase().contains(_query),
        )
        .toList();
    return AlertDialog(
      title: Text(strings.text('profile.favorites.edit')),
      content: SizedBox(
        width: 620,
        height: (MediaQuery.sizeOf(context).height * .65).clamp(180, 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${strings.text('profile.local.selected')} ${_selected.length}/${widget.capacity}',
              key: const Key('profile-favorites-capacity'),
            ),
            SizedBox(height: context.tokens.space.md),
            StarBridgeFieldFrame(
              builder: (_, focus) => TextField(
                key: const Key('profile-favorite-search'),
                focusNode: focus,
                decoration: InputDecoration(
                  labelText: strings.text('profile.local.search'),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
            ),
            SizedBox(height: context.tokens.space.sm),
            if (!widget.local.hangarAvailable)
              Text(strings.text('profile.local.noHangar')),
            Expanded(
              child: ListView(
                children: [
                  for (final id in missing)
                    if (retained[id] case final ship?)
                      _choice(context, ship)
                    else
                      StarBridgeCheckboxTile(
                        controlKey: Key('profile-favorite-$id'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        dense: false,
                        value: true,
                        label: strings.text('profile.favorites.unavailable'),
                        onChanged: (_) => setState(() => _selected.remove(id)),
                      ),
                  if (choices.isEmpty && missing.isEmpty)
                    Text(strings.text('profile.local.noResults')),
                  for (final ship in choices) _choice(context, ship),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('profile-favorites-cancel'),
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source),
          child: Text(strings.text('common.cancel')),
        ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.primary,
          controlKey: const Key('profile-favorites-apply'),
          onActivate:
              _selected.length > widget.capacity ||
                  _selected.any(widget.reserved.contains)
              ? null
              : (source) => dismissStarBridgeDialog<List<String>>(
                  context,
                  source: source,
                  result: List<String>.unmodifiable(_selected),
                ),
          child: Text(strings.text('profile.favorites.apply')),
        ),
      ],
    );
  }

  Widget _choice(BuildContext context, PersonalProfileShipSummary ship) {
    final id = ship.identity.runtimeId;
    final checked = _selected.contains(id);
    final reserved = widget.reserved.contains(id);
    final strings = AppStrings.of(context);
    final index = widget.local.choices.indexOf(ship) + 1;
    return StarBridgeCheckboxTile(
      controlKey: Key('profile-favorite-$id'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
      value: checked,
      label:
          '${PersonalProfileShipNames.primary(context, ship.identity)}${ship.formerlyOwned ? ' · ${LocalHangarCopy(context).formerlyOwned}' : ''}',
      subtitle: reserved
          ? strings.text('profile.favorites.used')
          : index > 0
          ? '${PersonalProfileShipNames.secondary(context, ship.identity) ?? ship.manufacturer} · #$index'
          : ship.manufacturer,
      onChanged: reserved || (!checked && _selected.length >= widget.capacity)
          ? null
          : (value) => setState(() {
              if (value == true) {
                _selected.add(id);
              } else {
                _selected.remove(id);
              }
            }),
    );
  }
}
