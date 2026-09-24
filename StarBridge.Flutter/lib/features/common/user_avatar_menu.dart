import '../../design_system/icons/standard_icon.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../friends/friends_module.dart';
import 'user_interaction.dart';
import 'user_profile_page.dart';
export 'user_interaction.dart' show UserTarget;

import '../../app/localization/app_strings.dart';
import '../../app/routing/open_destination_intent.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/native_viewport_visibility.dart';

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
  final String? avatarImageData;
  final Uint8List? avatarBytes;
  final List<AvatarMenuAction> actions;

  @override
  State<UserAvatarMenu> createState() => _UserAvatarMenuState();
}

class _UserAvatarMenuState extends State<UserAvatarMenu> {
  FriendRow? social;
  bool loading = false, busy = false;
  int epoch = 0;
  StreamSubscription<void>? subscription;
  UserInteractionPort? boundPort;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final port = UserInteractionScope.maybeOf(context)?.port;
    if (identical(boundPort, port)) return;
    subscription?.cancel();
    boundPort = port;
    subscription = port?.invalidations.listen((_) {
      epoch++;
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
    if (oldWidget.target?.reference != widget.target?.reference) {
      epoch++;
      social = null;
      loading = false;
    }
  }

  @override
  void dispose() {
    epoch++;
    subscription?.cancel();
    super.dispose();
  }

  Future<void> loadSocial() async {
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
      SnackBar(
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
    final tokens = context.tokens;
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
    return NativeViewportMenu(
      builder: (onOpen, onClose) => MenuAnchor(
        onOpen: () {
          onOpen();
          unawaited(loadSocial());
        },
        onClose: onClose,
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            tokens.surfaces.floating.fill,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(
            BorderSide(color: tokens.surfaces.floating.border),
          ),
          maximumSize: const WidgetStatePropertyAll(Size(320, 480)),
        ),
        menuChildren: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              widget.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: canOpenSelf
                ? () {
                    if (!context.mounted) return;
                    if (scope?.navigation.openSelf != null) {
                      unawaited(scope!.navigation.openSelf!(context));
                    } else {
                      Actions.invoke(context, ownProfile);
                    }
                  }
                : isSelf
                ? null
                : onViewProfile,
            leadingIcon: const StandardIcon(StandardIconSemantic.accountCircle, size: 18),
            child: Text(
              strings.text(
                isSelf ? 'navigation.profile' : 'avatar.viewProfile',
              ),
            ),
          ),
          if (!canOpenSelf && (isSelf || onViewProfile == null))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SizedBox(
                width: 250,
                child: Text(
                  strings.text('avatar.profileUnavailable'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          if (social case final row? when !isSelf) ...[
            if (row.chatTargetRef != null &&
                scope?.messagePage != null &&
                scope?.navigation.open != null &&
                !actions.any(
                  (a) => a.label == strings.text('avatar.sendMessage'),
                ))
              MenuItemButton(
                leadingIcon: const StandardIcon(StandardIconSemantic.chatBubble, size: 18),
                onPressed: busy
                    ? null
                    : () => unawaited(
                        scope!.navigation.open!(
                          context,
                          (pageContext) => scope.messagePage!(
                            row,
                            () => Navigator.of(pageContext).pop(),
                          ),
                          'direct.title',
                        ),
                      ),
                child: Text(strings.text('avatar.sendMessage')),
              ),
            for (final action in row.actions.where(
              (a) => const ['send', 'accept', 'reject', 'cancel'].contains(a),
            ))
              MenuItemButton(
                onPressed: busy ? null : () => unawaited(execute(action, row)),
                child: Text(strings.text('friends.action.$action')),
              ),
          ],
          if (actions.isNotEmpty) const Divider(height: 1),
          for (final action in actions)
            MenuItemButton(
              onPressed: action.onPressed == null
                  ? null
                  : () {
                      if (context.mounted) action.onPressed!();
                    },
              style: action.color == null
                  ? null
                  : ButtonStyle(
                      foregroundColor: WidgetStatePropertyAll(action.color),
                    ),
              child: Text(action.label),
            ),
        ],
        builder: (context, controller, _) => Tooltip(
          message: strings.text('avatar.menu'),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: widget.child,
            ),
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
