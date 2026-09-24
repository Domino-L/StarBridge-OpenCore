import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/icons/icon_semantic.dart';
import 'menu_overlay_workspace.dart';
import 'menu_workspace_controller.dart';

/// Explicit native preview entry only. No account, storage or feature adapters.
class MenuWorkspacePreview extends StatefulWidget {
  const MenuWorkspacePreview({
    super.key,
    required this.visible,
    required this.onDismiss,
  });
  final bool visible;
  final VoidCallback onDismiss;
  @override
  State<MenuWorkspacePreview> createState() => _MenuWorkspacePreviewState();
}

class _MenuWorkspacePreviewState extends State<MenuWorkspacePreview> {
  late final controller =
      MenuWorkspaceController(
          scope: Object(),
          panels: [
            MenuPanelSpec(
              id: 'friends',
              initialBounds: const Rect.fromLTWH(40, 40, 340, 500),
            ),
            MenuPanelSpec(
              id: 'messages',
              initialBounds: const Rect.fromLTWH(410, 80, 500, 440),
            ),
            MenuPanelSpec(
              id: 'help',
              initialBounds: const Rect.fromLTWH(100, 100, 380, 300),
            ),
          ],
        )
        ..open('friends')
        ..open('messages')
        ..setVisible(widget.visible);
  late final panels = [
    MenuPanelContent(
      id: 'friends',
      title: '好友',
      icon: StarBridgeIconSemantic.friends,
      builder: (_, _) => const _FriendsPreview(),
    ),
    MenuPanelContent(
      id: 'messages',
      title: '消息',
      icon: StarBridgeIconSemantic.notifications,
      builder: (_, _) => const _MessagesPreview(),
    ),
    MenuPanelContent(
      id: 'help',
      title: '预览说明',
      icon: StarBridgeIconSemantic.tools,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('菜单交互预览'),
          SizedBox(height: 12),
          Text('拖动标题移动面板，拖动右下角调整大小。底部入口可以重新打开或切换面板。'),
          SizedBox(height: 12),
          Text('Esc 关闭浮层；在预览控制窗口中可以再次打开。'),
          SizedBox(height: 12),
          Text('这里均为演示内容。好友、通信和其他工具尚未接入真实数据，不会发送消息或保存设置。'),
        ],
      ),
    ),
  ];
  @override
  void didUpdateWidget(covariant MenuWorkspacePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      controller.setVisible(widget.visible);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
    },
    child: MenuOverlayWorkbench(
      controller: controller,
      panels: panels,
      contextLabel: '菜单交互预览 · 演示数据',
      returnLabel: '关闭预览',
      settingsLabel: '设置',
      closeLabel: '关闭面板',
      moveLabel: '移动面板',
      resizeLabel: '调整大小',
      onReturn: widget.onDismiss,
    ),
  );
}

class _FriendsPreview extends StatefulWidget {
  const _FriendsPreview();
  @override
  State<_FriendsPreview> createState() => _FriendsPreviewState();
}

class _FriendsPreviewState extends State<_FriendsPreview> {
  String query = '';
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(child: Text('我')),
        title: Text('本人状态 · 演示'),
        subtitle: Text('应用在线'),
      ),
      const SizedBox(height: 12),
      TextField(
        decoration: const InputDecoration(hintText: '搜索演示好友'),
        onChanged: (value) => setState(() => query = value),
      ),
      const SizedBox(height: 20),
      const Text('好友请求 · 0'),
      const Divider(),
      for (final group in ['在线', '离线']) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(group),
        ),
        for (final name in (group == '在线' ? ['演示好友 A', '演示好友 B'] : ['演示好友 C']))
          if (name.toLowerCase().contains(query.toLowerCase()))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(name.substring(name.length - 1)),
              ),
              title: Text(name),
              subtitle: Text(group == '在线' ? '未进入游戏' : '离线'),
            ),
      ],
    ],
  );
}

class _MessagesPreview extends StatefulWidget {
  const _MessagesPreview();
  @override
  State<_MessagesPreview> createState() => _MessagesPreviewState();
}

class _MessagesPreviewState extends State<_MessagesPreview> {
  final draft = TextEditingController();
  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('演示会话'),
      const Divider(),
      const SizedBox(height: 12),
      const Text('这里用于查看消息面板的大小和排版。'),
      const SizedBox(height: 16),
      const Text('可以输入草稿并切换面板，检查内容是否保留。此预览不会发送消息。'),
      const SizedBox(height: 24),
      TextField(
        controller: draft,
        minLines: 3,
        maxLines: 5,
        decoration: const InputDecoration(
          hintText: '输入预览草稿…',
          labelText: '仅在本次预览中保留',
        ),
      ),
    ],
  );
}
