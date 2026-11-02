import 'menu_overlay_locale.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'menu_native_popup.dart';
import 'menu_chrome_hint.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'package:flutter/services.dart';

import 'menu_bridge_style.dart';
import 'menu_friends_view.dart';
import 'menu_comms_panel.dart' show MenuInlineAvatar;
import '../presence/manual_presence_widgets.dart';
import '../../shared/release/official_client_profile.dart';

String menuFriendActionLabel(BuildContext? context, String action) =>
    switch (action) {
      'send' => menuText(context, 'menu.overlay.friends.send'),
      'accept' => menuText(context, 'menu.overlay.friends.accept'),
      'reject' => menuText(context, 'menu.overlay.friends.reject'),
      'cancel' => menuText(context, 'friends.action.cancel'),
      'remove' => menuText(context, 'menu.overlay.friends.remove'),
      'block' => menuText(context, 'menu.overlay.friends.block'),
      'unblock' => menuText(context, 'friends.action.unblock'),
      _ => '',
    };

class MenuFriendsControls extends StatefulWidget {
  const MenuFriendsControls({
    super.key,
    required this.view,
    required this.onAction,
    this.onFilter,
  });
  final MenuFriendsView view;
  final void Function(String action, String key, String value) onAction;
  final ValueChanged<String>? onFilter;
  @override
  State<MenuFriendsControls> createState() => _MenuFriendsControlsState();
}

class _MenuFriendsControlsState extends State<MenuFriendsControls> {
  MenuBridgeColors get ink => MenuBridgeColors.of(context);
  Color _statusColor(String value) =>
      menuPresenceColor(value, context: context);

