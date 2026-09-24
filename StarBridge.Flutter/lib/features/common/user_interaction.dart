import 'package:flutter/material.dart';

import '../../app/routing/user_page_navigation.dart';
export '../../app/routing/user_page_navigation.dart';

import '../friends/friends_module.dart';
import '../personal_profile/personal_profile_models.dart';

/// References originate in authenticated projections, never in display names.
class UserTarget {
  const UserTarget(
    this.source,
    this.reference, {
    this.contextRef,
    this.query = '',
  });
  const UserTarget.community(String context, String member, {String query = ''})
    : this('community', member, contextRef: context, query: query);
  final String source, reference, query;
  final String? contextRef;
  Map<String, Object?> get payload => {
    'source': source,
    'reference': reference,
    'contextRef': ?contextRef,
    'query': query,
  };
}

abstract interface class UserInteractionPort {
  Stream<void> get invalidations;
  Future<PersonalProfileSnapshot> profile(UserTarget target);
  Future<FriendRow?> social(UserTarget target);
  Future<FriendCommandResult> execute(String action, String reference);
  Future<void> close();
}

class UserInteractionScope extends InheritedWidget {
  const UserInteractionScope({
    required this.navigation,
    required this.port,
    required this.messagePage,
    required super.child,
    super.key,
  });
  final UserPageNavigation navigation;
  final UserInteractionPort? port;
  final Widget Function(FriendRow row, VoidCallback back)? messagePage;
  static UserInteractionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserInteractionScope>();
  @override
  bool updateShouldNotify(UserInteractionScope oldWidget) =>
      port != oldWidget.port || navigation != oldWidget.navigation;
}
