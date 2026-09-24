import 'package:flutter/material.dart';

import '../hangar/local_hangar_copy.dart';

import '../../app/localization/app_strings.dart';
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
    final selectedFormer = [
      for (final id in _selected)
        if (retained[id]?.formerlyOwned == true) retained[id]!,
    ];
    final effectiveChoices = widget.local.choices.map((ship) {
      if (ship.formerlyOwned) {
        for (final selected in selectedFormer) {
          if (selected.identity.englishName.trim().toLowerCase() ==
              ship.identity.englishName.trim().toLowerCase()) {
            return selected;
          }
        }
      }
      return ship;
    }).toList();
    final known = effectiveChoices.map((e) => e.identity.runtimeId).toSet();
    final missing = _selected.where((id) => !known.contains(id)).toList();
    final choices = effectiveChoices
        .where(
          (s) => [
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
            TextField(
              key: const Key('profile-favorite-search'),
              decoration: InputDecoration(
                labelText: strings.text('profile.local.search'),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
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
                      CheckboxListTile(
                        key: Key('profile-favorite-$id'),
                        value: true,
                        title: Text(
                          strings.text('profile.favorites.unavailable'),
                        ),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.text('common.cancel')),
        ),
        FilledButton(
          key: const Key('profile-favorites-apply'),
          onPressed:
              _selected.length > widget.capacity ||
                  _selected.any(widget.reserved.contains)
              ? null
              : () => Navigator.pop(
                  context,
                  List<String>.unmodifiable(_selected),
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
    return CheckboxListTile(
      key: Key('profile-favorite-$id'),
      dense: true,
      value: checked,
      title: Text(
        '${PersonalProfileShipNames.primary(context, ship.identity)}${ship.formerlyOwned ? ' · ${LocalHangarCopy(context).formerlyOwned}' : ''}',
      ),
      subtitle: Text(
        reserved
            ? strings.text('profile.favorites.used')
            : index > 0
            ? '${ship.manufacturer} · #$index'
            : ship.manufacturer,
      ),
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
