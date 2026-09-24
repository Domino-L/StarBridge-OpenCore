import '../../design_system/styles/home_scene_palette.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../app/shell/chrome/presence_label.dart';
import '../../app/shell/chrome/shell_chrome_port.dart';
import '../../app/shell/chrome/shell_chrome_projection.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../party_rooms/party_rooms_module.dart';
import 'home_scene_video.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.chrome,
    required this.rooms,
    this.scene,
    this.now,
    super.key,
  });

  final ShellChromePort chrome;
  final PartyRoomsModule rooms;
  final Widget? scene;
  final DateTime? now;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<ShellChromeProjection>(
      valueListenable: widget.chrome.projection,
      builder: (context, chrome, _) {
        final now = widget.now ?? DateTime.now();
        return LayoutBuilder(
          builder: (context, constraints) {
            // Follow the visible viewport, not a capped width-derived banner.
            // Short windows can scroll so the greeting stays readable.
            final availableHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height;
            final heroHeight = (availableHeight * .62).clamp(
              250.0,
              double.infinity,
            );
            return SingleChildScrollView(
              key: const Key('home-page-scroll'),
              child: Column(
                children: [
                  SizedBox(
                    key: const Key('home-hero'),
                    height: heroHeight,
                    child: _Hero(
                      chrome: chrome,
                      now: now,
                      scene: widget.scene ?? const HomeSceneVideo(),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      tokens.density.pagePadding,
                      tokens.space.md,
                      tokens.density.pagePadding,
                      tokens.density.pagePadding,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 160,
                      child: Center(
                        child: Text(
                          AppStrings.of(context).text('home.moreInDevelopment'),
                          key: const Key('home-more-in-development'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: tokens.colors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.chrome, required this.now, required this.scene});

  final ShellChromeProjection chrome;
  final DateTime now;
  final Widget scene;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final account = chrome.accountSignedIn ? chrome.accountLabel.trim() : '';
    final greeting = strings.text(_greetingKey(now.hour));
    final title = strings.text(_titleKey(account, now));
    final presenceKey = chrome.displayPresenceKey;
    final presence = displayPresenceLabel(strings, chrome);
    final statusColor = presenceColor(tokens.colors, presenceKey);
    return Stack(
      fit: StackFit.expand,
      children: [
        scene,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [HomeScenePalette.scrimStrong, HomeScenePalette.scrimSoft, HomeScenePalette.scrimClear],
              stops: [0, .46, .78],
            ),
          ),
        ),
        DecoratedBox(
          key: const Key('home-hero-bottom-fade'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                tokens.surfaces.ground.fill.withValues(alpha: .12),
                tokens.surfaces.ground.fill,
              ],
              stops: const [.52, .78, 1],
            ),
          ),
        ),
        Positioned(
          left: tokens.density.pagePadding * 1.35,
          right: tokens.density.pagePadding,
          bottom: tokens.space.xl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Localizations.localeOf(context).languageCode == 'en'
                    ? '$greeting, ${account.isEmpty ? title : '$account · $title'}'
                    : '$greeting，${account.isEmpty ? title : '$account $title'}',
                key: const Key('home-greeting'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: tokens.typography.display,
                  fontWeight: tokens.typography.displayWeight,
                  letterSpacing: tokens.typography.displayTracking,
                  shadows: const [
                    Shadow(color: HomeScenePalette.textShadow, blurRadius: 16),
                  ],
                ),
              ),
              SizedBox(height: tokens.space.xs),
              Wrap(
                spacing: tokens.space.sm,
                runSpacing: tokens.space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _HeroMeta(
                    child: Container(
                      width: tokens.icons.statusDot,
                      height: tokens.icons.statusDot,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: .32),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _HeroMeta(text: presence),
                  const _HeroDivider(),
                  _HeroMeta(text: strings.text('home.scene.location')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({this.text, this.child});
  final String? text;
  final Widget? child;
  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: TextStyle(
      color: Colors.white.withValues(alpha: .84),
      fontSize: context.tokens.typography.body,
      fontWeight: context.tokens.typography.bodyWeight,
      shadows: const [Shadow(color: HomeScenePalette.textShadow, blurRadius: 8)],
    ),
    child: child ?? Text(text!),
  );
}

class _HeroDivider extends StatelessWidget {
  const _HeroDivider();
  @override
  Widget build(BuildContext context) => Container(
    width: context.tokens.stroke.regular,
    height: 14,
    color: Colors.white.withValues(alpha: .38),
  );
}

String _greetingKey(int hour) {
  if (hour < 11) return 'home.greeting.morning';
  if (hour < 14) return 'home.greeting.noon';
  if (hour < 18) return 'home.greeting.afternoon';
  return 'home.greeting.evening';
}

String _titleKey(String account, DateTime now) {
  const keys = [
    'home.title.captain',
    'home.title.navigator',
    'home.title.pathfinder',
    'home.title.voyager',
  ];
  return keys[_dailySeed(account, now) % keys.length];
}

int _dailySeed(String value, DateTime now) {
  var hash = now.year * 10000 + now.month * 100 + now.day;
  for (final unit in value.codeUnits) {
    hash = ((hash * 31) ^ unit) & 0x7fffffff;
  }
  return hash;
}
