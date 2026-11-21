import 'package:flutter/material.dart';

/// Fixed accents of the Steam-style personal profile (accepted preview
/// ProfileSteam, 2026-11-02): the gold main role and the green SCM reputation
/// read the same on every wallpaper and theme.
abstract final class ProfileShowcasePalette {
  static const gold = Color(0xFFF1B24A);
  static const goldOnLight = Color(0xFFA86A00);
  static const reputation = Color(0xFF62D69F);
  static const reputationOnLight = Color(0xFF1E8A57);
  static const online = Color(0xFF62D69F);
  static const timeBar = Color(0xFF5CC0FF);

  static Color mainRole(Brightness brightness) =>
      brightness == Brightness.dark ? gold : goldOnLight;

  static Color reputationFor(Brightness brightness) =>
      brightness == Brightness.dark ? reputation : reputationOnLight;
}
