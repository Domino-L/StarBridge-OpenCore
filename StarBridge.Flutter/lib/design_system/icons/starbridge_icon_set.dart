import 'package:flutter/foundation.dart';

import 'icon_semantic.dart';

enum StarBridgeIconFamily { identity, profile, system }

enum StarBridgeIconSignature { none, trail, junction }

@immutable
final class StarBridgeIconGlyph {
  const StarBridgeIconGlyph({
    required this.semantic,
    required this.family,
    this.signature = StarBridgeIconSignature.none,
    this.matchTextDirection = false,
  });

  final StarBridgeIconSemantic semantic;
  final StarBridgeIconFamily family;
  final StarBridgeIconSignature signature;
  final bool matchTextDirection;
}

abstract final class StarBridgeIconSet {
  static const id = 'starbridge-outline-v1';

  static StarBridgeIconGlyph resolve(StarBridgeIconSemantic semantic) =>
      switch (semantic) {
        StarBridgeIconSemantic.home => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.home,
          family: StarBridgeIconFamily.identity,
          signature: StarBridgeIconSignature.junction,
        ),
        StarBridgeIconSemantic.room => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.room,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.operation => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.operation,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.officialFleet => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.officialFleet,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.marketplace => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.marketplace,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.community => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.community,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.hangar => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.hangar,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.overlay => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.overlay,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.tools => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.tools,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.settings => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.settings,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.friends => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.friends,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.notifications => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.notifications,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.account => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.account,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.profile => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.profile,
          family: StarBridgeIconFamily.identity,
        ),
        StarBridgeIconSemantic.edit => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.edit,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.add => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.add,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.dragHandle => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.dragHandle,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.resize => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.resize,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.remove => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.remove,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.schedule => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.schedule,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.playtime => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.playtime,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.activity => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.activity,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.publicProfile => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.publicProfile,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.generalData => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.generalData,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.privacy => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.privacy,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.reminder => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.reminder,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.diagnostics => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.diagnostics,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.legalNotice => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.legalNotice,
          family: StarBridgeIconFamily.profile,
        ),
        StarBridgeIconSemantic.login => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.login,
          family: StarBridgeIconFamily.system,
          matchTextDirection: true,
        ),
        StarBridgeIconSemantic.logout => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.logout,
          family: StarBridgeIconFamily.system,
          matchTextDirection: true,
        ),
        StarBridgeIconSemantic.refresh => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.refresh,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.undo => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.undo,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.redo => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.redo,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.save => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.save,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.cache => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.cache,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.scene => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.scene,
          family: StarBridgeIconFamily.system,
          signature: StarBridgeIconSignature.junction,
        ),
        StarBridgeIconSemantic.statusHost => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.statusHost,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.statusGame => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.statusGame,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.statusIdentity => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.statusIdentity,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.statusNetwork => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.statusNetwork,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.connected => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.connected,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.disconnected => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.disconnected,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.warning => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.warning,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.forward => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.forward,
          family: StarBridgeIconFamily.system,
          matchTextDirection: true,
        ),
        StarBridgeIconSemantic.windowMinimize => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.windowMinimize,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.windowMaximize => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.windowMaximize,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.windowRestore => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.windowRestore,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.windowClose => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.windowClose,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.pending => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.pending,
          family: StarBridgeIconFamily.system,
        ),
        StarBridgeIconSemantic.menuDown => const StarBridgeIconGlyph(
          semantic: StarBridgeIconSemantic.menuDown,
          family: StarBridgeIconFamily.system,
        ),
      };
}
