import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show Brightness;

/// Notification-center category colors (0.7.2, approved preview
/// notify-badge-preview "通知中心配色"). Color is never the only cue: every
/// item also shows the category icon and name. Light theme uses a deeper
/// shade of the same hue for contrast.
abstract final class NotificationCategoryPalette {
  static const _dark = <String, Color>{
    'trade': Color(0xFFF5B544),
    'tradeChat': Color(0xFF36C9C6),
    'social': Color(0xFF4CB2F5),
    'fleet': Color(0xFFA78BFA),
    'room': Color(0xFF3ED59A),
    'system': Color(0xFF93A4AE),
    'safety': Color(0xFFF26D75),
  };
  static const _light = <String, Color>{
    'trade': Color(0xFF9A6200),
    'tradeChat': Color(0xFF0F7F7D),
    'social': Color(0xFF1B6FAD),
    'fleet': Color(0xFF6A4BC4),
    'room': Color(0xFF178256),
    'system': Color(0xFF55646D),
    'safety': Color(0xFFB8303C),
  };

  static Color of(String category, Brightness brightness) =>
      (brightness == Brightness.light ? _light : _dark)[category] ??
      (brightness == Brightness.light ? _light : _dark)['system']!;
}
