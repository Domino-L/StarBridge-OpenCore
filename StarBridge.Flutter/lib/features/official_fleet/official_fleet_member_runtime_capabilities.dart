import 'package:flutter/foundation.dart';

/// Declared by a directory adapter for the entire list, never inferred from rows.
@immutable
final class OfficialFleetMemberRuntimeCapabilities {
  const OfficialFleetMemberRuntimeCapabilities({
    this.presence = false,
    this.server = false,
    this.ship = false,
    this.location = false,
    this.onlineCount = false,
    this.inGameCount = false,
  });

  const OfficialFleetMemberRuntimeCapabilities.none() : this();

  const OfficialFleetMemberRuntimeCapabilities.all()
    : this(
        presence: true,
        server: true,
        ship: true,
        location: true,
        onlineCount: true,
        inGameCount: true,
      );

  final bool presence;
  final bool server;
  final bool ship;
  final bool location;
  final bool onlineCount;
  final bool inGameCount;
}
