import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/brand/brand_lockup.dart';
import '../../design_system/brand/brand_lockup_spec.dart';
import '../../design_system/styles/update_poster_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'application_update_announcement.dart';
import 'application_update_panel.dart';

// 更新说明不能带图：旧客户端显示新版本的消息，图只能用客户端里已有的。
const _posterAsset = 'assets/home-scenes/lorville-skyline-poster-v1.jpg';
const _posterFallbackAsset = 'assets/brand/default_banner_dark.png';
const _highlightArt = <String, String>{
  '主舰队': 'assets/achievements/collection-earned.png',
  '交易大厅': 'assets/brand/scm_market_crate.png',
  '社区组织': 'assets/achievements/paths-earned.png',
  '城市成就': 'assets/achievements/journey-stanton-earned-512.webp',
};
const _containedArt = {'assets/brand/scm_market_crate.png'};

const posterMaxWidth = 880.0;
const _footerStacksBelow = 640.0;
const _gutter = 24.0;

/// 版本海报：实景主图、标题、亮点卡片，底部一条放状态和按钮。
///
/// 下载时图和亮点不动，变的只有底部。这里不碰更新流程，流程还在对话框的 State 里。
class ApplicationUpdatePoster extends StatefulWidget {
  const ApplicationUpdatePoster({
    required this.announcement,
    required this.version,
    required this.testVersionLabel,
    required this.status,
    required this.actions,
    this.warning = false,
    this.showFullNotes = false,
    this.hero,
    super.key,
  });

  final UpdateAnnouncement announcement;
  final String? version;
  final String testVersionLabel;
  final Widget status;
  final List<Widget> actions;

  /// 失败时底部换成提醒色。主色可能是节日金，这里不用红色。
  final bool warning;
  final bool showFullNotes;

  /// 这一版从更新服务器读到、校验过的主图；没有就用客户端自带的。
  final Uint8List? hero;

  @override
  State<ApplicationUpdatePoster> createState() =>
      _ApplicationUpdatePosterState();
}

class _ApplicationUpdatePosterState extends State<ApplicationUpdatePoster> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final notes = widget.announcement.fullNotes;
    return Dialog(
      insetPadding: const EdgeInsets.all(_gutter),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: posterMaxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PosterHero(
                        announcement: widget.announcement,
                        version: widget.version,
                        testVersionLabel: widget.testVersionLabel,
                        hero: widget.hero,
                        // 窗口矮时先压图，文字和按钮不动；展开长文时只留一条。
                        height: widget.showFullNotes
                            ? 112
                            : (screen.height - 372).clamp(150.0, 340.0),
                      ),
                      if (widget.showFullNotes && notes != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            _gutter,
                            0,
                            _gutter,
                            _gutter,
                          ),
                          child: UpdateReleaseNotes(notes),
                        )
                      else
                        _HighlightCards(
                          highlights: widget.announcement.highlights,
                          artHeight: screen.height < 700 ? 62 : 92,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _PosterFooter(
              status: widget.status,
              actions: widget.actions,
              warning: widget.warning,
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterHero extends StatelessWidget {
  const _PosterHero({
    required this.announcement,
    required this.version,
    required this.testVersionLabel,
    required this.height,
    this.hero,
  });

  final UpdateAnnouncement announcement;
  final String? version;
  final String testVersionLabel;
  final double height;
  final Uint8List? hero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = MediaQuery.devicePixelRatioOf(context);
    final compact = height < 180;
    final subline = announcement.subline ?? '';
    // 图一直是深的，浅色主题下这里的文字和标志也按深底来。
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(brightness: Brightness.dark),
      ),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                _posterAsset,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -.16),
                cacheWidth: (posterMaxWidth * device).round(),
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => Image.asset(
                  _posterFallbackAsset,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: UpdatePosterPalette.imageFallback,
                  ),
                ),
              ),
            ),
            if (hero case final bytes?)
              Positioned.fill(
                child: Image.memory(
                  bytes,
                  key: const Key('update-hero-image'),
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -.16),
                  cacheWidth: (posterMaxWidth * device).round(),
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .26, .42, 1],
                    colors: [
                      UpdatePosterPalette.scrimTop,
                      UpdatePosterPalette.scrimClear,
                      UpdatePosterPalette.scrimClear,
                      UpdatePosterPalette.scrimBottom,
                    ],
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: IntrinsicHeight(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    _gutter - 8,
                    compact ? 6 : 12,
                    _gutter,
                    compact ? 10 : 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: [
                          const BrandLockup(
                            scale: BrandLockupScale.navigationExpanded,
                          ),
                          _VersionChip(
                            version: version,
                            label: announcement.isTestVersion
                                ? testVersionLabel
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                announcement.headline,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  color: UpdatePosterPalette.headline,
                                  fontSize: compact ? 28 : 40,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            if (subline.isNotEmpty && !compact) ...[
                              const SizedBox(height: 6),
                              Text(
                                subline,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: UpdatePosterPalette.subline,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.version, required this.label});

  final String? version;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: UpdatePosterPalette.chipText);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UpdatePosterPalette.chipFill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (version case final value?)
              Text(
                value,
                key: const Key('update-announcement-version'),
                style: style?.copyWith(fontWeight: FontWeight.w700),
              ),
            if (label case final value?) ...[
              const SizedBox(width: 6),
              Text(value, style: style),
            ],
          ],
        ),
      ),
    );
  }
}

