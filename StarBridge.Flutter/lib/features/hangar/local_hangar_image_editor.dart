import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../communities/community_logo_crop.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_images.dart';
import 'local_hangar_image_cache.dart';

import 'dart:typed_data';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

class LocalHangarImageEditor extends StatefulWidget {
  const LocalHangarImageEditor({
    required this.port,
    required this.onSaved,
    this.preserveImageOnPortChange = false,
    required this.fallback,
    this.editable = true,
    super.key,
  });
  final LocalHangarImagePort port;
  final VoidCallback onSaved;
  final Widget fallback;
  final bool editable;

  /// Only for a proven same owner and same instance whose metadata changed.
  /// The caller must recreate this state on owner or instance replacement.
  final bool preserveImageOnPortChange;
  @override
  State<LocalHangarImageEditor> createState() => _LocalHangarImageEditorState();
}

class _LocalHangarImageEditorState extends State<LocalHangarImageEditor> {
  String? _image, _message;
  String? _decodedValue;
  Uint8List? _decodedImage;
  bool _busy = false;
  int _imageEpoch = 0;
  final _children = <StarBridgeDialogRoute<dynamic>>{};
  int _flowEpoch = 0;

  void _retireChildren() {
    for (final route in _children.toList()) {
      retireStarBridgeDialog(route, includeClosing: true);
    }
    _children.clear();
  }

