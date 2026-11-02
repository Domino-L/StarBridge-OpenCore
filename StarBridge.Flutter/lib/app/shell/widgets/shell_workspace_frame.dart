import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../../design_system/appearance/appearance_scope.dart';
import '../../../design_system/interaction/starbridge_page_route.dart';
import '../../../design_system/tokens/color_tokens.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';
import '../shell_navigation_controller.dart';
import 'shell_workspace.dart';
import '../../../design_system/interaction/starbridge_timed_snack_bar.dart';

void showShellReminderUnavailable(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    starBridgeTimedSnackBar(
      content: Text(
        AppStrings.of(context)
            .text('settings.notification.activationUnavailable'),
      ),
    ),
  );
}

/// Shell-only framing; does not create or dispose any feature owner.
class ShellWindowFrame extends StatelessWidget {
  const ShellWindowFrame({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      key: const Key('application-window-frame'),
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(
          color: tokens.surfaces.windowFrame,
          width: tokens.stroke.hairline,
        ),
      ),
      child: child,
    );
  }
}

class ShellWorkspaceNavigator extends StatelessWidget {
  const ShellWorkspaceNavigator({
    required this.navigatorKey,
    required this.navigation,
    super.key,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final ShellNavigationController navigation;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // 页面底色上的节日印花或用户背景图；自己画底色的页面（全息页）会盖住它。
      const AppearanceSurfaceBackdrop(role: SurfaceRole.ground),
      _navigator(context),
    ],
  );

  Widget _navigator(BuildContext context) => Semantics(
    // The nested route barrier hides only its workspace, not shell chrome.
    container: true,
    child: Navigator(
      key: navigatorKey,
      onGenerateRoute: (_) => StarBridgePageRoute<void>.fromContext(
        context,
        source: InteractionSource.keyboard,
        builder: (_) => ListenableBuilder(
          listenable: navigation,
          builder: (_, _) => ShellWorkspace(
            selected: navigation.selected,
            interaction: navigation.lastInteraction,
          ),
        ),
      ),
    ),
  );
}
