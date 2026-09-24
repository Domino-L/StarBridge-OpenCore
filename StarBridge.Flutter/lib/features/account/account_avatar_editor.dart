import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../communities/community_logo_crop.dart';
import 'account_avatar.dart';

class AccountAvatarScope extends InheritedWidget {
  const AccountAvatarScope({
    required this.port,
    required this.imageData,
    required this.editable,
    required super.child,
    super.key,
  });
  final AccountAvatarPort? port;
  final String? imageData;
  final bool editable;
  static AccountAvatarScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountAvatarScope>();
  @override
  bool updateShouldNotify(AccountAvatarScope oldWidget) =>
      imageData != oldWidget.imageData ||
      editable != oldWidget.editable ||
      port != oldWidget.port;
}

class AccountAvatarEditor extends StatefulWidget {
  const AccountAvatarEditor({super.key});
  @override
  State<AccountAvatarEditor> createState() => _AccountAvatarEditorState();
}

class _AccountAvatarEditorState extends State<AccountAvatarEditor> {
  bool _busy = false;
  String? _message;

  Future<void> _choose(AccountAvatarPort port) async {
    final strings = AppStrings.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final source = await port.pickLogo();
      if (!mounted || source == null) return;
      final cropped = await showDialog<String>(
        context: context,
        builder: (_) => CommunityLogoCrop(port: port, source: source),
      );
      if (!mounted || cropped == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.text('profile.avatar.change')),
          content: Text(strings.text('profile.avatar.confirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.text('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.text('profile.avatar.change')),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await port.save(cropped);
      if (mounted) setState(() => _message = 'profile.avatar.saved');
    } catch (_) {
      if (mounted) setState(() => _message = 'profile.avatar.failed');
    } finally {
      try {
        await port.clearLogo();
      } catch (_) {
        /* Account invalidation clears native image buffers. */
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AccountAvatarScope.of(context);
    final strings = AppStrings.of(context);
    final port = scope?.port;
    final canEdit = scope?.editable == true && port?.canPickLogo == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.text(
            canEdit ? 'profile.avatar.shared' : 'profile.avatar.managed',
          ),
        ),
        const SizedBox(height: 8),
        if (canEdit)
          OutlinedButton(
            key: const Key('profile-change-account-avatar'),
            onPressed: _busy ? null : () => _choose(port!),
            child: Text(
              strings.text(
                _busy ? 'profile.avatar.saving' : 'profile.avatar.change',
              ),
            ),
          ),
        if (_message != null) Text(strings.text(_message!)),
      ],
    );
  }
}
