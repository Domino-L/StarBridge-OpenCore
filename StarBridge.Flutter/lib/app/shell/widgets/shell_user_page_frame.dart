import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../../design_system/icons/standard_icon.dart';
import '../../../design_system/interaction/starbridge_activation_origin.dart';
import '../../../design_system/interaction/starbridge_icon_action.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';
import '../../routing/user_page_navigation.dart';

/// Original route chrome only. The primary shell owns the route, leave guard,
/// activation source and back transaction; this function adds no state owner.
Widget buildShellUserPageFrame(
  BuildContext pageContext, {
  required WidgetBuilder builder,
  required String title,
  required UserPageLeaveGuard leave,
  required Future<void> Function(InteractionSource) back,
}) {
  final page = builder(pageContext);
  return CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          unawaited(back(InteractionSource.keyboard)),
    },
    child: _UserPageKeyboardFocus(
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            unawaited(back(currentStarBridgeActivationSource));
          }
        },
        child: UserPageLeaveScope(
          guard: leave,
          child: ColoredBox(
            color: pageContext.tokens.surfaces.ground.fill,
            child: Column(
              children: [
                if (page is! SelfNavigatingUserPage)
                  Row(
                    children: [
                      StarBridgeIconAction(
                        controlKey: const Key('user-page-back'),
                        label: MaterialLocalizations.of(pageContext)
                            .backButtonTooltip,
                        icon: const StandardIcon(
                          StandardIconSemantic.arrowBack,
                        ),
                        onActivate: (source) => unawaited(back(source)),
                      ),
                      Text(AppStrings.of(pageContext).text(title)),
                    ],
                  ),
                Expanded(child: page),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A non-traversal fallback under the page shortcuts. Let descendant
/// autofocus settle first; never replace an editor's selected focus target.
class _UserPageKeyboardFocus extends StatefulWidget {
  const _UserPageKeyboardFocus({required this.child});
  final Widget child;
  @override
  State<_UserPageKeyboardFocus> createState() => _UserPageKeyboardFocusState();
}

class _UserPageKeyboardFocusState extends State<_UserPageKeyboardFocus> {
  final _focus = FocusNode(
    skipTraversal: true,
    debugLabel: 'user-page-shortcuts',
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        if (FocusScope.of(context).focusedChild == null) _focus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _focus, child: widget.child);
}
