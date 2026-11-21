import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/styles/hangar_wall_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_image_cache.dart';
import 'local_hangar_images.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_ship_accent.dart';
import 'local_hangar_stage_fill.dart';
import 'local_hangar_stage_parts.dart';
import 'local_hangar_stage_switch.dart';
import 'local_hangar_wall_card.dart';
import 'local_hangar_wall_sections.dart';

/// One ship at full size over the wall, which stays mounted beneath it, so that
/// going back lands where the wall was left. The strip below changes the ship.
/// All detail and its future modification view stay behind 查看详情.
class LocalHangarStage extends StatefulWidget {
  const LocalHangarStage({
    required this.sections,
    required this.shipId,
    required this.former,
    required this.peers,
    required this.imageFor,
    required this.imageCache,
    required this.cacheKey,
    required this.onSelect,
    required this.onBack,
    required this.onDetails,
    this.onFavorite,
    this.favoritesAvailable = false,
    this.favoriteBusy = false,
    this.favoriteFailed = false,
    super.key,
  });
  final List<LocalHangarWallSection> sections;
  final String shipId;
  final bool former;
  final List<LocalHangarShip> Function(LocalHangarShip) peers;
  final LocalHangarImagePort? Function(LocalHangarShip) imageFor;
  final LocalHangarImageCache imageCache;
  final String Function(LocalHangarShip) cacheKey;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;
  final ValueChanged<LocalHangarShip> onDetails;
  final ValueChanged<LocalHangarShip>? onFavorite;
  final bool favoritesAvailable, favoriteBusy, favoriteFailed;

  @override
  State<LocalHangarStage> createState() => _LocalHangarStageState();
}

class _LocalHangarStageState extends State<LocalHangarStage> {
  static const _thumbWidth = 176.0, _thumbGap = 10.0;
  final _strip = ScrollController();
  final _focus = FocusNode(debugLabel: 'hangar-stage');
  final _detailsFocus = FocusNode(debugLabel: 'hangar-stage-details');
  Color? _accent;
  String? _accentFor;
  int _direction = 1;
  int? _stepped;

