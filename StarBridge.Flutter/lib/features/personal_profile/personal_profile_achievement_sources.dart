import 'package:flutter/foundation.dart';

import '../achievements/achievement_catalog.dart';
import '../achievements/achievement_collection_port.dart';
import '../achievements/achievement_sources.dart';

/// What the profile counts and shows: the same achievements the achievements
/// page counts (its catalog plus the SCM ones). The Host read carries no
/// catalog of its own, so counting it alone always gave 0 (build 65).
AchievementCollection profileAchievementCollection(
  AchievementCollection bridge,
  AchievementCollection? scm, [
  List<AchievementDefinition> catalog = achievementCatalog,
]) {
  final usable = scm != null && scm.generation == bridge.generation;
  return combineAchievementSources(
    bridge,
    usable
        ? scm
        // An empty stand-in in the bridge's state, so the catalog is still
        // attached and nothing becomes ready that was not.
        : AchievementCollection(
            generation: bridge.generation,
            status: bridge.status,
          ),
    catalog,
  );
}

/// The shared collections seen as one; borrows them. It follows them only
/// while something on screen listens: a listener makes a collection read,
/// and nothing may read before the profile or achievements are shown.
final class ProfileAchievementSources extends ChangeNotifier
    implements ValueListenable<AchievementCollection> {
  ProfileAchievementSources(this.bridge, this.scm);
  var _following = false;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_following || !hasListeners) return;
    _following = true;
    bridge.addListener(notifyListeners);
    scm?.addListener(notifyListeners);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!_following || hasListeners) return;
    _following = false;
    bridge.removeListener(notifyListeners);
    scm?.removeListener(notifyListeners);
  }

  final ValueListenable<AchievementCollection> bridge;
  final ValueListenable<AchievementCollection>? scm;

  @override
  AchievementCollection get value =>
      profileAchievementCollection(bridge.value, scm?.value);

  @override
  void dispose() {
    if (_following) {
      bridge.removeListener(notifyListeners);
      scm?.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
