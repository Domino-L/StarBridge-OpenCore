import 'package:flutter/widgets.dart';

/// Features request navigation; the shell still owns route lookup and leave guards.
class OpenDestinationIntent extends Intent {
  const OpenDestinationIntent(this.route);
  final String route;
}
