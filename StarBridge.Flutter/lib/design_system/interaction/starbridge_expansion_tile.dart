import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_interaction_theme.dart';

/// Keeps the existing local disclosure/PageStorage owner. Only header feedback
/// and the body reveal are delegated to the approved suite; no business writes.
class StarBridgeExpansionTile extends StatefulWidget {
  const StarBridgeExpansionTile({
    required this.title,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.childrenPadding = EdgeInsets.zero,
    this.headerPadding = EdgeInsets.zero,
    this.titleStyle,
    this.onExpansionChanged,
    this.headerBuilder,
    this.headerMinHeight = 56,
    this.childrenCrossAxisAlignment = CrossAxisAlignment.stretch,
    this.useNativePageStorage = false,
    super.key,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool initiallyExpanded, maintainState;
  final EdgeInsetsGeometry childrenPadding;
  final EdgeInsetsGeometry headerPadding;
  final TextStyle? titleStyle;
  final ValueChanged<bool>? onExpansionChanged;
  final Widget Function(
    BuildContext context,
    PressableVisual visual,
    double open,
  )?
  headerBuilder;
  final double headerMinHeight;
  final CrossAxisAlignment childrenCrossAxisAlignment;

  /// Opt-in interoperability for existing native ExpansionTile consumers.
  /// They keep their context-keyed bool; existing suite consumers keep the
  /// namespaced storage that avoids descendant ScrollPosition collisions.
  final bool useNativePageStorage;
  @override
  State<StarBridgeExpansionTile> createState() =>
      _StarBridgeExpansionTileState();
}

class _StarBridgeExpansionTileState extends State<StarBridgeExpansionTile> {
  late bool _expanded = widget.initiallyExpanded;
  bool _restored = false;
  Object? get _storageId => widget.key is PageStorageKey
      ? (StarBridgeExpansionTile, widget.key)
      : null;
  final _focus = FocusNode(debugLabel: 'StarBridge-disclosure');
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restored) {
      _restored = true;
      // Namespace the bool away from descendant ScrollPosition offsets.
      final stored = !widget.useNativePageStorage && _storageId == null
          ? null
          : PageStorage.maybeOf(context)?.readState(
              context,
              identifier: widget.useNativePageStorage ? null : _storageId,
            );
      if (stored is bool) _expanded = stored;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _change(bool value) {
    setState(() => _expanded = value);
    if (widget.useNativePageStorage || _storageId != null) {
      PageStorage.maybeOf(context)?.writeState(
        context,
        value,
        identifier: widget.useNativePageStorage ? null : _storageId,
      );
    }
    widget.onExpansionChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: SuiteExpander(
      title: widget.title,
      subtitle: widget.subtitle,
      titleStyle: widget.titleStyle ?? Theme.of(context).textTheme.titleMedium,
      subtitleStyle: Theme.of(context).textTheme.bodySmall,
      headerPadding: widget.headerPadding,
      bodyPadding: widget.childrenPadding,
      headerMinHeight: widget.headerMinHeight,
      headerBuilder: widget.headerBuilder,
      focusNode: _focus,
      expanded: _expanded,
      onChanged: _change,
      maintainState: widget.maintainState,
      child: Column(
        crossAxisAlignment: widget.childrenCrossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: widget.children,
      ),
    ),
  );
}
