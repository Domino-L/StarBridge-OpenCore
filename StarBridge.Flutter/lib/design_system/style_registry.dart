import 'package:flutter/foundation.dart';

import 'styles/future_restraint_style.dart';
import 'styles/probe_style.dart';
import 'tokens/color_tokens.dart';
import 'tokens/starbridge_tokens.dart';

typedef StyleResolver = StarBridgeTokens Function(AppearanceMode mode);

@immutable
final class StyleDescriptor {
  const StyleDescriptor({
    required this.id,
    required this.name,
    required this.resolve,
    required this.userSelectable,
  });

  final String id;
  final String name;
  final StyleResolver resolve;
  final bool userSelectable;
}

@immutable
final class StyleResolution {
  const StyleResolution({
    required this.tokens,
    required this.requestedStyleId,
    required this.didFallback,
    this.fallbackReason,
  });

  final StarBridgeTokens tokens;
  final String requestedStyleId;
  final bool didFallback;
  final String? fallbackReason;
}

final class StyleRegistry {
  StyleRegistry([Iterable<StyleDescriptor>? descriptors])
    : _descriptors = Map.unmodifiable({
        for (final descriptor in descriptors ?? defaults)
          descriptor.id: descriptor,
      }) {
    _validateCompleteness();
  }

  static const fallbackStyleId = FutureRestraintStyle.id;

  static const defaults = [
    StyleDescriptor(
      id: FutureRestraintStyle.id,
      name: FutureRestraintStyle.name,
      resolve: FutureRestraintStyle.resolve,
      userSelectable: true,
    ),
    StyleDescriptor(
      id: ProbeStyle.id,
      name: ProbeStyle.name,
      resolve: ProbeStyle.resolve,
      userSelectable: false,
    ),
  ];

  final Map<String, StyleDescriptor> _descriptors;

  Iterable<StyleDescriptor> get all => _descriptors.values;
  Iterable<StyleDescriptor> get userSelectable =>
      _descriptors.values.where((descriptor) => descriptor.userSelectable);

  StyleResolution resolve(String styleId, AppearanceMode mode) {
    final descriptor = _descriptors[styleId];
    if (descriptor == null) {
      return StyleResolution(
        tokens: _descriptors[fallbackStyleId]!.resolve(mode),
        requestedStyleId: styleId,
        didFallback: true,
        fallbackReason: 'style_not_registered',
      );
    }
    try {
      return StyleResolution(
        tokens: descriptor.resolve(mode),
        requestedStyleId: styleId,
        didFallback: false,
      );
    } on Object {
      return StyleResolution(
        tokens: _descriptors[fallbackStyleId]!.resolve(mode),
        requestedStyleId: styleId,
        didFallback: true,
        fallbackReason: 'style_resolution_failed',
      );
    }
  }

  void _validateCompleteness() {
    if (!_descriptors.containsKey(fallbackStyleId)) {
      throw StateError('Style registry requires the Direction A fallback.');
    }
    for (final descriptor in _descriptors.values) {
      for (final mode in AppearanceMode.values) {
        final tokens = descriptor.resolve(mode);
        if (tokens.styleId != descriptor.id || tokens.appearanceMode != mode) {
          throw StateError('Style ${descriptor.id} is incomplete for $mode.');
        }
      }
    }
  }
}
