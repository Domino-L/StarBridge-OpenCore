import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import 'menu_chat_widgets.dart';
import 'menu_comms_view.dart';
import 'menu_comms_composer.dart';
import 'menu_inline_avatar.dart';
import 'menu_loading.dart';
import 'menu_avatar_actions.dart';
import 'menu_visible_receipts.dart';
import 'menu_feature_view.dart';

class MenuCommsHistory extends StatefulWidget {
  const MenuCommsHistory({
    super.key,
    required this.view,
    required this.active,
    required this.onAction,
    this.onProfile,
    this.onCompose,
    this.disconnected = false,
  });
  final MenuCommsView view;
  final bool active, disconnected;
  final void Function(String, String) onAction;
  final ValueChanged<String>? onProfile;
  final void Function(String, String, String, int)? onCompose;
  @override
  State<MenuCommsHistory> createState() => _MenuCommsHistoryState();
}

class _MenuCommsHistoryState extends State<MenuCommsHistory> {
  final _scroll = ScrollController();
  bool _newMessages = false;
  @override
  void didUpdateWidget(MenuCommsHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.view, next = widget.view;
    if (previous.profileKey != next.profileKey ||
        previous.pageKey != next.pageKey) {
      _newMessages = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    } else if (previous.messages.lastOrNull != next.messages.lastOrNull &&
        _scroll.hasClients &&
        _scroll.offset > 48) {
      final pixels = _scroll.offset, extent = _scroll.position.maxScrollExtent;
      _newMessages = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(
          (pixels + _scroll.position.maxScrollExtent - extent).clamp(
            0,
            _scroll.position.maxScrollExtent,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget action(String key, String title) => StarBridgeActionButton(
    controlKey: ValueKey('menu-comms-$key'),
    semanticLabel: title,
    onActivate: widget.view.busy ? null : (_) => widget.onAction(key, ''),
    child: Text(title),
  );
  Widget portrait() => MenuAvatarActions(
    identity: ('peer', widget.view.profileKey),
    name: widget.view.name ?? '',
    onProfile: widget.onProfile == null || widget.view.profileKey == null
        ? null
        : () => widget.onProfile!(widget.view.profileKey!),
    child: MenuInlineAvatar(name: widget.view.name, source: widget.view.avatar),
  );
  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    if (view.name == null) {
      return Center(
        child: Text(menuText(context, 'menu.overlay.comms.select')),
      );
    }
    final status = switch (view.conversationState) {
      'request_incoming' => menuText(
        context,
        'menu.overlay.comms.incomingRequest',
      ),
      'request_outgoing' => menuText(
        context,
        'menu.overlay.comms.outgoingRequest',
      ),
      'friend' => menuText(context, 'menu.tools.friends'),
      'accepted' => menuText(context, 'menu.overlay.comms.accepted'),
      _ => view.request ? menuText(context, 'menu.overlay.comms.request') : '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuChatHeader(
          title: view.name!,
          subtitle: status,
          portrait: portrait(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            action('back', menuText(context, 'menu.overlay.comms.back')),
            if (view.hasOlder)
              action('older', menuText(context, 'menu.overlay.comms.older')),
            action(
              'latest',
              view.olderPage
                  ? menuText(context, 'menu.overlay.comms.latest')
                  : menuText(context, 'menu.overlay.comms.refreshMessages'),
            ),
            if (view.inviteAvailable && view.canSend)
              action(
                'inviteSend',
                menuText(context, 'menu.overlay.comms.invite'),
              ),
            if (view.archiveAvailable)
              MenuFeatureAction(
                identity: view.profileKey ?? view.pageKey,
                action: (
                  key: 'clearLocal',
                  role: 'clearLocalHistory',
                  secret: false,
                  label: menuText(context, 'menu.overlay.comms.clearLocal'),
                  confirm: menuText(context, 'menu.overlay.comms.clearConfirm'),
                  input: null,
                  limit: 128,
                ),
                enabled: !view.busy,
                onAction: widget.onAction,
              ),
          ],
        ),
        if (view.notice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    view.notice,
                    style: TextStyle(color: context.tokens.colors.warning),
                  ),
                ),
                action('retry', menuText(context, 'menu.display.reload')),
              ],
            ),
          ),
        if (view.readStatus == 'failed')
          Text(
            menuText(context, 'menu.overlay.comms.readSyncFailed'),
            style: TextStyle(color: context.tokens.colors.warning),
          ),
        if (view.refreshing) MenuLoading(feedback: view.readFeedback),
        Divider(color: context.tokens.surfaces.panel.border),
        Expanded(
          child: MenuVisibleReceipts(
            active: widget.active && view.notice.isEmpty,
            tokens: view.receipts,
            onRead: (key) => widget.onAction('read', key),
            builder: (anchors) => view.messages.isEmpty
                ? Center(
                    child: Text(menuText(context, 'menu.overlay.comms.empty')),
                  )
                : MenuChatScroll(
                    controller: _scroll,
                    child: ListView.builder(
                      key: const ValueKey('menu-message-history'),
                      controller: _scroll,
                      reverse: true,
                      itemCount: view.messages.length,
                      itemBuilder: (context, reverseIndex) {
                        final index = view.messages.length - 1 - reverseIndex,
                            message = view.messages[index];
                        final time = message.time.toLocal();
                        String pad(int n) => n.toString().padLeft(2, '0');
                        return KeyedSubtree(
                          key: anchors[index],
                          child: MenuChatMessage(
                            incoming: message.incoming,
                            sender: message.incoming
                                ? view.name!
                                : menuText(context, 'menu.overlay.comms.me'),
                            time:
                                '${time.year}/${time.month}/${time.day} ${pad(time.hour)}:${pad(time.minute)}',
                            portrait: message.incoming
                                ? portrait()
                                : MenuAvatarActions(
                                    identity: ('self', view.pageKey),
                                    name: menuText(
                                      context,
                                      'menu.overlay.comms.me',
                                    ),
                                    onProfile: widget.onProfile == null
                                        ? null
                                        : () => widget.onProfile!('self'),
                                    child: MenuInlineAvatar(
                                      name: menuText(
                                        context,
                                        'menu.overlay.comms.me',
                                      ),
                                      source: view.ownAvatar,
                                    ),
                                  ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (message.text.isNotEmpty)
                                  SelectableText(message.text),
                                if ((view.attachments[index] ?? '')
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(view.attachments[index]!),
                                ],
                                if (view.attachmentKeys[index] case final key?)
                                  StarBridgeActionButton(
                                    semanticLabel: menuText(
                                      context,
                                      'menu.overlay.comms.viewInvite',
                                    ),
                                    onActivate:
                                        view.busy || view.notice.isNotEmpty
                                        ? null
                                        : (_) => widget.onAction(
                                            'attachment',
                                            key,
                                          ),
                                    child: Text(
                                      menuText(
                                        context,
                                        'menu.overlay.comms.viewInvite',
                                      ),
                                    ),
                                  )
                                else if (message.attachment)
                                  Text(
                                    menuText(
                                      context,
                                      'menu.overlay.comms.unsupportedAttachment',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
        if (_newMessages)
          Align(
            alignment: Alignment.centerRight,
            child: StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: const ValueKey('menu-comms-new-messages'),
              semanticLabel: menuText(
                context,
                'menu.overlay.comms.newMessages',
              ),
              onActivate: (_) {
                if (_scroll.hasClients) _scroll.jumpTo(0);
                setState(() => _newMessages = false);
              },
              child: Text(menuText(context, 'menu.overlay.comms.newMessages')),
            ),
          ),
        if (view.compose && view.profileKey != null && widget.onCompose != null)
          MenuCommsComposer(
            key: ValueKey('composer-${view.profileKey}'),
            view: view,
            onCompose: widget.onCompose!,
            disconnected: widget.disconnected,
          )
        else
          Padding(
            padding: EdgeInsets.all(12),
            child: Text(menuText(context, 'menu.overlay.comms.cannotSend')),
          ),
      ],
    );
  }
}
