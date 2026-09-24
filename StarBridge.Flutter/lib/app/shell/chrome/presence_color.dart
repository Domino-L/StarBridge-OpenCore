import 'package:flutter/material.dart';

import '../../../design_system/tokens/color_tokens.dart';

/// One palette for the compact account, expanded menu and owner profile.
/// Connection/identity errors override this at their existing issue boundary.
Color presenceColor(ColorTokens colors, String presenceKey) =>
    switch (presenceKey) {
      'presence.online' => colors.info,
      'presence.inGame' => colors.success,
      'presence.away' => colors.warning,
      'presence.offline' || 'presence.notInGame' => colors.offline,
      _ => colors.warning,
    };
