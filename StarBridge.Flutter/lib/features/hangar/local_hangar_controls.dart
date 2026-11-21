import '../../shared/guide/guide_scope.dart';

import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo_choice.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_presentation.dart';

class LocalHangarSearchField extends StatelessWidget {
  const LocalHangarSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.focusNode,
    super.key,
  });
  final FocusNode? focusNode;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context);
    return StarBridgeFieldFrame(
      enabled: true,
      focusNode: focusNode,
      builder: (_, focus) => TextField(
        focusNode: focus,
        key: const Key('local-hangar-search'),
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: c.search,
          suffixIcon: controller.text.isEmpty
              ? null
              : StarBridgeIconAction(
                  controlKey: const Key('local-hangar-clear-search'),
                  label: c.clearSearch,
                  icon: const StarBridgeIcon(
                    StarBridgeIconSemantic.windowClose,
                  ),
                  onActivate: (_) => onClear(),
                ),
        ),
      ),
    );
  }
}

/// A thin rule between groups of choices on one line.
class _ChoiceRule extends StatelessWidget {
  const _ChoiceRule();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 9,
    height: 28,
    child: Center(
      child: SizedBox(
        width: 1,
        height: 18,
        child: ColoredBox(color: context.tokens.surfaces.panel.border),
      ),
    ),
  );
}

