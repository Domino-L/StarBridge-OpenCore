enum ShellLayoutMode { wide, compact, iconOnly }

abstract final class ShellLayoutResolver {
  static const double wideMinimumWidth = 1260;
  static const double compactMinimumWidth = 1040;

  static ShellLayoutMode resolve(double width) {
    if (width >= wideMinimumWidth) {
      return ShellLayoutMode.wide;
    }
    if (width >= compactMinimumWidth) {
      return ShellLayoutMode.compact;
    }
    return ShellLayoutMode.iconOnly;
  }
}
