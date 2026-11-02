import '../../design_system/icons/standard_icon.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../friends/friends_module.dart';
import 'user_interaction.dart';
import 'user_profile_page.dart';
import 'social_read_activity.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

export 'user_interaction.dart' show UserTarget;

import '../../app/localization/app_strings.dart';
import '../../app/routing/open_destination_intent.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

/// Callers supply only actions backed by their current account-scoped targets.
/// Display names and avatar URLs are never used as user identifiers.
class AvatarMenuAction {
  const AvatarMenuAction(this.label, this.onPressed, {this.color});
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
}

class UserAvatarMenu extends StatefulWidget {
  const UserAvatarMenu({
    required this.name,
    required this.child,
    this.isSelf = false,
    this.onViewProfile,
    this.target,
    this.includeSocialActions = true,
    this.includeNameInHint = false,
    this.avatarImageData,
    this.avatarBytes,
    this.actions = const [],
    super.key,
  });
  final String name;
  final Widget child;
  final bool isSelf;
  final VoidCallback? onViewProfile;
  final UserTarget? target;
  final bool includeSocialActions;

  /// For compact identity-only anchors: one bubble conveys both the person's
  /// name and the menu action, rather than two nested hints at one position.
  final bool includeNameInHint;
  final String? avatarImageData;
  final Uint8List? avatarBytes;
  final List<AvatarMenuAction> actions;

  @override
  State<UserAvatarMenu> createState() => _UserAvatarMenuState();
}

class _UserAvatarMenuState extends State<UserAvatarMenu> {
  FriendRow? social;
  bool loading = false, busy = false;
  InteractionSource _readSource = InteractionSource.programmatic;
  int epoch = 0;
  int _menuRevision = 0;