/// The two lines above the wall. Presentation only; the page keeps its state
/// and action owners. One line finds and groups ships and holds the actions,
/// the next chooses which ships show and how they read. Both wrap when narrow.
class LocalHangarToolbar extends StatelessWidget {
  const LocalHangarToolbar({
    required this.showRead,
    required this.onRead,
    required this.onRefresh,
    required this.showSearch,
    required this.search,
    required this.former,
    required this.favoritesOnly,
    required this.grid,
    required this.compact,
    required this.byMaker,
    required this.sort,
    required this.onFormer,
    required this.onFavorites,
    required this.onSort,
    required this.onGrid,
    required this.onCompact,
    required this.onByMaker,
    this.filters = const [],
    this.sizeFilters = const [],
    this.ownedCount,
    this.favoriteCount,
    this.extraAction,
    super.key,
  });
  final bool showRead,
      showSearch,
      former,
      favoritesOnly,
      grid,
      compact,
      byMaker;
  final String sort;
  final Widget search;
  final Widget? extraAction;
  final List<Widget> filters, sizeFilters;
  final int? ownedCount, favoriteCount;
  final VoidCallback? onRead, onRefresh;
  final ValueChanged<bool> onFormer, onFavorites, onGrid, onCompact, onByMaker;
  final ValueChanged<String> onSort;
  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context);
    String counted(String label, int? count) =>
        count == null ? label : '$label $count';
    return LayoutBuilder(
      builder: (context, bounds) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (showSearch)
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: bounds.maxWidth < 650 ? bounds.maxWidth : 300,
                      child: search,
                    ),
                    const _ChoiceRule(),
                    Text(
                      c.segmentLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    OrganizationHoloChoice(
                      controlKey: const Key('hangar-by-size'),
                      label: c.bySize,
                      selected: !byMaker,
                      inGroup: true,
                      onSelected: (_) => onByMaker(false),
                    ),
                    OrganizationHoloChoice(
                      controlKey: const Key('hangar-by-maker'),
                      label: c.byMaker,
                      selected: byMaker,
                      inGroup: true,
                      onSelected: (_) => onByMaker(true),
                    ),
                  ],
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (showRead)
                    GuideAnchor(
                      id: 'hangar.readbar',
                      child: StarBridgeActionButton(
                        controlKey: const Key('local-hangar-read'),
                        kind: StarBridgeActionKind.primary,
                        onActivate: onRead == null ? null : (_) => onRead!(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const StarBridgeIcon(StarBridgeIconSemantic.hangar),
                            const SizedBox(width: 8),
                            Flexible(child: Text(c.read)),
                          ],
                        ),
                      ),
                    ),
                  StarBridgeActionButton(
                    controlKey: const Key('local-hangar-refresh'),
                    onActivate: onRefresh == null ? null : (_) => onRefresh!(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                        const SizedBox(width: 8),
                        Flexible(child: Text(c.refresh)),
                      ],
                    ),
                  ),
                  ?extraAction,
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OrganizationHoloChoice(
                controlKey: const Key('hangar-current'),
                label: counted(c.currentOwned, ownedCount),
                selected: !former,
                inGroup: true,
                onSelected: (_) => onFormer(false),
              ),
              OrganizationHoloChoice(
                controlKey: const Key('hangar-former'),
                label: c.formerlyOwned,
                selected: former,
                inGroup: true,
                onSelected: (_) => onFormer(true),
              ),
              OrganizationHoloChoice(
                controlKey: const Key('hangar-favorites'),
                label: counted(c.favorites, favoriteCount),
                selected: favoritesOnly,
                onSelected: onFavorites,
              ),
              if (filters.isNotEmpty) const _ChoiceRule(),
              ...filters,
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: sizeFilters,
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    child: StarBridgeCompactSelect<String>(
                      identity: 'hangar-sort',
                      controlKey: const Key('hangar-sort'),
                      semanticLabel: c.sortLabel,
                      isExpanded: true,
                      value: sort,
                      options: [
                        StarBridgeSelectOption(
                          value: 'saved',
                          label: c.sortDefault,
                        ),
                        StarBridgeSelectOption(
                          value: 'name',
                          label: c.sortName,
                        ),
                        StarBridgeSelectOption(
                          value: 'added',
                          label: c.sortAdded,
                        ),
                        StarBridgeSelectOption(
                          value: 'value',
                          label: c.sortValue,
                        ),
                      ],
                      onSelected: (value, _) => onSort(value),
                    ),
                  ),
                  const _ChoiceRule(),
                  OrganizationHoloChoice(
                    controlKey: const Key('hangar-grid'),
                    label: c.gridView,
                    selected: grid && !compact,
                    inGroup: true,
                    onSelected: (_) {
                      onCompact(false);
                      onGrid(true);
                    },
                  ),
                  OrganizationHoloChoice(
                    controlKey: const Key('hangar-compact'),
                    label: c.compactView,
                    selected: grid && compact,
                    inGroup: true,
                    onSelected: (_) {
                      onCompact(true);
                      onGrid(true);
                    },
                  ),
                  OrganizationHoloChoice(
                    controlKey: const Key('hangar-list'),
                    label: c.listView,
                    selected: !grid,
                    inGroup: true,
                    onSelected: (_) => onGrid(false),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Which ships show, by role and status; these join the toolbar's own line.
List<Widget> localHangarRoleChoices(
  BuildContext context, {
  required Set<String> roles,
  required String? category,
  required String? status,
  required ValueChanged<String?> onCategory,
  required ValueChanged<String?> onStatus,
}) {
  final c = LocalHangarCopy(context);
  return [
    OrganizationHoloChoice(
      controlKey: const Key('hangar-role-all'),
      label: c.allRoles,
      selected: category == null,
      inGroup: true,
      onSelected: (_) => onCategory(null),
    ),
    for (final role in LocalHangarPresentation.categories.where(roles.contains))
      OrganizationHoloChoice(
        controlKey: ValueKey('hangar-role-$role'),
        label: c.category(role),
        selected: category == role,
        inGroup: true,
        onSelected: (_) => onCategory(role),
      ),
    for (final choice in ['flyable', 'concept'])
      OrganizationHoloChoice(
        controlKey: ValueKey('hangar-status-$choice'),
        label: c.status(choice),
        selected: status == choice,
        onSelected: (value) => onStatus(value ? choice : null),
      ),
  ];
}

/// Which ships show, by size, and the way out of any active filter.
List<Widget> localHangarSizeChoices(
  BuildContext context, {
  required Set<String> sizes,
  required String? size,
  required bool hasFilters,
  required ValueChanged<String?> onSize,
  required VoidCallback onClear,
}) {
  final c = LocalHangarCopy(context);
  const sizeOrder = [
    'capital',
    'large',
    'medium',
    'small',
    'ground-large',
    'ground-medium',
    'ground-small',
  ];
  return [
    if (sizes.isNotEmpty) ...[
      OrganizationHoloChoice(
        controlKey: const Key('hangar-size-all'),
        label: c.allSizes,
        selected: size == null,
        inGroup: true,
        onSelected: (_) => onSize(null),
      ),
      for (final choice in sizeOrder.where(sizes.contains))
        OrganizationHoloChoice(
          controlKey: ValueKey('hangar-size-$choice'),
          label: c.combatSize(choice)!,
          selected: size == choice,
          inGroup: true,
          onSelected: (_) => onSize(choice),
        ),
    ],
    if (hasFilters)
      StarBridgeActionButton(
        controlKey: const Key('hangar-clear-active-filters'),
        kind: StarBridgeActionKind.quiet,
        onActivate: (_) => onClear(),
        child: Text(c.clearFilters),
      ),
  ];
}
