/// One callsign for SCM accounts (11-15 decision 甲), with the same rules as legacy
/// accounts: trim, blank clears, CJK characters count 2, at most 10.
///
/// Counting is per UTF-16 code unit, exactly like the Relay (`GetCallsignWeight`)
/// and the Host, so an emoji (two code units) counts 2 everywhere.
abstract final class CallsignRules {
  static const maxWeight = 10;

  static int weight(String value) => value.codeUnits.fold(
    0,
    (sum, unit) =>
        sum +
        ((unit >= 0x4E00 && unit <= 0x9FFF) ||
                (unit >= 0x3400 && unit <= 0x4DBF) ||
                (unit >= 0xF900 && unit <= 0xFAFF)
            ? 2
            : 1),
  );

  /// Same control characters as .NET `char.IsControl`: C0, DEL and C1.
  static bool _control(int unit) =>
      unit < 0x20 || (unit >= 0x7F && unit < 0xA0);

  /// True when [value] (after trimming) is empty or a valid callsign.
  static bool valid(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ||
        (weight(trimmed) <= maxWeight && !trimmed.codeUnits.any(_control));
  }
}
