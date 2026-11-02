import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo.dart';
import '../common/organization_holo_choice.dart';
import 'community_ships_copy.dart';

/// One row, as the approved preview (user decision 2026-10-29, option D):
/// the search field, the filter chips with their counts, then the sort
/// choice and the view switch (按舰船 / 按持有人 / 列表) at the end. Inside
/// the holo shell the chips take the banner slant. Narrow windows stack the
/// three parts.
class CommunityShipsToolbar extends StatelessWidget {
  const CommunityShipsToolbar({
    required this.search,
    required this.filter,
    required this.sort,
    required this.descending,
    required this.viewMode,
    required this.enabled,
    required this.onSearch,
    required this.onFilter,
    required this.onSort,
    required this.onDirection,
    required this.onView,
    this.counts,
    super.key,
  });

  final TextEditingController search;
  final String filter, sort, viewMode;
  final bool enabled, descending;
  final VoidCallback onSearch, onDirection;
  final ValueChanged<String> onFilter, onSort, onView;

  /// Per filter key, from the full inventory; null while it loads.
  final Map<String, int>? counts;

  static const filters = [
    'all',
    'capital',
    'large',
    'medium',
    'small',
    'flyable',
    'concept',
    'unknown',
  ];

  /// The hairline between the size filters and the status filters.
  static const _separated = {'flyable'};
  static const sorts = ['spec', 'name', 'status', 'price', 'role', 'owner'];
  static const views = ['cards', 'owners', 'list'];
  static const searchWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    String t(String key) => communityShipsText(context, key);
    final holo = OrganizationHolo.of(context);
    final c = OrganizationHoloColors(context);
    String chipLabel(String key) {
      final count = counts?[key];
      return count == null ? t(key) : '${t(key)} $count';
    }

    // Holo surfaces draw their own slanted choice; elsewhere the chips keep the
    // page's rounded face. Either way a choice's width never changes when chosen.
    Widget choice({
      required Key controlKey,
      required String label,
      required bool selected,
      required ValueChanged<bool>? onSelected,
    }) => holo
        ? OrganizationHoloChoice(
            controlKey: controlKey,
            label: label,
            selected: selected,
            onSelected: onSelected,
          )
        : StarBridgeChoiceChip(
            controlKey: controlKey,
            label: label,
            selected: selected,
            onSelected: onSelected,
          );
    Widget chips(Widget child) => holo
        ? child
        : ChipTheme(
            data: ChipTheme.of(context).copyWith(
              showCheckmark: false,
              labelStyle: Theme.of(context).textTheme.labelLarge,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              elevation: 0,
              pressElevation: 0,
            ),
            child: child,
          );
    final separator = Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: c.hair,
    );
    final decoration = InputDecoration(
      hintText: t('search'),
      counterText: '',
      isDense: true,
      // In the holo shell the search pair's button takes the icon's place.
      suffixIcon: holo
          ? null
          : StarBridgeIconAction(
              controlKey: const Key('community-ships-search'),
              label: t('searchButton'),
              onActivate: enabled ? (_) => onSearch() : null,
              icon: const StandardIcon(StandardIconSemantic.search, size: 18),
            ),
    );
    final input = StarBridgeFieldFrame(
      enabled: enabled,
      builder: (_, focus) => TextField(
        key: const Key('community-ships-search-field'),
        focusNode: focus,
        controller: search,
        maxLength: 128,
        enabled: enabled,
        // Enter is a keyboard activation; the read records it so.
        onSubmitted: (_) => runStarBridgeActivation<void>(
          InteractionSource.keyboard,
          () async => onSearch(),
        ),
        decoration: holo
            ? organizationHoloField(context, decoration, slantEnd: true)
            : decoration,
      ),
    );
    // The same pair as the member boards: the button's slanted start sits
    // against the field's slanted end, a few pixels apart.
    final field = !holo
        ? input
        : Row(
            children: [
              Expanded(child: input),
              Transform.translate(
                offset: Offset(
                  4 - organizationHoloRun(organizationHoloFieldHeight(context)),
                  0,
                ),
                child: SizedBox(
                  height: organizationHoloFieldHeight(context),
                  child: StarBridgeActionButton(
                    controlKey: const Key('community-ships-search'),
                    nativeStyle: organizationHoloButton(
                      context,
                      parallelogram: true,
                    ),
                    onActivate: enabled ? (_) => onSearch() : null,
                    child: Text(t('searchButton')),
                  ),
                ),
              ),
            ],
          );
    final filterStrip = SizedBox(
      height: 38,
      child: chips(
        ListView(
          key: const ValueKey('community-ship-filters'),
          scrollDirection: Axis.horizontal,
          children: [
            for (final key in filters) ...[
              if (_separated.contains(key))
                Center(child: separator)
              else if (key != 'all')
                const SizedBox(width: 6),
              Center(
                child: choice(
                  controlKey: ValueKey('community-ship-filter-$key'),
                  label: chipLabel(key),
                  selected: filter == key,
                  onSelected: enabled ? (_) => onFilter(key) : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    // The sort and its direction read as one chip (user 2026-10-30: the loose
    // arrow beside it looked out of place).
    final sortBody = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${t('sort')} · ', style: Theme.of(context).textTheme.labelLarge),
        DropdownButtonHideUnderline(
          child: StarBridgeCompactSelect<String>(
            identity: 'community-ships-sort',
            controlKey: const ValueKey('community-ships-sort-control'),
            semanticLabel: t('sort'),
            value: sort,
            isDense: true,
            selectedMaxLines: 1,
            selectedOverflow: TextOverflow.ellipsis,
            onSelected: enabled ? (next, _) => onSort(next) : null,
            options: sorts
                .map(
                  (key) => StarBridgeSelectOption(
                    value: key,
                    // The price column's short name keeps the chip narrow.
                    label: t(key == 'price' ? 'priceColumn' : key),
                  ),
                )
                .toList(),
          ),
        ),
        Container(
          width: 1,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: c.hair,
        ),
        StarBridgeIconAction(
          controlKey: const Key('community-ships-direction'),
          label: t(descending ? 'descending' : 'ascending'),
          quiet: true,
          constraints: BoxConstraints.tight(const Size.square(24)),
          padding: EdgeInsets.zero,
          onActivate: enabled ? (_) => onDirection() : null,
          icon: StandardIcon(
            descending
                ? StandardIconSemantic.south
                : StandardIconSemantic.north,
            size: 16,
          ),
        ),
      ],
    );
    final sortChip = holo
        ? OrganizationHoloChoiceFrame(child: sortBody)
        : Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ShapeDecoration(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: c.glass),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: sortBody,
          );
    final switcher = chips(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final view in views) ...[
            if (view != views.first) const SizedBox(width: 6),
            choice(
              controlKey: ValueKey('community-ships-view-$view'),
              label: t(switch (view) {
                'owners' => 'viewOwners',
                'list' => 'viewList',
                _ => 'viewCards',
              }),
              selected: viewMode == view,
              onSelected: (_) => onView(view),
            ),
          ],
        ],
      ),
    );
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [sortChip, separator, switcher],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 1180
          ? Row(
              children: [
                SizedBox(width: searchWidth, child: field),
                const SizedBox(width: 10),
                Expanded(child: filterStrip),
                const SizedBox(width: 10),
                trailing,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field,
                SizedBox(height: context.tokens.space.xs),
                filterStrip,
                SizedBox(height: context.tokens.space.xs),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [sortChip, switcher],
                ),
              ],
            ),
    );
  }
}
