import 'package:flutter/material.dart';

import '../../features/personal_profile/personal_profile_module.dart';
import '../../features/personal_profile/personal_profile_models.dart';
import '../../features/personal_profile/personal_profile_page.dart';
import '../menu_overlay/menu_profile_view.dart';
import '../localization/app_strings.dart';

/// Display-only composition: no account, transport or write port in this engine.
class MenuProfileWindowPage extends StatefulWidget {
  const MenuProfileWindowPage({
    super.key,
    required this.view,
    required this.onRefresh,
  });
  final MenuProfileView view;
  final VoidCallback onRefresh;
  @override
  State<MenuProfileWindowPage> createState() => _MenuProfileWindowPageState();
}

class _MenuProfileWindowPageState extends State<MenuProfileWindowPage> {
  late final _DisplayProfile module = _DisplayProfile(() => widget.onRefresh())
    ..update(widget.view);
  @override
  void didUpdateWidget(MenuProfileWindowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view)) module.update(widget.view);
  }

  @override
  void dispose() {
    module.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PersonalProfilePage(
    module: module,
    isVisitor: true,
    pageToolbar: TextButton(
      onPressed:
          widget.view.state == 'loading' || widget.view.state == 'revoked'
          ? null
          : widget.onRefresh,
      child: Text(AppStrings.of(context).text('profile.refresh')),
    ),
  );
}

final class _DisplayProfile implements PersonalProfileModule {
  _DisplayProfile(this.read);
  final VoidCallback read;
  @override
  final ValueNotifier<PersonalProfileProjection> projection =
      ValueNotifier<PersonalProfileProjection>(
        const PersonalProfileProjection.loading(),
      );
  void update(MenuProfileView view) {
    if (view.state == 'ready' && view.snapshot != null) {
      projection.value = PersonalProfileProjection.fromSnapshot(view.snapshot!);
    } else if (view.state == 'loading') {
      projection.value =
          projection.value.availability == PersonalProfileAvailability.available
          ? projection.value.copyWith(
              operation: PersonalProfileOperation.refreshing,
            )
          : const PersonalProfileProjection.loading();
    } else {
      projection.value = PersonalProfileProjection.fromSnapshot(
        PersonalProfileSnapshot.unavailable(
          failureKey: view.state == 'notVisible'
              ? 'profile.visitor.notVisible'
              : view.state == 'revoked'
              ? 'profile.visitor.refreshMembers'
              : 'profile.error.unavailable',
        ),
      );
    }
  }

  @override
  Future<PersonalProfileActionResult> initialize() => refresh();
  @override
  Future<PersonalProfileActionResult> refresh() async {
    read();
    return const PersonalProfileActionResult(
      PersonalProfileActionOutcome.completed,
    );
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async =>
      const PersonalProfileActionResult(PersonalProfileActionOutcome.rejected);
  @override
  void renameCommunity(String code, String name) {}
  @override
  void dispose() => projection.dispose();
}
