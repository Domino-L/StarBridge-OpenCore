import 'package:flutter/widgets.dart';

/// An empty workspace route must not become a Tab stop that traps shell focus.
class ShellFocusTraversalPolicy extends OrderedTraversalPolicy {
  FocusNode _start(FocusNode node) {
    final scope = node.nearestScope;
    if (scope != null && scope.traversalDescendants.isEmpty) {
      return scope.enclosingScope ?? node;
    }
    return node;
  }

  @override
  FocusNode? findFirstFocus(
    FocusNode currentNode, {
    bool ignoreCurrentFocus = false,
  }) {
    final start = _start(currentNode);
    return super.findFirstFocus(
      start,
      ignoreCurrentFocus: start != currentNode || ignoreCurrentFocus,
    );
  }

  @override
  FocusNode findLastFocus(
    FocusNode currentNode, {
    bool ignoreCurrentFocus = false,
  }) {
    final start = _start(currentNode);
    return super.findLastFocus(
      start,
      ignoreCurrentFocus: start != currentNode || ignoreCurrentFocus,
    );
  }
}