class _HighlightCards extends StatelessWidget {
  const _HighlightCards({required this.highlights, required this.artHeight});

  final List<UpdateHighlight> highlights;
  final double artHeight;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 16, _gutter, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final card = [
            for (final item in highlights)
              _HighlightCard(highlight: item, artHeight: artHeight),
          ];
          if (width >= 640) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < card.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Expanded(child: card[i]),
                  ],
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < card.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                card[i],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.highlight, required this.artHeight});

  final UpdateHighlight highlight;
  final double artHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final art = _highlightArt[highlight.label];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 不认识的亮点名字没有图，只留文字。公开构建没有这些图时也一样。
            if (art != null) _HighlightArt(asset: art, height: artHeight),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    highlight.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    highlight.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightArt extends StatelessWidget {
  const _HighlightArt({required this.asset, required this.height});

  final String asset;
  final double height;

  @override
  Widget build(BuildContext context) {
    final contained = _containedArt.contains(asset);
    final device = MediaQuery.devicePixelRatioOf(context);
    final image = Image.asset(
      asset,
      // 带底色的图上下各留 4，总高和其他卡片一样，文字才对得齐。
      height: contained ? height - 8 : height,
      fit: contained ? BoxFit.contain : BoxFit.cover,
      cacheHeight: contained ? ((height - 8) * device).round() : null,
      cacheWidth: contained ? null : (240 * device).round(),
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    return contained
        ? ColoredBox(
            color: Theme.of(context).brightness == Brightness.dark
                ? UpdatePosterPalette.tradeArtDark
                : UpdatePosterPalette.tradeArtLight,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: image,
            ),
          )
        : image;
  }
}

class _PosterFooter extends StatelessWidget {
  const _PosterFooter({
    required this.status,
    required this.actions,
    required this.warning,
  });

  final Widget status;
  final List<Widget> actions;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final buttons = Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: actions,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning
            ? Theme.of(context)
                  .extension<StarBridgeTokens>()
                  ?.colors
                  .warningSoft
            : null,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 字放大时状态自己滚动，按钮一直看得见。
            final text = ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 132),
              child: SingleChildScrollView(child: status),
            );
            if (constraints.maxWidth < _footerStacksBelow) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [text, const SizedBox(height: 10), buttons],
              );
            }
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                buttons,
              ],
            );
          },
        ),
      ),
    );
  }
}
