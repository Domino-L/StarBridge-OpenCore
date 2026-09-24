import 'package:flutter/widgets.dart';

/// A workspace page that renders its own navigation on its content background.
abstract interface class SelfNavigatingUserPage {}

/// Shell-owned navigation preserves the source page while another page is open.
class UserPageNavigation {
  Future<void> Function(BuildContext, WidgetBuilder, String)? open;
  Future<void> Function(BuildContext)? openSelf;
}

class UserPageLeaveGuard {
  Future<bool> Function()? confirm;
}

class UserPageLeaveScope extends InheritedWidget {
  const UserPageLeaveScope({
    required this.guard,
    required super.child,
    super.key,
  });
  final UserPageLeaveGuard guard;
  static UserPageLeaveGuard? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserPageLeaveScope>()?.guard;
  @override
  bool updateShouldNotify(UserPageLeaveScope oldWidget) =>
      guard != oldWidget.guard;
}
