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
  String? _avatar;
  int _avatarEpoch = 0;
  @override
  void initState() {
    super.initState();
    module = createPersonalProfileModule(
      _ReadOnlyProfile(widget.port, widget.target),
    );
    module.projection.addListener(_profileChanged);
    unawaited(module.initialize());
  }

  void _profileChanged() {
    final epoch = ++_avatarEpoch;
    final profile = module.projection.value;
    if (profile.availability != PersonalProfileAvailability.available) {
      _avatar = null;
      return;
    }
    if (widget.avatarImageData == null &&
        profile.avatarImageData == null &&
        _avatar == null) {
      unawaited(_readAvatar(epoch));
    }
  }

  Future<void> _readAvatar(int epoch) async {
    try {
      // This existing read resolves the exact opaque source reference in Host.
      // Do not discover a substitute by name or make profile readiness wait.
      final row = await widget.port.social(widget.target);
      if (!mounted ||
          epoch != _avatarEpoch ||
          module.projection.value.availability !=
              PersonalProfileAvailability.available) {
        return;
      }
      if (row?.avatar != null) setState(() => _avatar = row!.avatar);
    } on Object {
      // A normal profile refresh retries an optional photo, not a hidden loop.
    }
  }

  @override
  void dispose() {
    _avatarEpoch++;
    module.projection.removeListener(_profileChanged);
    module.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UserProfileTargetScope(
    target: widget.target,
    child: PersonalProfilePage(
      module: module,
      isVisitor: true,
      visitorAvatarImageData: widget.avatarImageData ?? _avatar,
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
