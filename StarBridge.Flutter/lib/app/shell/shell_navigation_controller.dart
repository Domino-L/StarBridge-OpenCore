import 'package:flutter/foundation.dart';

import '../feature_registry.dart';

enum NavigationInteraction { pointer, keyboard }

final class ShellNavigationController extends ChangeNotifier {
  ShellNavigationController({required FeatureDescriptor initial})
    : _selected = initial;

  FeatureDescriptor _selected;
  NavigationInteraction _lastInteraction = NavigationInteraction.keyboard;

  FeatureDescriptor get selected => _selected;
  NavigationInteraction get lastInteraction => _lastInteraction;

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