  List<LocalHangarShip> get _ships => [
    for (final section in widget.sections) ...section.ships,
  ];

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
  }

  @override
  void didUpdateWidget(LocalHangarStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shipId != widget.shipId) {
      final ships = _ships;
      final from = ships.indexWhere((s) => s.id == oldWidget.shipId);
      final to = ships.indexWhere((s) => s.id == widget.shipId);
      if (from >= 0 && to >= 0 && _stepped == null) {
        _direction = to >= from ? 1 : -1;
      }
      _stepped = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _strip.dispose();
    _focus.dispose();
    _detailsFocus.dispose();
    super.dispose();
  }

  /// Keeps the current ship in view on the strip, a little in from the left.
  void _reveal({bool jump = false}) {
    if (!mounted || !_strip.hasClients) return;
    final index = _ships.indexWhere((ship) => ship.id == widget.shipId);
    if (index < 0) return;
    final target = ((index - 3) * (_thumbWidth + _thumbGap)).clamp(
      0.0,
      _strip.position.maxScrollExtent,
    );
    if (jump || MediaQuery.disableAnimationsOf(context)) {
      _strip.jumpTo(target);
    } else {
      unawaited(
        _strip.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _step(int delta) {
    final ships = _ships;
    if (ships.length < 2) return;
    final index = ships.indexWhere((ship) => ship.id == widget.shipId);
    // Wrapping round the ends still moves the way the key points.
    _direction = _stepped = delta.sign;
    widget.onSelect(ships[(index + delta) % ships.length].id);
  }

  /// The ships either side get their line color and picture shape read now,
  /// so stepping to one changes everything in the same frame.
  void _prepareNeighbors(List<LocalHangarShip> ships, int index) {
    for (final delta in const [-1, 1]) {
      final next = LocalHangarPresentation.fromSaved(
        ships[(index + delta) % ships.length],
      );
      final asset = next.bundledImage;
      if (asset == null) continue;
      LocalHangarStageFill.prepare(asset);
      if (LocalHangarShipAccent.known(asset) == null) {
        unawaited(LocalHangarShipAccent.read(asset));
      }
    }
  }

  void _readAccent(LocalHangarPresentation item) {
    final asset = item.bundledImage;
    if (asset == null || asset == _accentFor) return;
    _accentFor = asset;
    _accent = LocalHangarShipAccent.known(asset);
    unawaited(
      LocalHangarShipAccent.read(asset).then((color) {
        if (mounted && _accentFor == asset && _accent != color) {
          setState(() => _accent = color);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ships = _ships;
    final ship = ships.where((s) => s.id == widget.shipId).firstOrNull;
    if (ship == null) return const SizedBox.shrink();
    final section = widget.sections.firstWhere((s) => s.ships.contains(ship));
    final item = LocalHangarPresentation.fromSaved(ship);
    _readAccent(item);
    if (ships.length > 1) _prepareNeighbors(ships, ships.indexOf(ship));
    final palette = HangarWallPalette.of(context), t = context.tokens;
    final c = LocalHangarCopy(context);
    final line = palette.line(_accent ?? t.colors.accent);
    return Semantics(
      key: const Key('hangar-stage'),
      container: true,
      explicitChildNodes: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onBack,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        },
        child: Focus(
          focusNode: _focus,
          child: ColoredBox(
            color: palette.stageGround,
            child: LayoutBuilder(
              builder: (context, bounds) {
                final scaler = MediaQuery.textScalerOf(context);
                final narrow = bounds.maxWidth < 900 || bounds.maxHeight < 640;
                final stripHeight =
                    _thumbWidth * localHangarArtAspect +
                    10 +
                    scaler.scale(13.5) * 1.3 +
                    scaler.scale(11.5) * 1.3 +
                    t.space.md +
                    t.space.sm;
                final info = (narrow ? 112.0 : 168.0) * scaler.scale(14) / 14;
                final imageHeight = math.max(
                  120.0,
                  bounds.maxHeight - stripHeight - info,
                );
                final stage = Stack(
                  fit: StackFit.expand,
                  children: [
                    LocalHangarStageSwitch(
                      shipId: ship.id,
                      direction: _direction,
                      child: _StageArt(
                        item: item,
                        imageHeight: imageHeight,
                        bottom: stripHeight,
                        line: line,
                        imagePort: widget.imageFor(ship),
                        cache: widget.imageCache,
                        cacheKey: widget.cacheKey(ship),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LocalHangarStageTopBar(
                          ship: ship,
                          position: c.stagePosition(
                            section.title,
                            section.ships.indexOf(ship) + 1,
                            section.ships.length,
                          ),
                          onBack: widget.onBack,
                          onFavorite: widget.onFavorite,
                          favoritesAvailable: widget.favoritesAvailable,
                          favoriteBusy: widget.favoriteBusy,
                          favoriteFailed: widget.favoriteFailed,
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              LocalHangarStageArrow(
                                controlKey: const Key('hangar-stage-previous'),
                                label: c.previousShip,
                                back: true,
                                onTap: ships.length < 2
                                    ? null
                                    : () => _step(-1),
                              ),
                              const Spacer(),
                              LocalHangarStageArrow(
                                controlKey: const Key('hangar-stage-next'),
                                label: c.nextShip,
                                back: false,
                                onTap: ships.length < 2 ? null : () => _step(1),
                              ),
                            ],
                          ),
                        ),
                        LocalHangarStageFacts(
                          item: item,
                          former: widget.former,
                          peers: widget.peers(ship),
                          narrow: narrow,
                          detailsFocus: _detailsFocus,
                          // Closing details comes back to the button, whatever
                          // opened them; the stage's keys keep working from it.
                          onDetails: () {
                            _detailsFocus.requestFocus();
                            widget.onDetails(ship);
                          },
                        ),
                        SizedBox(
                          height: stripHeight,
                          child: ListView.builder(
                            controller: _strip,
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.fromLTRB(
                              t.space.lg,
                              t.space.md,
                              t.space.lg,
                              t.space.sm,
                            ),
                            itemExtent: _thumbWidth + _thumbGap,
                            itemCount: ships.length,
                            itemBuilder: (context, index) =>
                                LocalHangarStageThumb(
                                  key: ValueKey(
                                    'hangar-stage-thumb-${ships[index].id}',
                                  ),
                                  item: LocalHangarPresentation.fromSaved(
                                    ships[index],
                                  ),
                                  width: _thumbWidth,
                                  selected: ships[index].id == widget.shipId,
                                  line: line,
                                  imagePort: widget.imageFor(ships[index]),
                                  cache: widget.imageCache,
                                  cacheKey: widget.cacheKey(ships[index]),
                                  onTap: () => widget.onSelect(ships[index].id),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
                final least = stripHeight + info * 1.8 + 160;
                if (bounds.maxHeight >= least &&
                    bounds.maxWidth >= 760 * scaler.scale(14) / 14) {
                  return stage;
                }
                // A very short or narrow window at large text scrolls instead
                // of cutting the facts off.
                return SingleChildScrollView(
                  child: SizedBox(
                    height: math.max(bounds.maxHeight, least + 120),
                    child: stage,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Artwork, its faint reflection and the table lines. No blur or layer: the
/// reflection is a small decode drawn large, the fade is one flat gradient.
class _StageArt extends StatelessWidget {
  const _StageArt({
    required this.item,
    required this.imageHeight,
    required this.bottom,
    required this.line,
    required this.imagePort,
    required this.cache,
    required this.cacheKey,
  });
  final LocalHangarPresentation item;
  final double imageHeight, bottom;
  final Color line;
  final LocalHangarImagePort? imagePort;
  final LocalHangarImageCache cache;
  final String cacheKey;

  @override
  Widget build(BuildContext context) {
    final palette = HangarWallPalette.of(context);
    final ground = palette.stageGround;
    final asset = item.bundledImage;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final width = bounds.maxWidth, height = bounds.maxHeight;
          final fade = imageHeight + (height - imageHeight - bottom) * .5;
          return Stack(
            children: [
              // The whole picture, never cropped. Whatever it leaves empty shows
              // its own colors from a tiny decode drawn large; nothing blurs live.
              if (asset != null)
                Positioned.fill(
                  child: ImageFiltered(
                    // Drawn once per ship: smooths the tiny decode's steps.
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: LocalHangarStageFill.backdropBlur,
                      sigmaY: LocalHangarStageFill.backdropBlur,
                      tileMode: TileMode.clamp,
                    ),
                    child: Image.asset(
                      asset,
                      key: ValueKey('backdrop:$asset'),
                      fit: BoxFit.cover,
                      cacheWidth: 48,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      opacity: AlwaysStoppedAnimation(
                        palette.isDark
                            ? LocalHangarStageFill.backdropDark
                            : LocalHangarStageFill.backdropLight,
                      ),
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: imageHeight,
                child: RepaintBoundary(
                  child: LocalHangarStageFill(
                    item: item,
                    width: width,
                    height: imageHeight,
                    placeholder: Center(
                      child: LocalHangarWallIcon(
                        item: item,
                        size: math.min(160, imageHeight * .6),
                      ),
                    ),
                    imagePort: imagePort,
                    cache: cache,
                    cacheKey: cacheKey,
                  ),
                ),
              ),
              // Words at the top stay light, so their scrim is dark in both.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: imageHeight * .22,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        HangarWallPalette.artScrim,
                        HangarWallPalette.artScrimClear,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: imageHeight * .66,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [
                        0,
                        (imageHeight * .34 / (height - imageHeight * .66))
                            .clamp(0, 1),
                        ((fade - imageHeight * .66) /
                                (height - imageHeight * .66))
                            .clamp(0, 1),
                      ],
                      colors: [
                        ground.withValues(alpha: 0),
                        ground.withValues(alpha: palette.artEdgeFade),
                        ground,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: imageHeight,
                bottom: bottom,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _GroundLines(
                      color: line.withValues(alpha: palette.lineStrength),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Lines of a table seen in perspective, in the ship's own color.
class _GroundLines extends CustomPainter {
  const _GroundLines({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = .6;
    final centre = size.width / 2;
    final spread = size.width * 1.2;
    for (var i = 0; i <= 14; i++) {
      canvas.drawLine(
        Offset(centre, 0),
        Offset(centre - spread / 2 + spread * i / 14, size.height),
        paint,
      );
    }
    for (var i = 0; i < 6; i++) {
      final y = size.height * math.pow(i / 5, 2).toDouble();
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GroundLines oldDelegate) => oldDelegate.color != color;
}
