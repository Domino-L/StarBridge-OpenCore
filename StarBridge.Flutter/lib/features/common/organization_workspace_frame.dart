import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'organization_holo.dart';

/// The existing community page inset, shared without changing its directory.
class OrganizationWorkspacePage extends StatelessWidget {
  const OrganizationWorkspacePage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(20), child: child);
}

/// Organization work surface (holo restyle, user decision 2026-10-22, shared
/// by communities and the main fleet): glass panel with the bottom-right
/// corner cut, same margin and padding as the 0.7.1 card it replaces.
class OrganizationWorkspaceSurface extends StatelessWidget {
  const OrganizationWorkspaceSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final panel = context.tokens.surfaces.panel;
    // Over an organization's background art the glass lets more of it through.
    final glass = OrganizationWorkspaceBackdrop.of(context) ? .62 : .82;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: panel.fill.withValues(alpha: panel.fill.a * glass),
          shape: BeveledRectangleBorder(
            side: BorderSide(color: panel.border),
            borderRadius: const BorderRadius.only(
              bottomRight: Radius.circular(22),
            ),
          ),
        ),
        padding: const EdgeInsets.all(16),
        // Holo glass edges (2026-10-23): a top highlight in the same light as
        // the fleet deck's edge, and an accent tick on the cut corner.
        foregroundDecoration: _SurfaceEdges(
          light: context.tokens.colors.textPrimary,
          accent: context.tokens.colors.accent,
        ),
        child: OrganizationHolo(child: child),
      ),
    );
  }
}

class _SurfaceEdges extends Decoration {
  const _SurfaceEdges({required this.light, required this.accent});

  final Color light, accent;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _SurfaceEdgesPainter(light, accent);

  @override
  bool operator ==(Object other) =>
      other is _SurfaceEdges && other.light == light && other.accent == accent;

  @override
  int get hashCode => Object.hash(light, accent);
}

class _SurfaceEdgesPainter extends BoxPainter {
  _SurfaceEdgesPainter(this.light, this.accent);

  final Color light, accent;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 1),
      Paint()
        ..shader = LinearGradient(
          colors: [
            light.withValues(alpha: .45),
            light.withValues(alpha: .08),
            light.withValues(alpha: 0),
          ],
          stops: const [0, .6, 1],
        ).createShader(rect),
    );
    const cut = 22.0;
    canvas.drawLine(
      Offset(rect.right - cut, rect.bottom - .75),
      Offset(rect.right - .75, rect.bottom - cut),
      Paint()
        ..color = accent.withValues(alpha: .85)
        ..strokeWidth = 1.5,
    );
  }
}

/// Marks a workspace drawn over an organization's background art, so the
/// work surfaces below it use thinner glass. Absent means a plain ground.
class OrganizationWorkspaceBackdrop extends InheritedWidget {
  const OrganizationWorkspaceBackdrop({
    required this.active,
    required super.child,
    super.key,
  });

  final bool active;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OrganizationWorkspaceBackdrop>()
          ?.active ??
      false;

  @override
  bool updateShouldNotify(OrganizationWorkspaceBackdrop old) =>
      old.active != active;
}

/// Organization chrome only. Each caller owns membership, capabilities, reads
/// and section selection; both organization kinds share the same layout.
class OrganizationWorkspaceFrame extends StatelessWidget {
  const OrganizationWorkspaceFrame({
    required this.header,
    required this.body,
    this.navigation,
    this.actions,
    this.feedback = const [],
    super.key,
  });

  final Widget header, body;

  /// Null when the page carries the tabs elsewhere (the main fleet's bar);
  /// without tabs or actions the row and its divider are left out.
  final Widget? navigation, actions;
  final List<Widget> feedback;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      header,
      if (navigation != null || actions != null) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: navigation == null
                  ? const SizedBox.shrink()
                  : OrganizationHoloFace(child: navigation!),
            ),
            ?actions,
          ],
        ),
        const Divider(height: 24),
      ],
      ...feedback,
      Expanded(child: body),
    ],
  );
}

/// Existing community header geometry, shared without a business DTO.
class OrganizationWorkspaceHeaderLayout extends StatelessWidget {
  const OrganizationWorkspaceHeaderLayout({
    required this.expanded,
    required this.compactBuilder,
    required this.identity,
    required this.presence,
    required this.activity,
    required this.actions,
    required this.announcement,
    required this.contacts,
    super.key,
  });

  final bool expanded;
  final Widget Function(bool narrow) compactBuilder;
  final Widget identity, presence, activity, actions, announcement, contacts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, available) {
      final compact =
          !expanded &&
          (available.maxWidth < 1000 ||
              MediaQuery.sizeOf(context).height <= 800);
      return Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
            : const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.tokens.surfaces.raised.fill,
          border: Border.all(color: context.tokens.surfaces.panel.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: compact
            ? compactBuilder(available.maxWidth < 650)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1000;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(flex: 4, child: identity),
                          if (wide) ...[
                            const SizedBox(width: 24),
                            Expanded(flex: 4, child: presence),
                            const SizedBox(width: 24),
                            Expanded(flex: 3, child: activity),
                            const SizedBox(width: 16),
                          ],
                          actions,
                        ],
                      ),
                      if (!wide) ...[
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: presence),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: activity),
                          ],
                        ),
                      ],
                      const Divider(height: 24),
                      if (constraints.maxWidth >= 650)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: announcement),
                            const SizedBox(width: 24),
                            Expanded(flex: 4, child: contacts),
                          ],
                        )
                      else ...[
                        announcement,
                        const SizedBox(height: 12),
                        contacts,
                      ],
                    ],
                  );
                },
              ),
      );
    },
  );
}
