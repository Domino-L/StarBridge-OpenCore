import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_manufacturers.dart';
import 'local_hangar_port.dart';
import 'local_hangar_wall_card.dart';
import 'local_hangar_wall_sections.dart';

/// The whole hangar: the page's header, a sticky jump bar and one lazy sliver
/// per section. Off-screen cards are never built, however many ships there are.
class LocalHangarWall extends StatefulWidget {
  const LocalHangarWall({
    required this.controller,
    required this.header,
    required this.sections,
    required this.grid,
    required this.compact,
    required this.cardBuilder,
    required this.rowBuilder,
    required this.onSearch,
    super.key,
  });
  final ScrollController controller;
  final Widget header;
  final List<LocalHangarWallSection> sections;
  final bool grid, compact;
  final Widget Function(
    BuildContext context,
    LocalHangarWallSection section,
    LocalHangarShip ship,
    LocalHangarWallMetrics metrics,
  )
  cardBuilder;
  final Widget Function(BuildContext context, LocalHangarShip ship) rowBuilder;
  final VoidCallback onSearch;

  @override
  State<LocalHangarWall> createState() => _LocalHangarWallState();
}

class _LocalHangarWallState extends State<LocalHangarWall> {
  final _sectionKeys = <String, GlobalKey>{};
  final _jumpKey = GlobalKey();
  final _current = ValueNotifier<String?>(null);
  final _pinned = ValueNotifier<bool>(false);
  int _jump = 0;

  double _barHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) / 14 * 42;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_track);
    LocalHangarMakerLogos.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _track());
  }

  @override
  void didUpdateWidget(LocalHangarWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_track);
      widget.controller.addListener(_track);
    }
    final density =
        oldWidget.compact != widget.compact || oldWidget.grid != widget.grid;
    final current = _current.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A new density moves everything: stay on the section being read.
      if (density && current != null && _pinned.value) {
        _jumpTo(current);
      } else {
        _track();
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_track);
    _current.dispose();
    _pinned.dispose();
    super.dispose();
  }

  RenderSliver? _sliver(GlobalKey? key) {
    final render = key?.currentContext?.findRenderObject();
    return render is RenderSliver ? render : null;
  }

  double? _sectionOffset(String key) {
    final sliver = _sliver(_sectionKeys[key]);
    return sliver == null || !sliver.attached
        ? null
        : sliver.constraints.precedingScrollExtent - _barHeight(context);
  }

  void _track() {
    if (!mounted || !widget.controller.hasClients) return;
    final offset = widget.controller.offset;
    final bar = _sliver(_jumpKey);
    _pinned.value =
        bar != null && offset > bar.constraints.precedingScrollExtent + .5;
    String? current;
    for (final section in widget.sections) {
      final top = _sectionOffset(section.key);
      if (top == null) continue;
      if (top <= offset + 1) current = section.key;
    }
    _current.value = current ?? widget.sections.firstOrNull?.key;
  }

  /// Lazy rows are estimated until they are built, so landing can move what
  /// was estimated; re-aim until the target holds. Fixed cards hold at once.
  void _jumpTo(String key, [int attempt = 0, int? run]) {
    final ticket = run ?? ++_jump;
    if (!mounted || ticket != _jump || !widget.controller.hasClients) return;
    final target = _sectionOffset(key);
    if (target == null) return;
    final position = widget.controller.position;
    final landing = target.clamp(0.0, position.maxScrollExtent);
    if ((position.pixels - landing).abs() < .5 || attempt > 5) {
      _track();
      return;
    }
    widget.controller.jumpTo(landing);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _jumpTo(key, attempt + 1, ticket),
    );
    WidgetsBinding.instance.scheduleFrame();
  }

  void _toTop() {
    ++_jump;
    if (widget.controller.hasClients) widget.controller.jumpTo(0);
  }

  Widget _title(BuildContext context, LocalHangarWallSection section) {
    final c = LocalHangarCopy(context), t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final original = section.maker?.original(c);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          LocalHangarMakerMark(maker: section.maker, height: 26, maxWidth: 110),
          if (section.maker != null) const SizedBox(width: 8),
          Flexible(
            child: Text(
              section.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: section.favorite ? t.colors.warning : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              [?original, c.shipUnits(section.ships.length)].join('  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall?.copyWith(color: t.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.space.lg;
    final sections = widget.sections;
    return LayoutBuilder(
      builder: (context, bounds) {
        final metrics = LocalHangarWallMetrics.of(
          context,
          width: bounds.maxWidth - side * 2,
          compact: widget.compact,
        );
        return CustomScrollView(
          controller: widget.controller,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, t.space.md, side, t.space.sm),
              sliver: SliverToBoxAdapter(child: widget.header),
            ),
            if (sections.isNotEmpty)
              SliverPersistentHeader(
                key: _jumpKey,
                pinned: true,
                delegate: _JumpBarDelegate(
                  height: _barHeight(context),
                  sections: sections,
                  current: _current,
                  pinned: _pinned,
                  onJump: _jumpTo,
                  onTop: _toTop,
                  onSearch: widget.onSearch,
                ),
              ),
            for (final section in sections)
              SliverPadding(
                key: _sectionKeys[section.key] ??= GlobalKey(
                  debugLabel: section.key,
                ),
                padding: EdgeInsets.symmetric(horizontal: side),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(child: _title(context, section)),
                    if (widget.grid)
                      SliverGrid.builder(
                        itemCount: section.ships.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: metrics.columns,
                          crossAxisSpacing: metrics.gapX,
                          mainAxisSpacing: metrics.gapY,
                          mainAxisExtent: metrics.extent,
                        ),
                        itemBuilder: (context, index) => widget.cardBuilder(
                          context,
                          section,
                          section.ships[index],
                          metrics,
                        ),
                      )
                    else
                      SliverList.separated(
                        itemCount: section.ships.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            widget.rowBuilder(context, section.ships[index]),
                      ),
                  ],
                ),
              ),
            SliverPadding(padding: EdgeInsets.only(bottom: side)),
          ],
        );
      },
    );
  }
}

