import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_ships_models.dart';
import 'official_fleet_ships_module.dart';

class OfficialFleetShipsToolbar extends StatelessWidget {
  const OfficialFleetShipsToolbar({
    required this.projection,
    required this.module,
    required this.searchController,
    super.key,
  });

  final OfficialFleetShipsProjection projection;
  final OfficialFleetShipsModule module;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final query = projection.query!;
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final search = SizedBox(
      width: 340,
      child: StarBridgeFieldFrame(
        enabled: true,
        builder: (_, focus) => TextField(
          focusNode: focus,
          key: const Key('official-fleet-ships-search'),
          controller: searchController,
          onSubmitted: module.search,
          decoration: InputDecoration(
            hintText: strings.text('officialFleet.ships.search'),
            prefixIcon: const Padding(
              padding: EdgeInsets.all(10),
              child: StarBridgeIcon(StarBridgeIconSemantic.hangar),
            ),
            suffixIcon: IconButton(
              tooltip: strings.text('officialFleet.ships.search.submit'),
              onPressed: () => module.search(searchController.text),
              icon: const StarBridgeIcon(StarBridgeIconSemantic.forward),
            ),
          ),
        ),
      ),
    );
    final filters = Wrap(
      spacing: tokens.space.xs,
      runSpacing: tokens.space.xs,
      children: [
        for (final filter in OfficialFleetShipFilter.values)
          StarBridgeChoiceChip(
            controlKey: Key('official-fleet-ships-filter-${filter.name}'),
            label: strings.text(_filterLabelKey(filter)),
            selected: query.filter == filter,
            onSelected: (_) => module.setFilter(filter),
          ),
      ],
    );
    final pageSize = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.text('officialFleet.ships.pageSize'),
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(width: tokens.space.sm),
        StarBridgeCompactSelect<int>(
          identity: 'official-fleet-ships-page-size',
          controlKey: const Key('official-fleet-ships-page-size'),
          semanticLabel: strings.text('officialFleet.ships.pageSize'),
          value: query.pageSize,
          options: const [
            StarBridgeSelectOption(value: 25, label: '25'),
            StarBridgeSelectOption(value: 50, label: '50'),
            StarBridgeSelectOption(value: 100, label: '100'),
          ],
          onSelected: (value, _) => module.setPageSize(value),
        ),
      ],
    );
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                SizedBox(height: tokens.space.md),
                filters,
                SizedBox(height: tokens.space.sm),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: pageSize,
                ),
              ],
            );
          }
          return Row(
            children: [
              search,
              SizedBox(width: tokens.space.md),
              Expanded(child: filters),
              pageSize,
            ],
          );
        },
      ),
    );
  }
}

String _filterLabelKey(OfficialFleetShipFilter filter) => switch (filter) {
  OfficialFleetShipFilter.all => 'officialFleet.ships.filter.all',
  OfficialFleetShipFilter.requestable =>
    'officialFleet.ships.filter.requestable',
  OfficialFleetShipFilter.sharedByMe => 'officialFleet.ships.filter.mine',
};
