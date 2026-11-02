import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'achievement_art.dart';
import 'achievement_catalog.dart';
import 'achievement_collection_port.dart';
import 'achievement_entry.dart';
import 'achievement_presentation.dart';

typedef InspectAchievement = void Function(
  AchievementDefinition,
  List<AchievementDefinition>,
);

/// Browsing is UI state only; this widget never reads, awards or synchronizes.
class AchievementCollectionView extends StatefulWidget {
  const AchievementCollectionView({
    required this.catalog,
    required this.collection,
    required this.header,
    required this.scrollController,
    required this.focusNodes,
    required this.onInspect,
    required this.scope,
    super.key,
  });
  final List<AchievementDefinition> catalog;
  final AchievementCollection collection;
  final Widget header;
  final ScrollController scrollController;
  final Map<String, FocusNode> focusNodes;
  final InspectAchievement onInspect;
  final int scope;
  @override
  State<AchievementCollectionView> createState() =>
      _AchievementCollectionViewState();
}

class _AchievementCollectionViewState extends State<AchievementCollectionView> {
  final _search = TextEditingController();
  String _group = 'all', _filter = 'all';
  bool _recent = false;
  int _limit = 24;
  AppStrings get s => AppStrings.of(context);
  AchievementPresentation p(AchievementDefinition d) =>
      AchievementPresentation(d, widget.collection, s);
  String groupKey(AchievementDefinition d) => '${d.source.name}:${d.groupId}';
  late Map<String, List<AchievementDefinition>> _groups;
  Map<String, List<AchievementDefinition>> get groups => _groups;

  void _groupCatalog() {
    _groups = {};
    for (final d in widget.catalog) {
      (_groups[groupKey(d)] ??= []).add(d);
    }
  }

  @override
  void initState() {
    super.initState();
    _groupCatalog();
  }

