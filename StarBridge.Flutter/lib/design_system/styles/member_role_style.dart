import 'dart:ui';

/// Accept only the existing six-digit role-color contract, otherwise use theme.
Color memberRoleColor(String raw, {required Color fallback}) {
  final value = RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw)
      ? int.tryParse(raw.substring(1), radix: 16)
      : null;
  return value == null ? fallback : Color(0xff000000 | value);
}
