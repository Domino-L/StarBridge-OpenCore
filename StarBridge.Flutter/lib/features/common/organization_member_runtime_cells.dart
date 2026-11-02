/// Display-only runtime content. A placeholder remains distinct from a real
/// value without deriving its style from translated text.
final class MemberRuntimeCell {
  const MemberRuntimeCell.value(this.text) : isPlaceholder = false;
  const MemberRuntimeCell.placeholder(this.text) : isPlaceholder = true;

  final String text;
  final bool isPlaceholder;
}

final class MemberRuntimeCells {
  const MemberRuntimeCells({
    required this.server,
    required this.ship,
    required this.location,
  });

  const MemberRuntimeCells.empty()
    : server = const MemberRuntimeCell.placeholder(''),
      ship = const MemberRuntimeCell.placeholder(''),
      location = const MemberRuntimeCell.placeholder('');

  final MemberRuntimeCell server, ship, location;
}