  late final _query = TextEditingController(text: widget.view.query);
  final _confirmationAnchor = GlobalKey(), _feedbackAnchor = GlobalKey();
  @override
  void didUpdateWidget(MenuFriendsControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.query != widget.view.query ||
        oldWidget.view.section != widget.view.section) {
      _query.text = widget.view.query;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFilter?.call(_query.text);
      });
    }
    final token = widget.view.confirmation?.token;
    final anchor = token != null && token != oldWidget.view.confirmation?.token
        ? _confirmationAnchor
        : widget.view.feedback.isNotEmpty &&
              widget.view.feedback != oldWidget.view.feedback
        ? _feedbackAnchor
        : null;
    if (anchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = anchor.currentContext;
        if (target != null) {
          unawaited(Scrollable.ensureVisible(target, alignment: .15));
        }
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view, pending = widget.view.confirmation;
    Widget action(
      String label,
      String command, {
      String key = '',
      String value = '',
    }) => BridgeMenuAction(
      key: ValueKey('friends-$command-${key.isEmpty ? value : key}'),
      label: label,
      onPressed: view.busy ? null : () => widget.onAction(command, key, value),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(label),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.self case final own?) ...[
          Row(
            children: [
              MenuInlineAvatar(
                source: view.identity?.avatar,
                name: view.identity?.name,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.identity?.name.isNotEmpty == true
                          ? view.identity!.name
                          : menuText(context, 'menu.overlay.friends.myStatus'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (view.identity?.handle.isNotEmpty == true)
                      Text(
                        view.identity!.handle,
                        style: TextStyle(fontSize: 12, color: ink.muted),
                      ),
                    MenuNativePopup(
                      identity: (view.scope, own.key, 'presence'),
                      label: menuText(
                        context,
                        'menu.overlay.friends.changePresence',
                      ),
                      enabled:
                          (own.change ||
                              view.canEnterOffline ||
                              own.status == 'presence.manualOffline') &&
                          !own.busy,
                      style: MenuStyle(
                        backgroundColor: WidgetStatePropertyAll(ink.ground),
                      ),
                      entries: [
                        for (final mode in ['online', 'invisible'])
                          StarBridgeMenuEntry(
                            id: 'friends-presence-$mode',
                            label: mode == 'online'
                                ? OfficialClientProfile.connectionModes &&
                                          view.canRestoreOnline
                                      ? menuText(
                                          context,
                                          'menu.overlay.friends.resumeOnline',
                                        )
                                      : menuText(
                                          context,
                                          'menu.overlay.friends.online',
                                        )
                                : menuText(
                                    context,
                                    'menu.overlay.friends.invisible',
                                  ),
                            onActivate:
                                mode == 'online' &&
                                    OfficialClientProfile.connectionModes &&
                                    view.canRestoreOnline &&
                                    !own.busy
                                ? (_) => widget.onAction(
                                    'resumeOnline',
                                    own.key,
                                    '',
                                  )
                                : own.change && !own.busy
                                ? (_) =>
                                      widget.onAction('presence', own.key, mode)
                                : null,
                            child: Text(
                              mode == 'online'
                                  ? OfficialClientProfile.connectionModes &&
                                            view.canRestoreOnline
                                        ? menuText(
                                            context,
                                            'menu.overlay.friends.resumeOnline',
                                          )
                                        : menuText(
                                            context,
                                            'menu.overlay.friends.online',
                                          )
                                  : menuText(
                                      context,
                                      'menu.overlay.friends.invisible',
                                    ),
                              style: TextStyle(color: _statusColor(mode)),
                            ),
                          ),
                        if (OfficialClientProfile.connectionModes)
                          StarBridgeMenuEntry(
                            id: 'friends-presence-offline',
                            controlKey: const ValueKey(
                              'friends-presence-offline',
                            ),
                            label: manualPresenceText(
                              context,
                              'presence.selectOffline',
                            ),
                            onActivate: view.canEnterOffline && !own.busy
                                ? (_) => widget.onAction(
                                    'offlineMode',
                                    own.key,
                                    '',
                                  )
                                : null,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _statusColor('manualOffline'),
                                  ),
                                  child: const SizedBox.square(dimension: 8),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    manualPresenceText(
                                      context,
                                      'presence.selectOffline',
                                    ),
                                    style: TextStyle(
                                      color: _statusColor('manualOffline'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      builder: (context, controller, focus, toggle) =>
                          BridgeMenuAction(
                            focusNode: focus,
                            label: menuText(
                              context,
                              'menu.overlay.friends.changePresence',
                            ),
                            padding: EdgeInsets.symmetric(vertical: 6),
                            onPressed:
                                (own.change ||
                                        view.canEnterOffline ||
                                        own.status ==
                                            'presence.manualOffline') &&
                                    !own.busy
                                ? () =>
                                      toggle(currentStarBridgeActivationSource)
                                : null,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _statusColor(
                                      own.status.replaceFirst('presence.', ''),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    manualPresenceText(context, own.status),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _statusColor(
                                        own.status.replaceFirst(
                                          'presence.',
                                          '',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 4),
                                MenuGlyphView(
                                  MenuGlyph.down,
                                  size: 16,
                                  color: ink.muted,
                                ),
                              ],
                            ),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (own.busy)
            BridgeCaption(menuText(context, 'menu.overlay.friends.switching')),
          if (own.failed)
            BridgeCaption(
              menuText(context, 'menu.overlay.friends.statusFailed'),
            ),
          SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: StarBridgeFieldFrame(
                key: const ValueKey('friends-account-field-frame'),
                builder: (_, focus) => TextField(
                  focusNode: focus,
                  key: ValueKey('friends-account-search'),
                  controller: _query,
                  readOnly: view.busy,
                  style: TextStyle(
                    fontSize: 13,
                    color: ink.text,
                    fontFamily: 'Source Sans 3',
                    fontFamilyFallback: ['Source Han Sans CN'],
                  ),
                  onChanged: widget.onFilter,
                  onSubmitted: view.busy
                      ? null
                      : (value) => runStarBridgeSynchronousActivation(
                          InteractionSource.keyboard,
                          () => widget.onAction('search', '', value),
                        ),
                  textInputAction: TextInputAction.search,
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) =>
                          newValue.text.length <= 128 ? newValue : oldValue,
                    ),
                  ],
                  decoration: InputDecoration(
                    hintText: menuText(
                      context,
                      'menu.overlay.friends.searchHint',
                    ),
                    hintStyle: TextStyle(
                      color: ink.muted,
                      fontSize: 13,
                      fontFamily: 'Source Sans 3',
                      fontFamilyFallback: ['Source Han Sans CN'],
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: ink.ground,
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: ink.line),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: ink.blue),
                    ),
                  ),
                ),
              ),
            ),
            MenuChromeHint(
              message: menuText(context, 'menu.overlay.friends.searchEnter'),
              child: BridgeMenuAction(
                key: ValueKey('friends-search'),
                label: menuText(context, 'menu.overlay.friends.search'),
                onPressed: view.busy
                    ? null
                    : () => widget.onAction('search', '', _query.text),
                padding: EdgeInsets.all(8),
                child: MenuGlyphView(
                  MenuGlyph.search,
                  size: 18,
                  color: ink.blue,
                ),
              ),
            ),
            MenuChromeHint(
              message: menuText(context, 'menu.overlay.friends.refresh'),
              child: BridgeMenuAction(
                key: ValueKey('friends-refresh-'),
                label: menuText(context, 'menu.overlay.friends.refresh'),
                onPressed: view.busy
                    ? null
                    : () => widget.onAction('refresh', '', ''),
                padding: EdgeInsets.all(8),
                child: MenuGlyphView(
                  MenuGlyph.refresh,
                  size: 18,
                  color: ink.muted,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: view.section == 'friends'
                  ? Text(
                      menuText(context, 'menu.overlay.friends.selectToChat'),
                      style: TextStyle(fontSize: 12, color: ink.muted),
                    )
                  : BridgeMenuAction(
                      key: ValueKey('friends-section-friends'),
                      label: menuText(context, 'menu.overlay.friends.back'),
                      padding: EdgeInsets.symmetric(vertical: 8),
                      onPressed: view.busy
                          ? null
                          : () => widget.onAction('section', '', 'friends'),
                      child: Text(
                        menuText(context, 'menu.overlay.friends.backArrow'),
                        style: TextStyle(color: ink.blue, fontSize: 13),
                      ),
                    ),
            ),
            MenuNativePopup(
              identity: (view.scope, 'manage'),
              label: menuText(context, 'menu.overlay.friends.manage'),
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(ink.ground),
              ),
              entries: [
                for (final section in {
                  'incoming': menuText(context, 'friends.incoming'),
                  'outgoing': menuText(
                    context,
                    'menu.overlay.friends.outgoing',
                  ),
                  'blocked': menuText(context, 'menu.overlay.friends.blocked'),
                }.entries)
                  StarBridgeMenuEntry(
                    id: 'friends-section-${section.key}',
                    controlKey: ValueKey('friends-section-${section.key}'),
                    label: section.value,
                    onActivate: view.busy
                        ? null
                        : (_) => widget.onAction('section', '', section.key),
                    child: Text(section.value),
                  ),
              ],
              builder: (context, controller, focus, toggle) => BridgeMenuAction(
                focusNode: focus,
                key: ValueKey('friends-manage'),
                label: menuText(context, 'menu.overlay.friends.manage'),
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                onPressed: () => toggle(currentStarBridgeActivationSource),
                child: Text(
                  menuText(context, 'menu.overlay.friends.manageMenu'),
                  style: TextStyle(fontSize: 13, color: ink.blue),
                ),
              ),
            ),
          ],
        ),
        if (view.busy)
          BridgeCaption(menuText(context, 'menu.overlay.friends.busy')),
        if (view.feedback.isNotEmpty)
          BridgeCaption(key: _feedbackAnchor, switch (view.feedback) {
            'invalidSearch' => menuText(
              context,
              'menu.overlay.friends.invalidSearch',
            ),
            'expired' => menuText(context, 'menu.overlay.friends.expired'),
            'rejected' => menuText(context, 'menu.overlay.friends.rejected'),
            'unknown' => menuText(context, 'menu.overlay.friends.unknown'),
            'reviewed' => menuText(context, 'menu.overlay.friends.reviewed'),
            _ => menuText(context, 'menu.overlay.friends.completed', {
              'action': menuFriendActionLabel(
                context,
                view.feedback.replaceFirst('success.', ''),
              ),
            }),
          }),
        if (view.requiresRefresh)
          BridgeCaption(
            menuText(context, 'menu.overlay.friends.reviewRequired'),
          ),
        if (pending != null)
          Container(
            key: ValueKey('friends-confirmation'),
            margin: EdgeInsets.symmetric(vertical: 10),
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: ink.blue)),
            ),
            child: Column(
              key: _confirmationAnchor,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    menuText(context, 'menu.overlay.friends.confirm', {
                      'action': menuFriendActionLabel(context, pending.action),
                      'name': pending.name,
                    }),
                ),
                if (pending.action == 'remove')
                  BridgeCaption(
                    menuText(context, 'menu.overlay.friends.removeHint'),
                  ),
                if (pending.action == 'block')
                  BridgeCaption(
                    menuText(context, 'menu.overlay.friends.blockHint'),
                  ),
                Wrap(
                  children: [
                    action(
                      menuFriendActionLabel(context, pending.action),
                      'confirm',
                      key: pending.token,
                    ),
                    action(
                      menuText(context, 'menu.overlay.window.cancel'),
                      'dismiss',
                    ),
                  ],
                ),
              ],
            ),
          ),
        SizedBox(height: 12),
      ],
    );
  }
}
