import '../../shared/guide/guide_scope.dart';

import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_presentation.dart';

class LocalHangarSearchField extends StatelessWidget {
  const LocalHangarSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    super.key,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context);
    return StarBridgeFieldFrame(
      enabled: true,
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

/// Presentation only; the page keeps its existing state and action owners.
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
    required this.sort,
    required this.onFormer,
    required this.onFavorites,
    required this.onSort,
    required this.onGrid,
    this.extraAction,
    super.key,
  });
  final bool showRead, showSearch, former, favoritesOnly, grid;
  final String sort;
  final Widget search;
  final Widget? extraAction;
  final VoidCallback? onRead, onRefresh;
  final ValueChanged<bool> onFormer, onFavorites, onGrid;
  final ValueChanged<String> onSort;
  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, bounds) => Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  c.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
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
              if (showSearch)
                SizedBox(
                  width: bounds.maxWidth < 650 ? bounds.maxWidth : 300,
                  child: search,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          children: [
            StarBridgeChoiceChip(
              controlKey: const Key('hangar-current'),
              label: c.currentOwned,
              selected: !former,
              onSelected: (_) => onFormer(false),
            ),
            StarBridgeChoiceChip(
              controlKey: const Key('hangar-former'),
              label: c.formerlyOwned,
              selected: former,
              onSelected: (_) => onFormer(true),
            ),
            StarBridgeChoiceChip.filter(
              controlKey: const Key('hangar-favorites'),
              label: c.favorites,
              selected: favoritesOnly,
              onSelected: onFavorites,
            ),
            SizedBox(
              width: 200,
              child: StarBridgeCompactSelect<String>(
                identity: 'hangar-sort',
                controlKey: const Key('hangar-sort'),
                semanticLabel: c.sortLabel,
                isExpanded: true,
                value: sort,
                options: [
                  StarBridgeSelectOption(value: 'saved', label: c.sortDefault),
                  StarBridgeSelectOption(value: 'name', label: c.sortName),
                  StarBridgeSelectOption(value: 'added', label: c.sortAdded),
                  StarBridgeSelectOption(value: 'value', label: c.sortValue),
                ],
                onSelected: (value, _) => onSort(value),
              ),
            ),
            StarBridgeIconAction(
              controlKey: const Key('hangar-grid'),
              label: c.gridView,
              selected: grid,
              onActivate: (_) => onGrid(true),
              icon: const StandardIcon(StandardIconSemantic.dashboard),
            ),
            StarBridgeIconAction(
              controlKey: const Key('hangar-list'),
              label: c.listView,
              selected: !grid,
              onActivate: (_) => onGrid(false),
              icon: const StandardIcon(StandardIconSemantic.listView),
            ),
          ],
        ),
      ],
    );
  }
}

class LocalHangarFilters extends StatelessWidget {
  const LocalHangarFilters({
    required this.roles,
    required this.sizes,
    required this.category,
    required this.status,
    required this.size,
    required this.hasFilters,
    required this.onCategory,
    required this.onStatus,
    required this.onSize,
    required this.onClear,
    super.key,
  });
  final Set<String> roles, sizes;
  final String? category, status, size;
  final bool hasFilters;
  final ValueChanged<String?> onCategory, onStatus, onSize;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StarBridgeChoiceChip(
              controlKey: const Key('hangar-role-all'),
              label: c.allRoles,
              selected: category == null,
              onSelected: (_) => onCategory(null),
            ),
            for (final role in LocalHangarPresentation.categories.where(
              roles.contains,
            ))
              StarBridgeChoiceChip(
                controlKey: ValueKey('hangar-role-$role'),
                label: c.category(role),
                selected: category == role,
                onSelected: (_) => onCategory(role),
              ),
            for (final choice in ['flyable', 'concept'])
              StarBridgeChoiceChip.filter(
                controlKey: ValueKey('hangar-status-$choice'),
                label: c.status(choice),
                selected: status == choice,
                onSelected: (value) => onStatus(value ? choice : null),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (sizes.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StarBridgeChoiceChip(
                controlKey: const Key('hangar-size-all'),
                label: c.allSizes,
                selected: size == null,
                onSelected: (_) => onSize(null),
              ),
              for (final choice in sizes)
                StarBridgeChoiceChip(
                  controlKey: ValueKey('hangar-size-$choice'),
                  label: c.combatSize(choice)!,
                  selected: size == choice,
                  onSelected: (_) => onSize(choice),
                ),
              if (hasFilters)
                StarBridgeActionButton(
                  controlKey: const Key('hangar-clear-active-filters'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (_) => onClear(),
                  child: Text(c.clearFilters),
                ),
            ],
          ),
      ],
    );
  }
}
