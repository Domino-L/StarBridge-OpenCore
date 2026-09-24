import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../personal_profile/personal_profile_models.dart';
import '../personal_profile/personal_profile_module.dart';
import '../personal_profile/personal_profile_page.dart';
import '../personal_profile/personal_profile_port.dart';
import 'user_interaction.dart';

class UserProfilePage extends StatefulWidget implements SelfNavigatingUserPage {
  const UserProfilePage({
    required this.port,
    required this.target,
    this.avatarImageData,
    super.key,
  });
  final UserInteractionPort port;
  final UserTarget target;
  final String? avatarImageData;
  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late final PersonalProfileModule module;
  @override
  void initState() {
    super.initState();
    module = createPersonalProfileModule(
      _ReadOnlyProfile(widget.port, widget.target),
    );
    unawaited(module.initialize());
  }

  @override
  void dispose() {
    module.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UserProfileTargetScope(
    target: widget.target,
    child: PersonalProfilePage(
      module: module,
      isVisitor: true,
      visitorAvatarImageData: widget.avatarImageData,
      pageToolbar: Row(
        key: const Key('visitor-profile-toolbar'),
        children: [
          BackButton(
            onPressed: () async {
              final guard = UserPageLeaveScope.maybeOf(context)?.confirm;
              if (guard != null && !await guard()) return;
              if (context.mounted) Navigator.of(context).maybePop();
            },
          ),
          const Spacer(),
          IconButton(
            key: const Key('visitor-profile-refresh'),
            tooltip: AppStrings.of(context).text('profile.refresh'),
            onPressed: () => unawaited(module.refresh()),
            icon: const StandardIcon(StandardIconSemantic.refresh),
          ),
        ],
      ),
    ),
  );
}

class UserProfileTargetScope extends InheritedWidget {
  const UserProfileTargetScope({
    required this.target,
    required super.child,
    super.key,
  });
  final UserTarget target;
  static UserTarget? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<UserProfileTargetScope>()
      ?.target;
  @override
  bool updateShouldNotify(UserProfileTargetScope oldWidget) =>
      target != oldWidget.target;
}

class _ReadOnlyProfile implements PersonalProfilePort {
  _ReadOnlyProfile(this.source, this.target) {
    subscription = source.invalidations.listen((_) {
      invalidated = true;
      changes.add(null);
    });
  }
  final UserInteractionPort source;
  final UserTarget target;
  final changes = StreamController<void>.broadcast();
  late final StreamSubscription<void> subscription;
  bool invalidated = false;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<PersonalProfileSnapshot> read() async {
    const unavailable = PersonalProfileSnapshot.unavailable(
      failureKey: 'profile.visitor.refreshMembers',
    );
    if (invalidated) return unavailable;
    final result = await source.profile(target);
    return invalidated || result.allowEditing || result.local != null
        ? unavailable
        : result;
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async =>
      const PersonalProfileActionResult(PersonalProfileActionOutcome.rejected);
  @override
  Future<void> close() async {
    invalidated = true;
    await subscription.cancel();
    await changes.close();
  }
}
