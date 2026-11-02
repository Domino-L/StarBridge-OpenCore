import 'package:flutter/foundation.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_activation_origin.dart';

import '../feature_registry.dart';

enum NavigationInteraction { pointer, keyboard }

NavigationInteraction get currentNavigationInteraction =>
    currentStarBridgeActivationSource == InteractionSource.keyboard
    ? NavigationInteraction.keyboard
    : NavigationInteraction.pointer;

final class ShellNavigationController extends ChangeNotifier {
  ShellNavigationController({required FeatureDescriptor initial})
    : _selected = initial;

  FeatureDescriptor _selected;
  NavigationInteraction _lastInteraction = NavigationInteraction.keyboard;

  FeatureDescriptor get selected => _selected;
  NavigationInteraction get lastInteraction => _lastInteraction;

  /// Presentation metadata for an interaction within the current destination.
  /// The shell rebuilds its own controls; this does not select/enter a page.
  void recordInteraction(NavigationInteraction interaction) {
    _lastInteraction = interaction;
  }

  void select(
    FeatureDescriptor descriptor, {
    NavigationInteraction interaction = NavigationInteraction.pointer,
  }) {
    if (_selected == descriptor) {
      return;
    }
    _selected = descriptor;
    _lastInteraction = interaction;
    notifyListeners();
  }
}
