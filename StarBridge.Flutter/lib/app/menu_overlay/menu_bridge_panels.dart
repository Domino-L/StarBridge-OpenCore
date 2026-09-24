import 'package:flutter/material.dart';

import 'menu_bridge_style.dart';

/// Synthetic content only; no account IDs, remote avatars or social actions.
class BridgeFriendsPreview extends StatelessWidget {
  const BridgeFriendsPreview({
    super.key,
    required this.onClose,
    this.embedded = false,
  });
  final VoidCallback onClose;
  final bool embedded;
  @override
  Widget build(BuildContext context) => BridgePlate(
    framed: !embedded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!embedded)
          Row(
            children: [
              const Expanded(
                child: Text(
                  '好友',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const BridgeCaption('3 在线'),
              BridgeMenuAction(
                key: const ValueKey('menu-panel-close'),
                label: '关闭好友面板',
                onPressed: onClose,
                padding: const EdgeInsets.all(10),
                child: const MenuGlyphView(MenuGlyph.close, size: 16),
              ),
            ],
          ),
        if (!embedded) const SizedBox(height: 22),
        const _Person('远', '远航者', '在线', self: true),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: BridgeInk.ground,
            border: const Border(bottom: BorderSide(color: BridgeInk.line)),
          ),
          child: const BridgeLabel(MenuGlyph.search, '搜索好友'),
        ),
        const SizedBox(height: 22),
        const Row(
          children: [
            Expanded(child: BridgeLabel(MenuGlyph.addFriend, '好友申请')),
            BridgeBadge('2'),
            SizedBox(width: 10),
            MenuGlyphView(MenuGlyph.next, size: 18),
          ],
        ),
        const SizedBox(height: 24),
        const BridgeCaption('在线 · 3'),
        const SizedBox(height: 12),
        const _Person('北', '北辰', '游戏中 · 奥里森'),
        const Divider(height: 25, color: BridgeInk.divider),
        const _Person('白', '白鸦', '游戏中 · 新巴贝奇', unread: true),
        const Divider(height: 25, color: BridgeInk.divider),
        const _Person('回', '回声', '应用在线', online: false),
        const SizedBox(height: 28),
        const Row(
          children: [
            Expanded(child: BridgeCaption('离线 · 12')),
            MenuGlyphView(MenuGlyph.down, size: 18),
          ],
        ),
        const Divider(height: 32, color: BridgeInk.divider),
        const BridgeLabel(MenuGlyph.add, '添加好友'),
      ],
    ),
  );
}

class _Person extends StatelessWidget {
  const _Person(
    this.letter,
    this.name,
    this.status, {
    this.self = false,
    this.unread = false,
    this.online = true,
  });
  final String letter, name, status;
  final bool self, unread, online;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      BridgeAvatar(letter, online: online),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            BridgeCaption(status),
          ],
        ),
      ),
      if (self) const MenuGlyphView(MenuGlyph.down, size: 18),
      if (unread) const BridgeBadge('2'),
    ],
  );
}

class BridgeCommsPreview extends StatelessWidget {
  const BridgeCommsPreview({
    super.key,
    required this.onClose,
    this.embedded = false,
  });
  final VoidCallback onClose;
  final bool embedded;
  @override
  Widget build(BuildContext context) => BridgePlate(
    framed: !embedded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embedded)
          Row(
            children: [
              const Text(
                '通信',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              const BridgeBadge('3'),
              const Spacer(),
              BridgeMenuAction(
                key: const ValueKey('menu-panel-close'),
                label: '关闭通讯面板',
                onPressed: onClose,
                padding: const EdgeInsets.all(10),
                child: const MenuGlyphView(MenuGlyph.close, size: 16),
              ),
            ],
          ),
        if (!embedded) const SizedBox(height: 24),
        const _Conversation('组织频道', '北辰：准备好后在机库集合。', '21:45', MenuGlyph.group),
        const Divider(height: 32, color: BridgeInk.divider),
        const _Conversation('白鸦', '我已经到达奥里森。', '21:42', MenuGlyph.person),
        const Divider(height: 40, color: BridgeInk.divider),
        const BridgeCaption('当前房间'),
        const SizedBox(height: 20),
        const BridgeLabel(MenuGlyph.group, '远航小队'),
        const SizedBox(height: 5),
        const BridgeCaption('4 / 8 人'),
        const SizedBox(height: 18),
        const Wrap(
          spacing: 8,
          children: [
            BridgeAvatar('远'),
            BridgeAvatar('北'),
            BridgeAvatar('白'),
            BridgeAvatar('回'),
          ],
        ),
        const SizedBox(height: 22),
        const Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            BridgeLabel(MenuGlyph.microphone, '麦克风'),
            BridgeLabel(MenuGlyph.headphones, '耳机'),
            BridgeLabel(MenuGlyph.room, '打开房间'),
          ],
        ),
      ],
    ),
  );
}

class _Conversation extends StatelessWidget {
  const _Conversation(this.name, this.message, this.time, this.icon);
  final String name, message, time;
  final MenuGlyph icon;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MenuGlyphView(icon, size: 27, color: BridgeInk.muted),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                BridgeCaption(time),
              ],
            ),
            const SizedBox(height: 6),
            BridgeCaption(message),
          ],
        ),
      ),
    ],
  );
}

class BridgeContextPreview extends StatelessWidget {
  const BridgeContextPreview({super.key, this.live = false, this.values});
  final bool live;
  final List<String>? values;
  @override
  Widget build(BuildContext context) => BridgePlate(
    framed: false,
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Wrap(
      spacing: 28,
      runSpacing: 18,
      children: [
        _Context('当前协作', values?[0] ?? (live ? '暂无协作场景' : '远航者组织')),
        _Context('成员', values?[1] ?? (live ? '—' : '12 人')),
        _Context('当前飞船', values?[2] ?? (live ? '—' : '星座 仙女座')),
        _Context('所在位置', values?[3] ?? (live ? '—' : '斯坦顿 · 奥里森')),
        _Context('服务器', values?[4] ?? (live ? '—' : '美服 · LIVE')),
      ],
    ),
  );
}

class _Context extends StatelessWidget {
  const _Context(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      BridgeCaption(label),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );
}
