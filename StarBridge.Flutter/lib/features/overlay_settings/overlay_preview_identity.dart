import 'package:flutter/foundation.dart';

/// Real user identity projected into overlay previews.
///
/// Preview widgets may simulate changing presence fields, but must never invent
/// people. Identity comes from the signed-in account and personal profile.
@immutable
final class OverlayPreviewIdentity {
  const OverlayPreviewIdentity({
    required this.callSign,
    required this.gameHandle,
  });

  final String callSign;
  final String gameHandle;
}