  @override
  void didUpdateWidget(AchievementCollectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.catalog, oldWidget.catalog)) _groupCatalog();
    if (widget.scope != oldWidget.scope) {
      _group = 'all';
      _filter = 'all';
      _recent = false;
      _limit = 24;
      _search.clear();
    }
    if (_group != 'all' && _group != 'earned' && !groups.containsKey(_group)) {
      _group = 'all';
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) {
    setState(() {
      change();
      _limit = 24;
    });
    if (widget.scrollController.hasClients) widget.scrollController.jumpTo(0);
  }

  void _navigate(String group) => _change(() {
    _group = group;
    _filter = 'all';
    _search.clear();
  });
  Widget _entry(
    AchievementDefinition d,
    List<AchievementDefinition> order, {
    bool wall = false,
  }) => AchievementEntry(
    key: Key('achievement-entry-${d.id}'),
    definition: d,
    collection: widget.collection,
    wall: wall,
    focusNode: widget.focusNodes.putIfAbsent(
      d.id,
      () => FocusNode(debugLabel: 'achievement-${d.id}'),
    ),
    onPressed: () => widget.onInspect(d, List.unmodifiable(order)),
  );
  Widget _heading(String text, {String? count, Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text(
                count,
                style: TextStyle(color: context.tokens.colors.textSecondary),
              ),
            ],
          ],
        ),
        ?action,
      ],
    ),
  );
  Widget _empty(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
    decoration: BoxDecoration(
      border: Border.all(color: context.tokens.surfaces.panel.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: context.tokens.colors.textSecondary),
    ),
  );
  Widget _grid(
    List<AchievementDefinition> items,
    List<AchievementDefinition> order,
    bool narrow, {
    bool wall = false,
    bool compact = false,
    int? columns,
  }) => LayoutBuilder(
    builder: (context, c) {
      final n =
          columns ??
          (wall
              ? narrow
                    ? 2
                    : math.max(
                        1,
                        (c.maxWidth / ((compact ? 180 : 150) + 16)).floor(),
                      )
              : narrow
              ? 1
              : 2);
      final gap = wall ? 16.0 : 10.0;
      final width = ((c.maxWidth - gap * (n - 1)) / n).clamp(
        1.0,
        compact && wall && !narrow ? 220.0 : double.infinity,
      );
      return Wrap(
        spacing: gap,
        runSpacing: wall ? 24 : 10,
        children: [
          for (final d in items)
            SizedBox(
              width: width,
              child: _entry(d, order, wall: wall),
            ),
        ],
      );
    },
  );
  Widget _sections(
    List<AchievementDefinition> items,
    bool narrow, {
    bool compact = false,
    List<AchievementDefinition>? allItems,
  }) {
    final earned = items.where((d) => p(d).earned).toList(),
        rest = items.where((d) => !p(d).earned).toList();
    final full = allItems ?? items;
    final allEarned = full.where((d) => p(d).earned).toList();
    final allRest = full.where((d) => !p(d).earned).toList();
    final order = [...allEarned, ...allRest];
    final known = full.every((d) => widget.collection.isConfirmed(d.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          s.text('achievements.earned'),
          count: known ? '${allEarned.length}' : '—',
        ),
        KeyedSubtree(
          key: const Key('achievement-earned-shelf'),
          child: earned.isEmpty
              ? _empty(
                  s.text(
                    known
                        ? 'achievements.emptyEarned'
                        : 'achievements.unknownEarned',
                  ),
                )
              : _grid(earned, order, narrow, wall: true, compact: compact),
        ),
        const SizedBox(height: 34),
        _heading(
          s.text(known ? 'achievements.locked' : 'achievements.available'),
          count: '${allRest.length}',
        ),
        KeyedSubtree(
          key: const Key('achievement-locked-shelf'),
          child: rest.isEmpty
              ? _empty(s.text('achievements.allEarned'))
              : _grid(rest, order, narrow),
        ),
      ],
    );
  }

  Widget _searchField() => StarBridgeFieldFrame(
    builder: (_, focus) => TextField(
      key: const Key('achievement-search'),
      focusNode: focus,
      controller: _search,
      decoration: InputDecoration(
        labelText: s
            .text('achievements.search')
            .replaceAll('{count}', '${widget.catalog.length}'),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _change(() {}),
    ),
  );
  String _count(List<AchievementDefinition> items) =>
      '${widget.collection.isReady && items.every((d) => widget.collection.isConfirmed(d.id)) ? items.where((d) => p(d).earned).length : '—'} / ${items.length}';
  double? _collectionFraction(List<AchievementDefinition> items) =>
      items.isNotEmpty &&
          items.every((d) => widget.collection.isConfirmed(d.id))
      ? items.where((d) => p(d).earned).length / items.length
      : null;

  Widget _collectionProgress(double fraction, {Key? key}) =>
      LinearProgressIndicator(
        key: key,
        value: fraction,
        minHeight: 3,
        borderRadius: BorderRadius.circular(3),
        color: context.tokens.colors.accent,
        backgroundColor: context.tokens.colors.textSecondary.withValues(
          alpha: .2,
        ),
      );

  Widget _navButton(
    String id,
    String title,
    String count, {
    double? fraction,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: StarBridgeActionButton(
      kind: StarBridgeActionKind.quiet,
      controlKey: Key('achievement-group-$id'),
      onActivate: (_) => _navigate(id),
      nativeStyle: TextButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        backgroundColor: _group == id ? context.tokens.colors.accentSoft : null,
        foregroundColor: _group == id
            ? context.tokens.colors.textPrimary
            : context.tokens.colors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(title)),
              const SizedBox(width: 8),
              Text(count, style: const TextStyle(fontSize: 12)),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 8),
            // The adjacent count already describes this decorative bar to AT.
            ExcludeSemantics(
              child: _collectionProgress(
                fraction,
                key: Key('achievement-group-progress-$id'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
  Widget _navigation(bool narrow) {
    final collected = widget.catalog.where((d) => p(d).earned).toList(),
        all = groups;
    final number =
        widget.collection.isReady && widget.collection.unknownIds.isEmpty
        ? '${collected.length}'
        : '—';
    final sources = AchievementSource.values.where(
      (source) => all.values.any((g) => g.first.source == source),
    );
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchField(),
          const SizedBox(height: 12),
          StarBridgeSelectFormField<String>(
            identity: 'achievement-groups',
            controlKey: const Key('achievement-group-control'),
            key: ValueKey('achievement-group-picker-$_group'),
            initialValue: _group,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: s.text('achievements.browseGroups'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              if (v != null) _navigate(v);
            },
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(s.text('achievements.overview')),
              ),
              DropdownMenuItem(
                value: 'earned',
                child: Text('${s.text('achievements.allCollected')} · $number'),
              ),
              for (final source in sources) ...[
                DropdownMenuItem(
                  value: 'source-${source.name}',
                  enabled: false,
                  child: Text(
                    source == AchievementSource.scm
                        ? 'SCM'
                        : s.text('achievements.sourceBridge'),
                  ),
                ),
                for (final g in all.entries.where(
                  (g) => g.value.first.source == source,
                ))
                  DropdownMenuItem(
                    value: g.key,
                    child: Text(
                      '${s.text(g.value.first.groupNameKey)} · ${_count(g.value)}',
                    ),
                  ),
              ],
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField(),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            key: const Key('achievement-directory-scroll'),
            padding: EdgeInsets.zero,
            children: [
              _navButton(
                'all',
                s.text('achievements.overview'),
                _count(widget.catalog),
                fraction: _collectionFraction(widget.catalog),
              ),
              _navButton('earned', s.text('achievements.allCollected'), number),
              for (final source in sources) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                  child: Text(
                    source == AchievementSource.scm
                        ? 'SCM'
                        : s.text('achievements.sourceBridge'),
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: .66,
                      color: context.tokens.colors.textSecondary,
                    ),
                  ),
                ),
                for (final g in all.entries.where(
                  (g) => g.value.first.source == source,
                ))
                  _navButton(
                    g.key,
                    s.text(g.value.first.groupNameKey),
                    _count(g.value),
                    fraction: _collectionFraction(g.value),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupCard(List<AchievementDefinition> items) {
    final fraction = _collectionFraction(items);
    final thumbs = [
      ...recentAchievements(
        items.where((d) => p(d).earned).toList(),
        widget.collection,
      ),
      ...items.where((d) => !p(d).earned),
    ].take(4);
    return StarBridgeActionButton(
      onActivate: (_) => _navigate(groupKey(items.first)),
      nativeStyle: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                s.text(items.first.groupNameKey),
                style: TextStyle(
                  color: context.tokens.colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (items.first.source == AchievementSource.scm)
                const AchievementSourceTag(),
              Text(
                _count(items),
                style: TextStyle(
                  fontSize: 12,
                  color: context.tokens.colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in thumbs)
                AchievementArt(definition: d, earned: p(d).earned, size: 42),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 10),
            _collectionProgress(fraction),
          ],
        ],
      ),
    );
  }

  Widget _overview(bool narrow) {
    if (!widget.collection.isReady) {
      return _sections(widget.catalog.take(_limit).toList(), narrow);
    }
    final recent = recentAchievements(
      widget.catalog.where((d) => p(d).earned).toList(),
      widget.collection,
    ).take(narrow ? 2 : 6).toList();
    final ids = recent.map((d) => d.id).toSet();
    final near = widget.catalog
        .where(
          (d) =>
              !ids.contains(d.id) &&
              p(d).fraction != null &&
              p(d).fraction! > 0 &&
              p(d).fraction! < 1,
        )
        .toList();
    final catalogOrder = {
      for (var i = 0; i < widget.catalog.length; i++) widget.catalog[i].id: i,
    };
    near.sort((a, b) {
      final v = p(b).fraction!.compareTo(p(a).fraction!);
      return v != 0 ? v : catalogOrder[a.id]!.compareTo(catalogOrder[b.id]!);
    });
    final goals = near.take(narrow ? 2 : 4).toList(),
        order = [...recent, ...near.take(narrow ? 2 : 4)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          s.text('achievements.recentCollected'),
          action: StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            onActivate: (_) => _navigate('earned'),
            child: Text('${s.text('achievements.allCollected')} ›'),
          ),
        ),
        if (recent.isEmpty)
          _empty(
            s.text(
              widget.collection.unknownIds.isEmpty
                  ? 'achievements.firstCollection'
                  : 'achievements.unknownEarned',
            ),
          )
        else
          _grid(recent, order, narrow, wall: true, columns: narrow ? 2 : 6),
        if (goals.isNotEmpty) ...[
          const SizedBox(height: 34),
          _heading(
            s.text('achievements.nearTarget'),
            action: Text(
              s.text('achievements.byProgress'),
              style: TextStyle(
                fontSize: 12,
                color: context.tokens.colors.textSecondary,
              ),
            ),
          ),
          _grid(goals, order, narrow),
        ],
        const SizedBox(height: 34),
        _heading(
          s.text('achievements.exploreGroups'),
          count: s
              .text('achievements.groupCount')
              .replaceAll('{count}', '${groups.length}'),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final n = narrow ? 1 : 3, width = (c.maxWidth - 12 * (n - 1)) / n;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final g in groups.values)
                  SizedBox(width: width, child: _groupCard(g)),
              ],
            );
          },
        ),
      ],
    );
  }

  bool _matches(AchievementDefinition d) {
    final item = p(d);
    return switch (_filter) {
      'progress' => item.inProgress,
      'earned' => item.earned,
      'locked' => widget.collection.isConfirmed(d.id) && !item.earned,
      _ => true,
    };
  }

  Widget _library(bool narrow) {
    final query = _search.text.trim().toLowerCase();
    var items = widget.catalog
        .where(
          (d) =>
              query.isNotEmpty ||
              _group == 'all' ||
              (_group == 'earned' ? p(d).earned : groupKey(d) == _group),
        )
        .where(_matches)
        .where(
          (d) =>
              query.isEmpty ||
              p(d).name.toLowerCase().contains(query) ||
              (!p(d).concealed && p(d).condition.toLowerCase().contains(query)),
        )
        .toList();
    if (_recent) items = recentAchievements(items, widget.collection);
    final shown = items.take(_limit).toList(),
        mixed = query.isNotEmpty || _filter == 'progress';
    final title = query.isNotEmpty
        ? s
              .text('achievements.searchTitle')
              .replaceAll('{query}', _search.text.trim())
        : _group == 'earned'
        ? s.text('achievements.allCollected')
        : s.text(groups[_group]!.first.groupNameKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          title,
          count: s
              .text('achievements.itemCount')
              .replaceAll('{count}', '${items.length}'),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in {
                  'all': 'achievements.all',
                  'progress': 'achievements.inProgress',
                  'earned': 'achievements.earned',
                  'locked': 'achievements.locked',
                }.entries)
                  StarBridgeChoiceChip(
                    controlKey: Key('achievement-filter-${f.key}'),
                    label: s.text(f.value),
                    selected: _filter == f.key,
                    onSelected: (_) => _change(() => _filter = f.key),
                  ),
              ],
            ),
            Wrap(
              spacing: 10,
              children: [
                for (final recent in [false, true])
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: Key(
                      'achievement-sort-${recent ? 'recent' : 'catalog'}',
                    ),
                    onActivate: (_) => _change(() => _recent = recent),
                    child: Text(
                      s.text(
                        recent
                            ? 'achievements.recentOrder'
                            : 'achievements.catalogOrder',
                      ),
                      style: TextStyle(
                        color: recent == _recent
                            ? context.tokens.colors.accent
                            : context.tokens.colors.textSecondary,
                        decoration: recent == _recent
                            ? TextDecoration.underline
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (shown.isEmpty)
          _empty(s.text('achievements.noResults'))
        else if (mixed)
          _grid(shown, items, narrow)
        else
          _sections(shown, narrow, allItems: items),
        if (shown.length < items.length) ...[
          const SizedBox(height: 24),
          Center(
            child: StarBridgeActionButton(
              controlKey: const Key('achievement-show-more'),
              onActivate: (_) => setState(() => _limit += 24),
              child: Text(
                s
                    .text('achievements.showMore')
                    .replaceAll('{shown}', '${shown.length}')
                    .replaceAll('{total}', '${items.length}'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final narrow =
          c.maxWidth < 760 || MediaQuery.textScalerOf(context).scale(1) >= 1.5;
      final directory = groups.length >= 4 || widget.catalog.length > 24;
      final padding = context.tokens.density.pagePadding;
      Widget scroll(
        Widget body, {
        Widget? prefix,
        bool besideDirectory = false,
      }) => SingleChildScrollView(
        key: const Key('achievement-collection-scroll'),
        controller: widget.scrollController,
        padding: besideDirectory
            ? EdgeInsets.only(top: padding, bottom: padding)
            : EdgeInsets.all(padding),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [?prefix, body],
            ),
          ),
        ),
      );
      if (!directory) {
        return scroll(
          widget.collection.status == AchievementCollectionStatus.loading
              ? const SizedBox.shrink()
              : _sections(widget.catalog, narrow, compact: true),
          prefix: widget.header,
        );
      }
      final main = _search.text.trim().isEmpty && _group == 'all'
          ? _overview(narrow)
          : _library(narrow);
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 196 + 28 + 1160 + padding * 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
                child: widget.header,
              ),
              if (narrow)
                Padding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 0),
                  child: _navigation(true),
                ),
              Expanded(
                child: narrow
                    ? scroll(main)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              padding,
                              0,
                              0,
                              padding,
                            ),
                            child: SizedBox(
                              width: 196,
                              child: _navigation(false),
                            ),
                          ),
                          const SizedBox(width: 28),
                          Expanded(child: scroll(main, besideDirectory: true)),
                          SizedBox(width: padding),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