class _JumpBarDelegate extends SliverPersistentHeaderDelegate {
  const _JumpBarDelegate({
    required this.height,
    required this.sections,
    required this.current,
    required this.pinned,
    required this.onJump,
    required this.onTop,
    required this.onSearch,
  });
  final double height;
  final List<LocalHangarWallSection> sections;
  final ValueNotifier<String?> current;
  final ValueNotifier<bool> pinned;
  final ValueChanged<String> onJump;
  final VoidCallback onTop, onSearch;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  bool shouldRebuild(_JumpBarDelegate old) =>
      old.height != height || !identical(old.sections, sections);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      _JumpBar(delegate: this);
}

class _JumpBar extends StatelessWidget {
  const _JumpBar({required this.delegate});
  final _JumpBarDelegate delegate;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), t = context.tokens;
    final theme = Theme.of(context).textTheme;
    return Container(
      key: const Key('hangar-jump-bar'),
      height: delegate.height,
      decoration: BoxDecoration(
        color: t.surfaces.ground.fill,
        border: Border(bottom: BorderSide(color: t.surfaces.panel.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.lg),
        child: ListenableBuilder(
          listenable: Listenable.merge([delegate.current, delegate.pinned]),
          builder: (context, _) {
            final pinned = delegate.pinned.value;
            final currentKey = delegate.current.value;
            final current = delegate.sections
                .where((section) => section.key == currentKey)
                .firstOrNull;
            return Row(
              children: [
                Flexible(
                  child: Text.rich(
                    pinned && current != null
                        ? TextSpan(
                            children: [
                              TextSpan(
                                text: '${current.title} ',
                                style: theme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: c.shipUnits(current.ships.length),
                                style: theme.bodySmall?.copyWith(
                                  color: t.colors.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : TextSpan(text: c.jumpLabel, style: theme.bodySmall),
                    key: pinned && current != null
                        ? const Key('hangar-jump-current')
                        : null,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: pinned ? 14 : 8),
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final section in delegate.sections)
                          _JumpItem(
                            section: section,
                            selected: section.key == currentKey,
                            onTap: () => delegate.onJump(section.key),
                          ),
                      ],
                    ),
                  ),
                ),
                if (pinned) ...[
                  StarBridgeIconAction(
                    controlKey: const Key('hangar-jump-search'),
                    label: c.searchAction,
                    quiet: true,
                    onActivate: (_) => delegate.onSearch(),
                    icon: const StandardIcon(StandardIconSemantic.search),
                  ),
                  StarBridgeIconAction(
                    controlKey: const Key('hangar-jump-top'),
                    label: c.backToTop,
                    quiet: true,
                    onActivate: (_) => delegate.onTop(),
                    icon: const StandardIcon(StandardIconSemantic.north),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _JumpItem extends StatelessWidget {
  const _JumpItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });
  final LocalHangarWallSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens, theme = Theme.of(context).textTheme;
    return StarBridgeActionRow(
      controlKey: ValueKey('hangar-jump-${section.key}'),
      semanticLabel: '${section.title} ${section.ships.length}',
      semanticSelected: selected,
      baseRadius: t.shape.radiusSmall,
      onActivate: (_, _) => onTap(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: section.title,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? t.colors.textPrimary
                      : t.colors.textSecondary,
                ),
              ),
              TextSpan(
                text: ' ${section.ships.length}',
                style: TextStyle(color: t.colors.textDisabled),
              ),
            ],
          ),
          maxLines: 1,
          style: theme.bodySmall,
        ),
      ),
    );
  }
}
