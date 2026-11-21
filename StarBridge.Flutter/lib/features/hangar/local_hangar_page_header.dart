import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'hangar_guide.dart';
import 'local_hangar_controls.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_inventory_projection.dart';
import 'local_hangar_overview.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_read_status.dart';
import 'local_hangar_wall_card.dart';

/// Everything above the wall. It owns no state and scrolls away with the first
/// section, leaving the jump bar in charge.
class LocalHangarPageHeader extends StatelessWidget {
  const LocalHangarPageHeader({
    required this.showRead,
    required this.onRead,
    required this.onRefresh,
    required this.extraAction,
    required this.search,
    required this.searchFocus,
    required this.onQuery,
    required this.onClearQuery,
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
    required this.snapshot,
    required this.source,
    required this.inventory,
    required this.saved,
    required this.guided,
    required this.loading,
    required this.failed,
    required this.favoriteBusy,
    required this.favoriteFailed,
    required this.readSource,
    required this.readPhase,
    required this.inheritReadOpeningSource,
    required this.favoriteSource,
    required this.favoritePhase,
    required this.onRetry,
    required this.category,
    required this.status,
    required this.size,
    required this.onCategory,
    required this.onStatus,
    required this.onSize,
    required this.onClearFilters,
    this.cloud,
    super.key,
  });

  /// Account copy bar (switch + where the hangar is kept); null = local only.
  final Widget? cloud;
  final bool showRead, former, favoritesOnly, grid, compact, byMaker;
  final bool saved, guided, loading, failed, favoriteBusy, favoriteFailed;
  final bool inheritReadOpeningSource;
  final VoidCallback? onRead, onRefresh;
  final Widget? extraAction;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ValueChanged<String> onQuery, onSort;
  final VoidCallback onClearQuery, onRetry, onClearFilters;
  final String sort;
  final String? category, status, size;
  final ValueChanged<bool> onFormer, onFavorites, onGrid, onCompact, onByMaker;
  final ValueChanged<String?> onCategory, onStatus, onSize;
  final LocalHangarSnapshot? snapshot;
  final List<LocalHangarShip> source;
  final LocalHangarInventoryProjection inventory;
  final InteractionSource readSource, favoriteSource;
  final int readPhase, favoritePhase;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), t = context.tokens;
    final hasFilters =
        search.text.trim().isNotEmpty ||
        category != null ||
        status != null ||
        size != null ||
        favoritesOnly;
    // Said once, next to when the hangar was saved, or under the empty hint.
    final storage =
        cloud ??
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Text(
            c.deviceStorage,
            key: const Key('hangar-device-storage'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: t.colors.textSecondary),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocalHangarToolbar(
          showRead: showRead,
          onRead: onRead,
          onRefresh: onRefresh,
          extraAction: extraAction,
          showSearch: source.isNotEmpty,
          search: LocalHangarSearchField(
            controller: search,
            focusNode: searchFocus,
            onChanged: onQuery,
            onClear: onClearQuery,
          ),
          former: former,
          favoritesOnly: favoritesOnly,
          grid: grid,
          compact: compact,
          byMaker: byMaker,
          sort: sort,
          ownedCount: snapshot?.ships.length,
          favoriteCount: source.where((ship) => ship.isFavorite).length,
          onFormer: onFormer,
          onFavorites: onFavorites,
          onSort: onSort,
          onGrid: onGrid,
          onCompact: onCompact,
          onByMaker: onByMaker,
          filters: source.isEmpty
              ? const []
              : localHangarRoleChoices(
                  context,
                  roles: inventory.roles,
                  category: category,
                  status: status,
                  onCategory: onCategory,
                  onStatus: onStatus,
                ),
          sizeFilters: source.isEmpty
              ? const []
              : [
                  ...localHangarSizeChoices(
                    context,
                    sizes: inventory.sizes,
                    size: size,
                    hasFilters: hasFilters,
                    onSize: onSize,
                    onClear: onClearFilters,
                  ),
                  Text(
                    c.count(inventory.ships.length),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
        ),
        const SizedBox(height: 6),
        if (former)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(favoritesOnly ? c.formerBookmarksHint : c.formerHint),
          ),
        if (saved && !former)
          LayoutBuilder(
            builder: (context, bounds) {
              final overview = LocalHangarOverview(
                ships: snapshot!.ships
                    .map(LocalHangarPresentation.fromSaved)
                    .toList(),
                note: snapshot!.fromLegacyProfile
                    ? c.legacySource
                    : c.savedOn(context, snapshot!.inventoryReadSavedAt),
              );
              if (bounds.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [overview, const LocalHangarNotice()],
                );
              }
              return Row(
                children: [
                  Expanded(child: overview),
                  SizedBox(width: t.space.sm),
                  const LocalHangarNotice(),
                ],
              );
            },
          ),
        if (saved && !former) storage,
        LocalHangarReadStatus(
          snapshot: snapshot,
          saved: saved,
          showSaved: former,
          loading: loading,
          favoriteBusy: favoriteBusy,
          favoriteFailed: favoriteFailed,
          failed: failed,
          readSource: readSource,
          readPhase: readPhase,
          inheritReadOpeningSource: inheritReadOpeningSource,
          favoriteSource: favoriteSource,
          favoritePhase: favoritePhase,
          onRetry: onRetry,
        ),
        if (guided) ...[
          hangarGuideEmpty(favoriteBusy ? null : onRead),
          // A never-saved account is exactly the one a restore can fill.
          ?cloud,
        ] else if ((!loading || snapshot != null) &&
            !failed &&
            source.isEmpty) ...[
          Text(
            former
                ? c.formerEmpty
                : saved
                ? c.emptySaved
                : c.noSaved,
          ),
          const SizedBox(height: 6),
          if (!former) Text(c.emptyHint),
          if (!former && !saved) storage,
        ],
        if (source.isNotEmpty && inventory.ships.isEmpty) ...[
          const SizedBox(height: 20),
          Text(c.noMatches),
          const SizedBox(height: 6),
          Text(c.searchHint),
          StarBridgeActionButton(
            controlKey: const Key('hangar-clear-filters'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (_) => onClearFilters(),
            child: Text(c.clearFilters),
          ),
        ],
      ],
    );
  }
}
