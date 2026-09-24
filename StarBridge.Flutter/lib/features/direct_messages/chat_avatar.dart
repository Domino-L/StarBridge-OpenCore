import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import '../common/user_avatar_menu.dart';

import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Peer avatars are bounded inline data from Host. Only the current SCM profile may supply HTTPS media.
class ChatAvatar extends StatefulWidget {
  const ChatAvatar({
    required this.label,
    this.source,
    this.allowProfileUrl = false,
    this.size = 36,
    this.isSelf = false,
    this.actions = const [],
    this.target,
    this.includeSocialActions = true,
    super.key,
  });
  final String label;
  final String? source;
  final bool allowProfileUrl;
  final double size;
  final bool isSelf;
  final List<AvatarMenuAction> actions;
  final UserTarget? target;
  final bool includeSocialActions;
  @override
  State<ChatAvatar> createState() => _ChatAvatarState();
}

class _ChatAvatarState extends State<ChatAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  void _evict() {
    final bytes = _bytes;
    if (bytes != null) {
      unawaited(ResizeImage.resizeIfNeeded(96, 96, MemoryImage(bytes)).evict());
    }
  }

  void _decode() {
    _bytes = null;
    final value = widget.source;
    if (value == null ||
        value.length > 128 * 1024 ||
        !(value.startsWith('data:image/png;base64,') ||
            value.startsWith('data:image/jpeg;base64,'))) {
      return;
    }
    try {
      _bytes = base64Decode(value.substring(value.indexOf(',') + 1));
    } on FormatException {
      // Invalid replacement data must never leave the previous avatar visible.
    }
  }

  @override
  void didUpdateWidget(covariant ChatAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _evict();
      _decode();
    }
  }

  @override
  void dispose() {
    _evict();
    _bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final label = widget.label;
    final isSelf = widget.isSelf;
    final actions = widget.actions;
    final allowProfileUrl = widget.allowProfileUrl;
    final fallback = StarBridgeIcon(
      StarBridgeIconSemantic.account,
      size: size * .65,
    );
    Widget picture = fallback;
    final value = widget.source;
    if (value != null) {
      if (_bytes != null) {
        try {
          picture = Image.memory(
            _bytes!,
            width: size,
            height: size,
            cacheWidth: 96,
            cacheHeight: 96,
            fit: BoxFit.cover,
            gaplessPlayback: false,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => fallback,
          );
        } on FormatException {
          picture = fallback;
        }
      } else if (allowProfileUrl && value.length <= 2048) {
        final uri = Uri.tryParse(value);
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty) {
          picture = Image.network(
            uri.toString(),
            key: ValueKey(value),
            width: size,
            height: size,
            cacheWidth: 96,
            cacheHeight: 96,
            fit: BoxFit.cover,
            gaplessPlayback: false,
            excludeFromSemantics: true,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : fallback,
            errorBuilder: (_, _, _) => fallback,
          );
        }
      }
    }
    return UserAvatarMenu(
      name: label,
      avatarImageData: widget.source,
      isSelf: isSelf,
      actions: actions,
      target: widget.target,
      includeSocialActions: widget.includeSocialActions,
      child: Semantics(
        label: label,
        image: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            color: context.tokens.colors.accent.withValues(alpha: .10),
            child: picture,
          ),
        ),
      ),
    );
  }
}
