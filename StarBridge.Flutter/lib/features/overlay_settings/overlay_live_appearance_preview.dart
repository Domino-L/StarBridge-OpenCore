import 'dart:async';

import 'package:flutter/material.dart';

import 'overlay_workspace_models.dart';
import 'overlay_workspace_port.dart';

Future<void> showOverlayLiveAppearancePreview(
  BuildContext context, {
  required String appearanceId,
  required OverlayAppearanceOptions options,
  required OverlayAppearancePreviewPort port,
  bool reduceMotion = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _LivePreview(
    appearanceId: appearanceId,
    options: options,
    port: port,
    reduceMotion: reduceMotion || MediaQuery.disableAnimationsOf(context),
  ),
);

class _LivePreview extends StatefulWidget {
  const _LivePreview({
    required this.appearanceId,
    required this.options,
    required this.port,
    required this.reduceMotion,
  });
  final String appearanceId;
  final OverlayAppearanceOptions options;
  final OverlayAppearancePreviewPort port;
  final bool reduceMotion;
  @override
  State<_LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<_LivePreview> {
  String? _session;
  bool _failed = false, _closing = false;
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final id = await widget.port.openAppearancePreview(
        widget.appearanceId,
        widget.options,
        reduceMotion: widget.reduceMotion,
      );
      if (!mounted) {
        await _cleanup(id);
        return;
      }
      setState(() => _session = id);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _cleanup(String id) async {
    try {
      await widget.port.closeAppearancePreview(id);
    } on Object {
      // Native lifetime owns cleanup too; its bounded expiry survives bridge loss.
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() {
      _closing = true;
      _failed = false;
    });
    try {
      if (_session case final id?) await widget.port.closeAppearancePreview(id);
      _session = null;
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _closing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_session case final id?) unawaited(_cleanup(id));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return AlertDialog(
      title: Text(zh ? '实时浮层预览' : 'Live overlay preview'),
      content: Text(
        _failed
            ? (_session == null
                  ? (zh
                        ? '预览未能打开。请关闭后重试。'
                        : 'Preview could not open. Close this dialog and try again.')
                  : (zh
                        ? '预览未能关闭。请重试，或在预览窗口按 Esc。'
                        : 'Preview could not close. Retry, or press Esc in the preview window.'))
            : _session == null
            ? (zh ? '正在打开独立预览窗口…' : 'Opening a separate preview window…')
            : (zh
                  ? '预览已在独立窗口打开。猫会自行活动，不需要操作。\n采用当前场景布置；不会保存、应用外观或读取你的消息。\n预览最多保持 10 分钟，可重新打开。'
                  : 'Preview is open in a separate window. The cat acts on its own.\nIt uses your current scene arrangement without saving, applying the appearance or reading your messages.\nPreview stays open for up to 10 minutes; you can open it again.'),
      ),
      actions: [
        TextButton(
          key: const Key('overlay-live-preview-close'),
          onPressed: _closing ? null : _close,
          child: Text(
            zh
                ? (_failed && _session != null ? '重试关闭' : '关闭预览')
                : (_failed && _session != null
                      ? 'Retry close'
                      : 'Close preview'),
          ),
        ),
      ],
    );
  }
}