  @override
  void didUpdateWidget(LocalHangarImageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.port, widget.port)) {
      ++_flowEpoch;
      ++_imageEpoch;
      _retireChildren();
      if (!widget.preserveImageOnPortChange) _image = null;
      _message = null;
      unawaited(_read());
    } else if (oldWidget.editable && !widget.editable) {
      ++_flowEpoch;
      _retireChildren();
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final epoch = _imageEpoch;
    final port = widget.port;
    try {
      final image = await port.readImage();
      if (mounted && epoch == _imageEpoch) setState(() => _image = image);
    } catch (_) {
      if (mounted && epoch == _imageEpoch) setState(() => _message = 'read');
    }
  }

  Future<T?> _dialog<T>(WidgetBuilder builder) => showStarBridgeDialog<T>(
    context,
    builder: builder,
    onRouteCreated: (route) {
      _children.add(route);
      // A crop can still be reversing while confirmation opens. Retain both
      // exact routes until completed, so disposal cannot leave an orphan tail.
      unawaited(route.completed.then((_) => _children.remove(route)));
    },
  );

  Future<void> _choose() async {
    if (_busy || !mounted || !widget.editable || !widget.port.canPickLogo) {
      return;
    }
    final port = widget.port, epoch = ++_flowEpoch;
    bool current() =>
        mounted &&
        epoch == _flowEpoch &&
        widget.editable &&
        identical(widget.port, port) &&
        port.canPickLogo;
    ++_imageEpoch;
    final copy = LocalHangarCopy(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    var saving = false;
    try {
      final source = await port.pickLogo();
      if (!current() || source == null) return;
      final cropped = await _dialog<String>(
        (_) => CommunityLogoCrop(
          port: port,
          source: source,
          title: copy.pick('裁剪舰船图片', '裁切艦船圖片', 'Crop ship image'),
        ),
      );
      if (!current() || cropped == null) return;
      final confirmed = await _dialog<bool>(
        (context) => AlertDialog(
          title: Text(copy.pick('保存舰船图片', '儲存艦船圖片', 'Save ship image')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(
                base64Decode(cropped.split(',').last),
                width: 220,
                height: 220,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 12),
              Text(
                copy.pick(
                  '仅保存在这台电脑，不会上传或对外分享。',
                  '僅儲存在這台電腦，不會上傳或對外分享。',
                  'Saved only on this computer. This does not upload or share the image.',
                ),
              ),
            ],
          ),
          actions: [
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: const Key('hangar-image-cancel'),
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: false,
              ),
              child: Text(copy.pick('取消', '取消', 'Cancel')),
            ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.primary,
              controlKey: const Key('hangar-image-confirm'),
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: true,
              ),
              child: Text(copy.pick('保存到本机', '儲存到本機', 'Save locally')),
            ),
          ],
        ),
      );
      if (!current() || confirmed != true) return;
      saving = true;
      await port.saveImage();
      if (!current()) return;
      setState(() {
        _image = cropped;
        _message = 'saved';
      });
      widget.onSaved();
    } catch (_) {
      if (current()) setState(() => _message = saving ? 'uncertain' : 'choose');
    } finally {
      try {
        await port.clearLogo();
      } catch (_) {
        /* Account change clears native drafts. */
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    ++_flowEpoch;
    _retireChildren();
    super.dispose();
  }

  Future<void> _restore() async {
    if (_busy || !mounted || !widget.editable || !widget.port.canPickLogo) {
      return;
    }
    final port = widget.port, epoch = ++_flowEpoch;
    bool current() =>
        mounted &&
        epoch == _flowEpoch &&
        widget.editable &&
        identical(widget.port, port) &&
        port.canPickLogo;
    final c = LocalHangarCopy(context);
    setState(() => _busy = true);
    try {
      final confirmed = await _dialog<bool>(
        (context) => AlertDialog(
          title: Text(c.pick('恢复默认图片？', '恢復預設圖片？', 'Restore default image?')),
          content: Text(
            c.pick(
              '只移除这艘舰船在本机使用的自定义图片。不会删除原始文件，也不影响已分享的图片。',
              '只移除這艘艦船在本機使用的自訂圖片。不會刪除原始檔案，也不影響已分享的圖片。',
              'Remove this ship’s local custom image. The original file and any shared image are unchanged.',
            ),
          ),
          actions: [
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: const Key('hangar-image-restore-cancel'),
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: false,
              ),
              child: Text(c.pick('保留图片', '保留圖片', 'Keep image')),
            ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.primary,
              controlKey: const Key('hangar-image-restore-confirm'),
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: true,
              ),
              child: Text(c.pick('恢复默认图片', '恢復預設圖片', 'Restore default image')),
            ),
          ],
        ),
      );
      if (!current() || confirmed != true) return;
      ++_imageEpoch;
      await port.restoreImage();
      if (!current()) return;
      setState(() {
        _image = null;
        _message = 'restored';
      });
      widget.onSaved();
    } catch (_) {
      if (current()) setState(() => _message = 'uncertain');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context);
    if (_decodedValue != _image) {
      _decodedValue = _image;
      try {
        _decodedImage = LocalHangarImageCache.decode(_image);
      } catch (_) {
        _decodedImage = null;
      }
    }
    final message = switch (_message) {
      'saved' => c.pick('已保存到本机。', '已儲存到本機。', 'Saved locally.'),
      'restored' => c.pick('已恢复默认图片。', '已恢復預設圖片。', 'Default image restored.'),
      'uncertain' => c.pick(
        '暂时无法确认保存结果。请关闭详情并刷新机库后检查。',
        '暫時無法確認儲存結果。請關閉詳情並重新整理機庫後檢查。',
        'The save could not be confirmed. Close details and refresh your hangar to check.',
      ),
      'choose' => c.pick(
        '未保存图片，请重新选择。',
        '未儲存圖片，請重新選擇。',
        'Image not saved. Choose it again.',
      ),
      'read' => c.pick(
        '暂时无法读取自定义图片。请关闭详情并刷新后重试。',
        '暫時無法讀取自訂圖片。請關閉詳情並重新整理後重試。',
        'Custom image unavailable. Close details and refresh to retry.',
      ),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_decodedImage != null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.memory(
              _decodedImage!,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) => widget.fallback,
            ),
          )
        else
          widget.fallback,
        if (widget.editable && widget.port.canPickLogo)
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('hangar-image-choose'),
            onActivate: _busy
                ? null
                : (source) =>
                      unawaited(runStarBridgeActivation<void>(source, _choose)),
            child: Text(c.pick('选择舰船图片', '選擇艦船圖片', 'Choose ship image')),
          ),
        if (widget.editable &&
            widget.port.canPickLogo &&
            (_image != null || _message == 'read'))
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('hangar-image-restore'),
            onActivate: _busy
                ? null
                : (source) => unawaited(
                    runStarBridgeActivation<void>(source, _restore),
                  ),
            child: Text(c.pick('恢复默认图片', '恢復預設圖片', 'Restore default image')),
          ),
        if (message != null)
          Semantics(
            liveRegion: true,
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
