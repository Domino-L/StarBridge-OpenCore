import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';

import 'menu_bridge_style.dart';
import 'menu_native_popup.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
export 'menu_native_popup.dart' show StarBridgeMenuEntry;

/// The same profile-first avatar interaction as the client, with no account or
/// social command adapter installed in the secondary engine.
class MenuAvatarActions extends StatelessWidget {
  const MenuAvatarActions({
    super.key,
    required this.name,
    required this.child,
    this.onProfile,
    this.identity,
    this.actions = const [],
  });
  final String name;
  final Widget child;
  final VoidCallback? onProfile;
  final Object? identity;
  final List<StarBridgeMenuEntry> actions;
  @override
  Widget build(BuildContext context) => onProfile == null && actions.isEmpty
      ? child
      : MenuNativePopup(
          identity: identity,
          label: menuText(context, 'menu.overlay.window.avatarMenu', {
            'name': name,
          }),
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(
              MenuBridgeColors.of(context).ground,
            ),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            side: WidgetStatePropertyAll(
              BorderSide(color: MenuBridgeColors.of(context).line),
            ),
            elevation: WidgetStatePropertyAll(0),
            maximumSize: WidgetStatePropertyAll(Size(300, 400)),
          ),
          header: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              Divider(height: 1, color: MenuBridgeColors.of(context).divider),
            ],
          ),
          entries: [
            if (onProfile != null)
              StarBridgeMenuEntry(
                id: 'avatar-profile',
                label: menuText(context, 'menu.overlay.window.viewProfile'),
                onActivate: (_) => onProfile!(),
                child: Text(
                  menuText(context, 'menu.overlay.window.viewProfile'),
                ),
              ),
            ...actions,
          ],
          builder: (context, controller, focus, toggle) => BridgeMenuAction(
            focusNode: focus,
            label: menuText(context, 'menu.overlay.window.avatarMenu', {
              'name': name,
            }),
            padding: EdgeInsets.zero,
            onPressed: () => toggle(currentStarBridgeActivationSource),
            child: child,
          ),
        );
}
