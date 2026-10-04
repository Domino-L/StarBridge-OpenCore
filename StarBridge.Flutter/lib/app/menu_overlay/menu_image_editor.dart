import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/icons/image_tool_icon.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import 'menu_bridge_style.dart';
import 'menu_image_edit.dart';
import 'menu_crop_viewport.dart';
import 'menu_local_tools.dart' show MenuLocalToolsController;
import 'menu_screenshot_actions.dart';
import 'menu_workspace_controller.dart';
import 'menu_workspace_viewport.dart';
import '../localization/app_strings.dart';

import 'menu_image_pin.dart';

/// Local image workspace. No file paths or account data enter the surface.
class MenuImageTool extends StatefulWidget {
  const MenuImageTool({
    super.key,
    required this.tools,
    this.capture = false,
    this.workspace,
  });
  final MenuLocalToolsController tools;
  final bool capture;
  final MenuWorkspaceController? workspace;
  @override
  State<MenuImageTool> createState() => _MenuImageToolState();
}

class _MenuImageToolState extends State<MenuImageTool>
    with MenuImagePinLifecycle<MenuImageTool> {
  @override
  bool get capturesScreenshot => widget.capture;
  @override
  MenuWorkspaceController? get imageWorkspace => widget.workspace;
  @override
  final viewport = GlobalKey();
  final screenshotTransform = TransformationController();
  Uint8List? measuredBytes;
  Size? dimensions;
  Rect? selection;
  @override
  bool cropping = false;
  bool regionZoom = false;
  @override
  bool imageReady = false;
  bool updatingScale = false;
  double actualScale = 1;
  bool hovered = false;

  @override
  MenuLocalToolsController get tools => widget.tools;
  TransformationController get transform =>
      widget.capture ? screenshotTransform : tools.referenceTransform;

  @override
  void initState() {
    super.initState();
    tools.referenceTransform.addListener(_transformed);
    widget.workspace?.addListener(queuePreparedReferencePin);
    tools.addListener(queuePreparedReferencePin);
    if (!widget.capture && widget.workspace != null) {
      unawaited(
        tools
            .call('imagePinState', const {})
            .then((value) {
              if (mounted && !tools.closed && value is bool) {
                setState(() => tools.pinned = value);
              }
            })
            .catchError((_) {}),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MenuImageTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace?.removeListener(queuePreparedReferencePin);
      widget.workspace?.addListener(queuePreparedReferencePin);
    }
    if (oldWidget.tools != tools) {
      oldWidget.tools.referenceTransform.removeListener(_transformed);
      oldWidget.tools.removeListener(queuePreparedReferencePin);
      tools.referenceTransform.addListener(_transformed);
      tools.addListener(queuePreparedReferencePin);
      preparedSerial = -1;
      screenshotTransform.value = Matrix4.identity();
      measuredBytes = null;
      dimensions = null;
      imageReady = false;
      cropping = capturingFrame = false;
      selection = null;
      actualScale = 1;
      autoPinQueued = false;
      autoPinEpoch++;
    }
  }

  void _transformed() {
    if (!widget.capture) {
      if (!updatingScale) tools.referenceScaleMode = null;
      tools.markPinDirty();
      queuePreparedReferencePin();
    }
  }

  void _movePureImage(ScaleUpdateDetails details) {
    final workspace = widget.workspace;
    final size = MenuWorkspaceViewport.sizeOf(context);
    if (!tools.referenceImageOnly ||
        workspace == null ||
        size == null ||
        details.pointerCount != 1 ||
        details.scale != 1) {
      return;
    }
    for (final lease in workspace.openPanels) {
      if (lease.id != 'image') continue;
      workspace.moveTo(
        lease,
        workspace.boundsFor('image', size).topLeft + details.focalPointDelta,
        size,
      );
      break;
    }
  }

  void _syncReferenceScale() {
    if (widget.capture || dimensions == null || tools.reference == null) return;
    final owner = tools, revision = owner.revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(tools, owner) ||
          owner.closed ||
          cropping ||
          owner.revision != revision) {
        return;
      }
      final box = viewport.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || dimensions == null) return;
      final nextActual = menuReferenceActualScale(
        dimensions!,
        box.size,
        physicalReferenceViewport(box).width / box.size.width,
        tools.referenceDisplayTurns,
      );
      if (nextActual == null) return;
      final mode = tools.referenceScaleMode;
      final center = box.size.center(Offset.zero);
      final scale = mode == 'actualSize' ? nextActual : 1.0;
      final matrix = Matrix4.identity()
        ..translateByDouble(center.dx, center.dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1)
        ..translateByDouble(-center.dx, -center.dy, 0, 1);
      if (mode != null && transform.value != matrix) {
        updatingScale = true;
        try {
          transform.value = matrix;
        } finally {
          updatingScale = false;
        }
      }
      if (actualScale != nextActual) setState(() => actualScale = nextActual);
    });
  }

  @override
  void dispose() {
    widget.workspace?.removeListener(queuePreparedReferencePin);
    tools.removeListener(queuePreparedReferencePin);
    if (!widget.capture && !tools.closed) {
      // Closing the image itself cancels staging. Once the whole menu is
      // hidden native authority rejects this call; its confirmed pin survives.
      unawaited(
        tools.call('imageCancelPreparedPin', const {}).catchError((_) => null),
      );
    }
    tools.referenceTransform.removeListener(_transformed);
    screenshotTransform.dispose();
    super.dispose();
  }

  void _measure(Uint8List? bytes) {
    if (identical(bytes, measuredBytes)) return;
    measuredBytes = bytes;
    imageReady = false;
    dimensions = bytes == null ? null : menuPngSize(bytes);
    selection = null;
    cropping = false;
  }

  Widget _button(
    String title,
    Widget icon,
    VoidCallback? action, {
    bool selected = false,
  }) => OutlinedButton.icon(
    onPressed: tools.busy || capturingFrame ? null : action,
    icon: icon,
    label: Text(title),
    style: selected
        ? OutlinedButton.styleFrom(foregroundColor: BridgeInk.blue)
        : null,
  );

  void _zoom(double factor) {
    final box = viewport.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final current = transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(
      widget.capture ? .2 : math.min(.2, actualScale),
      widget.capture ? 8.0 : math.max(8.0, actualScale),
    );
    final f = next / current, c = box.size.center(Offset.zero);
    transform.value = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(f, f, f, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1)
      ..multiply(transform.value);
    setState(() {});
  }

  Future<void> _applyCrop() async {
    final crop = selection;
    if (crop == null) return;
    if (regionZoom) {
      final owner = tools, revision = tools.revision;
      setState(() {
        cropping = false;
        selection = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !identical(tools, owner) ||
            owner.closed ||
            owner.busy ||
            cropping ||
            owner.revision != revision) {
          return;
        }
        final box = viewport.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || dimensions == null) return;
        final view = menuImageRegionView(
          dimensions!,
          box.size,
          widget.capture ? 0 : owner.referenceDisplayTurns,
          crop,
          widget.capture ? 8 : math.max(8, actualScale),
        );
        if (view == null) return;
        final center = box.size.center(Offset.zero);
        transform.value = Matrix4.identity()
          ..translateByDouble(center.dx, center.dy, 0, 1)
          ..scaleByDouble(view.scale, view.scale, view.scale, 1)
          ..translateByDouble(-view.center.dx, -view.center.dy, 0, 1);
        setState(() {});
      });
      return;
    }
    final owner = tools;
    final edit = (widget.capture ? owner.screenshotEdit : owner.referenceEdit)
        .select(crop);
    if (edit != null) {
      if (widget.capture) {
        await owner.editScreenshot(edit);
      } else {
        await owner.editReference(edit);
      }
      if (mounted &&
          identical(tools, owner) &&
          (widget.capture ? owner.screenshotEdit : owner.referenceEdit) ==
              edit) {
        setState(() {
          cropping = false;
          selection = null;
        });
      }
    }
  }

  List<Widget> _editButtons(bool available, String Function(String) text) => [
    _button(
      text(cropping && !regionZoom ? 'cancelCrop' : 'crop'),
      const ImageToolIcon(ImageToolGlyph.crop),
      available && dimensions != null
          ? () => setState(() {
              cropping = !cropping || regionZoom;
              regionZoom = false;
              selection = null;
            })
          : null,
      selected: cropping && !regionZoom,
    ),
    if (!widget.capture)
      _button(
        text(cropping && regionZoom ? 'cancelRegion' : 'regionZoom'),
        const StarBridgeIcon(StarBridgeIconSemantic.windowMaximize, size: 16),
        available && dimensions != null
            ? () => setState(() {
                cropping = !cropping || !regionZoom;
                regionZoom = true;
                selection = null;
              })
            : null,
        selected: cropping && regionZoom,
      ),
    if (cropping)
      _button(
        text(regionZoom ? 'applyRegion' : 'applyCrop'),
        const StandardIcon(StandardIconSemantic.checkCircle, size: 16),
        selection == null ? null : _applyCrop,
      ),
    _button(
      text('undo'),
      const StarBridgeIcon(StarBridgeIconSemantic.undo, size: 16),
      !cropping && (widget.capture ? tools.canUndo : tools.canUndoReference)
          ? widget.capture
                ? tools.undoScreenshot
                : tools.undoReference
          : null,
    ),
    _button(
      text('reset'),
      const StandardIcon(StandardIconSemantic.history, size: 16),
      available && !cropping
          ? () => widget.capture
                ? tools.editScreenshot(const MenuImageEdit())
                : tools.editReference(const MenuImageEdit())
          : null,
    ),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tools,
    builder: (context, _) {
      final bytes = widget.capture
          ? tools.screenshotPreview ?? tools.screenshot
          : tools.referencePreview ?? tools.reference;
      _measure(bytes);
      checkReferencePinPosition();
      if (!cropping) _syncReferenceScale();
      queueDefaultReferencePin();
      queuePreparedReferencePin();
      final available = bytes != null;
      final imageOnly =
          !widget.capture && available && tools.referenceImageOnly;
      String imageText(String key) =>
          AppStrings.of(context).text('menu.image.$key');
      String shotText(String key) =>
          AppStrings.of(context).text('menu.screenshot.$key');
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            // Keep the image viewport unchanged when switching presentation.
            // Visibility also removes hidden tools from focus and hit testing.
            Visibility(
              visible: !imageOnly,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .48,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _button(
                              widget.capture
                                  ? shotText(
                                      available ? 'recapture' : 'capture',
                                    )
                                  : '选择图片',
                              widget.capture
                                  ? const MenuGlyphView(
                                      MenuGlyph.camera,
                                      size: 16,
                                    )
                                  : const MenuGlyphView(
                                      MenuGlyph.image,
                                      size: 16,
                                    ),
                              () => tools.image(capture: widget.capture),
                            ),
                            if (widget.capture) ...[
                              ...screenshotExportActions(
                                context,
                                tools,
                                available: available,
                                blocked: cropping,
                                button: (label, icon, action) =>
                                    _button(label, icon, action),
                              ),
                            ] else ...[
                              _button(
                                imageText('hideTools'),
                                const ImageToolIcon(ImageToolGlyph.crop),
                                available && !cropping
                                    ? () => tools.referenceView(imageOnly: true)
                                    : null,
                              ),
                              _button(
                                tools.pinned ? '更新固定画面' : '固定到游戏',
                                const ImageToolIcon(ImageToolGlyph.pin),
                                available && !cropping ? pinReference : null,
                                selected: tools.pinned,
                              ),
                              if (tools.pinned)
                                _button(
                                  '取消固定',
                                  const MenuGlyphView(
                                    MenuGlyph.close,
                                    size: 16,
                                  ),
                                  () => tools.clear(unpinOnly: true),
                                ),
                            ],
                            ..._editButtons(available, imageText),
                            _button(
                              widget.capture
                                  ? shotText('clearPreview')
                                  : '清除预览',
                              const StandardIcon(
                                StandardIconSemantic.delete,
                                size: 16,
                              ),
                              available && !cropping
                                  ? () => tools.clear(capture: widget.capture)
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _button(
                              widget.capture ? shotText('fit') : '适合窗口',
                              const StarBridgeIcon(
                                StarBridgeIconSemantic.windowMaximize,
                                size: 16,
                              ),
                              available && !cropping
                                  ? () {
                                      if (widget.capture) {
                                        transform.value = Matrix4.identity();
                                      } else {
                                        tools.referenceView(mode: 'fit');
                                      }
                                      setState(() {});
                                    }
                                  : null,
                            ),
                            if (!widget.capture)
                              _button(
                                imageText('actualSize'),
                                const StarBridgeIcon(
                                  StarBridgeIconSemantic.windowMaximize,
                                  size: 16,
                                ),
                                available && !cropping && dimensions != null
                                    ? () => tools.referenceView(
                                        mode: 'actualSize',
                                      )
                                    : null,
                                selected:
                                    tools.referenceScaleMode == 'actualSize',
                              ),
                            _button(
                              widget.capture ? shotText('zoomOut') : '缩小',
                              const StarBridgeIcon(
                                StarBridgeIconSemantic.remove,
                                size: 16,
                              ),
                              available && !cropping ? () => _zoom(.8) : null,
                            ),
                            _button(
                              widget.capture ? shotText('zoomIn') : '放大',
                              const StarBridgeIcon(
                                StarBridgeIconSemantic.add,
                                size: 16,
                              ),
                              available && !cropping ? () => _zoom(1.25) : null,
                            ),
                            _button(
                              widget.capture ? shotText('rotate') : '旋转',
                              const ImageToolIcon(ImageToolGlyph.rotate),
                              available && !cropping
                                  ? () {
                                      if (widget.capture) {
                                        unawaited(
                                          tools.editScreenshot(
                                            tools.screenshotEdit.rotate(),
                                          ),
                                        );
                                      } else {
                                        tools.referenceChanged(
                                          turns: (tools.referenceTurns + 1) % 4,
                                          fit: true,
                                        );
                                      }
                                    }
                                  : null,
                            ),
                            if (dimensions != null)
                              Text(
                                '${dimensions!.width.toInt()} × ${dimensions!.height.toInt()}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        if (!widget.capture)
                          Row(
                            children: [
                              Text(
                                '${imageText('opacityValue')} ${(tools.referenceOpacity * 100).round()}%',
                              ),
                              Expanded(
                                child: Slider(
                                  value: tools.referenceOpacity,
                                  min: .15,
                                  onChanged:
                                      !available || tools.busy || capturingFrame
                                      ? null
                                      : (v) =>
                                            tools.referenceChanged(opacity: v),
                                ),
                              ),
                            ],
                          ),
                        if (!widget.capture && available && !cropping)
                          Text(
                            imageText('editHint'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: BridgeInk.muted),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 2,
              child: tools.busy || capturingFrame
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
            Visibility(
              visible: !imageOnly,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: ConstrainedBox(
                constraints: BoxConstraints.tightFor(
                  height: math.min(48, constraints.maxHeight * .22),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    child: Text(
                      tools.notice.isNotEmpty
                          ? tools.notice
                          : widget.capture &&
                                tools.screenshotNoticeKey.isNotEmpty
                          ? shotText(tools.screenshotNoticeKey)
                          : !widget.capture &&
                                tools.referenceNoticeKey.isNotEmpty
                          ? imageText(tools.referenceNoticeKey)
                          : widget.capture
                          ? (cropping
                                ? imageText('cropHint')
                                : shotText('previewHint'))
                          : cropping
                          ? imageText(regionZoom ? 'regionHint' : 'cropHint')
                          : tools.pinDirty
                          ? '调整尚未应用到游戏，请点击“更新固定画面”。'
                          : tools.pinned
                          ? '仅在 Star Citizen 前台显示，鼠标可穿透。关闭此编辑窗口不会取消固定。'
                          : '滚轮缩放、拖动查看；固定后可在游戏中对照。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: MouseRegion(
                onEnter: (_) => setState(() => hovered = true),
                onExit: (_) => setState(() => hovered = false),
                child: GestureDetector(
                  key: const ValueKey('reference-image-viewport'),
                  onDoubleTap:
                      !widget.capture && available && !cropping && !tools.busy
                      ? () => tools.referenceView(
                          imageOnly: !tools.referenceImageOnly,
                        )
                      : null,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: imageOnly
                          ? Colors.transparent
                          : MenuBridgeColors.of(context).ground,
                      border: imageOnly
                          ? null
                          : Border(
                              top: BorderSide(
                                color: MenuBridgeColors.of(context).divider,
                              ),
                            ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          key: viewport,
                          child: AbsorbPointer(
                            absorbing: tools.busy || capturingFrame,
                            child: ClipRect(
                              child: bytes == null
                                  ? const SizedBox.expand()
                                  : cropping && dimensions != null
                                  ? MenuCropViewport(
                                      bytes: bytes,
                                      size: dimensions!,
                                      turns: widget.capture
                                          ? 0
                                          : tools.referenceDisplayTurns,
                                      busy: tools.busy,
                                      selection: selection,
                                      onSelection: (rect) =>
                                          setState(() => selection = rect),
                                      onCancel: () => setState(() {
                                        cropping = false;
                                        selection = null;
                                      }),
                                      hint: imageText(
                                        regionZoom ? 'regionHint' : 'cropHint',
                                      ),
                                    )
                                  : InteractiveViewer(
                                      transformationController: transform,
                                      panEnabled:
                                          !imageOnly ||
                                          widget.workspace == null,
                                      onInteractionUpdate: imageOnly
                                          ? _movePureImage
                                          : null,
                                      minScale: widget.capture
                                          ? .2
                                          : math.min(.2, actualScale),
                                      maxScale: widget.capture
                                          ? 8
                                          : math.max(8, actualScale),
                                      onInteractionEnd: (_) {
                                        if (mounted) setState(() {});
                                      },
                                      child: SizedBox.expand(
                                        child: Opacity(
                                          opacity: widget.capture
                                              ? 1
                                              : tools.referenceOpacity,
                                          child: RotatedBox(
                                            quarterTurns: widget.capture
                                                ? 0
                                                : tools.referenceDisplayTurns,
                                            child: Image.memory(
                                              bytes,
                                              fit: BoxFit.contain,
                                              gaplessPlayback: true,
                                              frameBuilder: (_, child, frame, sync) {
                                                imageReady =
                                                    sync || frame != null;
                                                if (imageReady &&
                                                    identical(
                                                      bytes,
                                                      tools.referencePreview ??
                                                          tools.reference,
                                                    )) {
                                                  queueDefaultReferencePin();
                                                  queuePreparedReferencePin();
                                                }
                                                return child;
                                              },
                                              errorBuilder: (_, _, _) =>
                                                  const Center(
                                                    child: Text(
                                                      '无法显示这张图片，请重新选择。',
                                                    ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        if (!available)
                          Center(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  widget.capture
                                      ? '截取菜单所在屏幕，再预览、裁剪或保存。'
                                      : '选择一张本机图片作为参考。\n图片不会上传，也不会随应用重启恢复。',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        if (imageOnly && (hovered || pinPreparationFailed))
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: IgnorePointer(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: BridgeInk.window.withValues(
                                      alpha: .88,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      tools.notice.isNotEmpty
                                          ? tools.notice
                                          : imageText('pureHint'),
                                      key: const ValueKey(
                                        'reference-image-hover-hint',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: BridgeInk.muted),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