  /// The portrait keeps its element when the menu scope is re-keyed for a
  /// renewed target (user report 2026-10-29: avatars reloading in an idle
  /// chat whenever the access reference changed).
  final _portrait = GlobalKey();
  StreamSubscription<void>? subscription;
  UserInteractionPort? boundPort;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final port = UserInteractionScope.maybeOf(context)?.port;
    if (identical(boundPort, port)) return;
    epoch++;
    _menuRevision++;
    social = null;
    loading = false;
    busy = false;
    subscription?.cancel();
    boundPort = port;
    subscription = port?.invalidations.listen((_) {
      epoch++;
      _menuRevision++;
      if (mounted) {
        setState(() {
          social = null;
          loading = false;
          busy = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(UserAvatarMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target?.reference != widget.target?.reference ||
        oldWidget.target?.source != widget.target?.source ||
        oldWidget.target?.contextRef != widget.target?.contextRef ||
        oldWidget.isSelf != widget.isSelf ||
        oldWidget.includeSocialActions != widget.includeSocialActions) {
      epoch++;
      _menuRevision++;
      social = null;
      loading = false;
      busy = false;
    }
  }

  @override
  void dispose() {
    epoch++;
    subscription?.cancel();
    super.dispose();
  }

  Future<void> loadSocial(InteractionSource source) async {
    final target = widget.target, port = boundPort;
    if (widget.isSelf ||
        !widget.includeSocialActions ||
        target == null ||
        port == null ||
        busy) {
      return;
    }
    final current = ++epoch;
    setState(() {
      _readSource = source;
      loading = true;
      social = null;
    });
    FriendRow? result;
    try {
      result = await port.social(target);
    } on Object {
      /* Current menu remains usable for profile reads. */
    }
    if (!mounted || current != epoch) return;
    setState(() {
      social = result;
      loading = false;
    });
  }

  Future<void> execute(String action, FriendRow row) async {
    final port = boundPort, ref = row.targetRef;
    if (port == null || ref == null || busy) return;
    final current = epoch;
    setState(() => busy = true);
    FriendCommandResult result;
    try {
      result = await port.execute(action, ref);
    } on Object {
      result = const FriendCommandResult('unknown', error: 'outcomeUnknown');
    }
    if (!mounted || current != epoch) return;
    setState(() {
      busy = false;
      social = null;
    });
    final strings = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      starBridgeTimedSnackBar(
        content: Text(
          strings.text(
            result.status == 'accepted'
                ? 'friends.success.$action'
                : 'friends.error.${result.error ?? 'unavailable'}',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scope = UserInteractionScope.maybeOf(context);
    final isSelf = widget.isSelf || social?.relationship == 'self';
    final target = widget.target;
    final onViewProfile =
        widget.onViewProfile ??
        (target != null && scope?.port != null && scope?.navigation.open != null
            ? () => unawaited(
                scope!.navigation.open!(
                  context,
                  (_) => UserProfilePage(
                    port: scope.port!,
                    target: target,
                    avatarImageData:
                        widget.avatarImageData ??
                        _inlineAvatar(widget.avatarBytes),
                  ),
                  'navigation.profile',
                ),
              )
            : null);
    final actions = widget.actions;
    const ownProfile = OpenDestinationIntent('/profile');
    final canOpenSelf =
        isSelf &&
        (scope?.navigation.openSelf != null ||
            Actions.maybeFind<OpenDestinationIntent>(context) != null);
    StarBridgeMenuEntry entry(
      Object id,
      String label,
      FutureOr<void> Function()? callback, {
      Widget? icon,
      Color? color,
    }) => StarBridgeMenuEntry(
      id: id,
      label: label,
      onActivate: callback == null
          ? null
          : (source) =>
                unawaited(runStarBridgeActivation<void>(source, callback)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              style: color == null ? null : TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
    final customIds = <String, int>{};
    Object customId(AvatarMenuAction action) => (
      'avatar-custom',
      action.label,
      customIds.update(action.label, (count) => count + 1, ifAbsent: () => 0),
    );
    return NativeViewportMenu(
      key: ValueKey(('avatar-menu-scope', _menuRevision)),
      builder: (onOpen, onClose) => StarBridgeMenuAnchor(
        semanticLabel: strings.text('avatar.menu'),
        semanticHint: widget.name,
        maximumSize: const Size(320, 480),
        onOpen: onOpen,
        onOpenWithSource: (source) => unawaited(loadSocial(source)),
        onClose: onClose,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(height: 16),
              if (!canOpenSelf && (isSelf || onViewProfile == null))
                SizedBox(
                  width: 250,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      strings.text('avatar.profileUnavailable'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              if (loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SocialReadActivity(
                    key: ValueKey(('avatar-social-read', epoch)),
                    source: _readSource,
                    opening: false,
                    label: strings.text('friends.loading'),
                    height:
                        ProgressIndicatorTheme.of(context).linearMinHeight ?? 4,
                  ),
                ),
            ],
          ),
        ),
        entries: [
          entry(
            'avatar-view-profile',
            strings.text(isSelf ? 'navigation.profile' : 'avatar.viewProfile'),
            canOpenSelf
                ? () async {
                    if (!context.mounted) return;
                    if (scope?.navigation.openSelf != null) {
                      await scope!.navigation.openSelf!(context);
                    } else {
                      Actions.invoke(context, ownProfile);
                    }
                  }
                : isSelf
                ? null
                : onViewProfile,
            icon: const StandardIcon(
              StandardIconSemantic.accountCircle,
              size: 18,
            ),
          ),
          if (social case final row? when !isSelf) ...[
            if (row.chatTargetRef != null &&
                scope?.messagePage != null &&
                scope?.navigation.open != null &&
                !actions.any(
                  (a) => a.label == strings.text('avatar.sendMessage'),
                ))
              entry(
                'avatar-send-message',
                strings.text('avatar.sendMessage'),
                busy
                    ? null
                    : () => scope!.navigation.open!(
                        context,
                        (pageContext) => scope.messagePage!(
                          row,
                          () => Navigator.of(pageContext).pop(),
                        ),
                        'direct.title',
                      ),
                icon: const StandardIcon(
                  StandardIconSemantic.chatBubble,
                  size: 18,
                ),
              ),
            for (final action in row.actions.where(
              (a) => const ['send', 'accept', 'reject', 'cancel'].contains(a),
            ))
              entry(
                ('avatar-social', action),
                strings.text('friends.action.$action'),
                busy ? null : () => execute(action, row),
              ),
          ],
          for (final action in actions)
            entry(
              customId(action),
              action.label,
              action.onPressed == null
                  ? null
                  : () {
                      if (context.mounted) action.onPressed!();
                    },
              color: action.color,
            ),
        ],
        builder: (context, controller, focus, toggle) => StarBridgeTooltip(
          message: widget.includeNameInHint
              ? '${widget.name} · ${strings.text('avatar.menu')}'
              : strings.text('avatar.menu'),
          child: StarBridgeActionRow(
            controlKey: const Key('user-avatar-menu-anchor'),
            focusNode: focus,
            onActivate: (_, source) => toggle(source),
            child: KeyedSubtree(key: _portrait, child: widget.child),
          ),
        ),
      ),
    );
  }
}

String? _inlineAvatar(Uint8List? bytes) {
  if (bytes == null || bytes.length > 512 * 1024) return null;
  final png =
      bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10;
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255;
  if (!png && !jpeg) return null;
  return 'data:image/${png ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}';
}
