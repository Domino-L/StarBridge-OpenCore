import 'package:flutter/material.dart';

import '../common/organization_holo_art.dart';
import '../common/organization_workspace_frame.dart';

/// The organization's RSI page background behind the whole main fleet page
/// (user decision 2026-10-23, option A): dimmed and vignetted under the
/// banner, the command row, the tiles and the lower screen's glass panels.
/// Without a background (or while it fails to load) the page keeps its plain
/// ground; the child is never wrapped differently, so its state is kept.
class OfficialFleetBackdrop extends StatelessWidget {
  const OfficialFleetBackdrop({
    required this.art,
    required this.child,
    super.key,
  });

  final OrganizationHoloArt? art;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ground = Theme.of(context).scaffoldBackgroundColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        if (art != null)
          Positioned.fill(
            key: const Key('official-fleet-backdrop'),
            // Static page art: painted once, never with the content above.
            child: RepaintBoundary(
              child: ExcludeSemantics(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    art!.image(
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                    // Dim to ~38% (dark) or wash out (light), then darken the
                    // edges and the lower half where the text sits.
                    ColoredBox(
                      color: ground.withValues(alpha: dark ? .62 : .80),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -.4),
                          radius: 1.1,
                          colors: [
                            ground.withValues(alpha: 0),
                            ground.withValues(alpha: .75),
                          ],
                          stops: const [.3, 1],
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            ground.withValues(alpha: .2),
                            ground.withValues(alpha: .65),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned.fill(
          key: const Key('official-fleet-backdrop-content'),
          child: OrganizationWorkspaceBackdrop(
            active: art != null,
            child: child,
          ),
        ),
      ],
    );
  }
}
