/// QualityPass ③ (user 2026-10-29): line-break helpers for Chinese text.
///
/// Flutter has no `text-wrap: pretty`, so these work on the string:
/// * [keepLastTwo] glues the last two CJK characters (plus any closing
///   punctuation) with a word joiner, so a paragraph never ends on a line
///   holding a single character — the previous line gives one up instead.
/// * [metaLine] keeps each short segment whole and lets the line break only
///   at the " · " separators, so "UTC-06:00" never drops to a line alone.
library;

const _wordJoiner = '⁠';
const _noBreakSpace = ' ';

bool _cjk(int rune) =>
    (rune >= 0x3400 && rune <= 0x9FFF) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0x20000 && rune <= 0x2FA1F);

bool _closing(int rune) => '，。！？；：、）》」』”’…—'.runes.contains(rune);

String keepLastTwo(String text) {
  final runes = text.trimRight().runes.toList();
  final trailing = text.substring(String.fromCharCodes(runes).length);
  var end = runes.length;
  while (end > 0 && _closing(runes[end - 1])) {
    end--;
  }
  // Need two CJK characters before the closing punctuation to glue.
  if (end < 2 || !_cjk(runes[end - 1]) || !_cjk(runes[end - 2])) return text;
  final out = StringBuffer()
    ..write(String.fromCharCodes(runes.sublist(0, end - 1)))
    ..write(_wordJoiner)
    ..write(String.fromCharCode(runes[end - 1]));
  for (var i = end; i < runes.length; i++) {
    out
      ..write(_wordJoiner)
      ..write(String.fromCharCode(runes[i]));
  }
  out.write(trailing);
  return out.toString();
}

String metaLine(Iterable<String> parts) => parts
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .map(
      (part) => part
          .replaceAll(' ', _noBreakSpace)
          // Keep "08:00-22:00" and "UTC-06:00" in one piece.
          .replaceAll('-', '‑'),
    )
    .join(' · ');
