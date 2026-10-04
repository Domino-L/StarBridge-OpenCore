import 'package:flutter/material.dart';

import 'menu_bridge_style.dart';
import 'menu_native_popup.dart';

/// The same profile-first avatar interaction as the client, with no account or
/// social command adapter installed in the secondary engine.
class MenuAvatarActions extends StatelessWidget {
  const MenuAvatarActions({
    super.key,
    required this.name,
    required this.child,
    this.onProfile,
    this.actions = const [],
  });
  final String name;
  final Widget child;
  final VoidCallback? onProfile;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => onProfile == null && actions.isEmpty
      ? child
      : MenuNativePopup(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(MenuBridgeColors.of(context).ground),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            side: WidgetStatePropertyAll(BorderSide(color: MenuBridgeColors.of(context).line)),
            elevation: WidgetStatePropertyAll(0),
            maximumSize: WidgetStatePropertyAll(Size(300, 400)),
          ),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            Divider(height: 1, color: MenuBridgeColors.of(context).divider),
            if (onProfile != null)
              MenuItemButton(onPressed: onProfile, child: const Text('查看个人页面')),
            ...actions,
          ],
          builder: (context, controller, _) => BridgeMenuAction(
            label: '$name · 头像菜单',
            padding: EdgeInsets.zero,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: child,
          ),
        );
}
