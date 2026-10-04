import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/styles/overlay_preview_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import 'overlay_preview_background.dart';
import 'overlay_menu_trigger.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_editor_state.dart';
import 'overlay_workspace_layout_editor.dart';
import 'overlay_workspace_layout_geometry.dart';

class OverlayWorkspacePreviewStage extends StatefulWidget {
  const OverlayWorkspacePreviewStage({
    required this.projection,
    required this.module,
    required this.editor,
    this.fullscreenButton,
    super.key,
  });
  final OverlayWorkspaceProjection projection;
  final OverlayWorkspaceModule module;
  final OverlayWorkspaceEditorState editor;
  final Widget? fullscreenButton;
  @override
  State<OverlayWorkspacePreviewStage> createState() => _PreviewStageState();
}

class _PreviewStageState extends State<OverlayWorkspacePreviewStage> {
  final _transform = TransformationController();
  bool _actualSize = false, _picking = false;
  String _background = 'grid';
  Uint8List? _image;
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.editor.addListener(_focusSelected);
  }

  @override
  void dispose() {
    widget.editor.removeListener(_focusSelected);
    _transform.dispose();
    super.dispose();
  }

  void _focusSelected() {
    if (!_actualSize || _viewport.isEmpty) return;
    final key = widget.editor.selectedKey;
    final item = widget.projection.layout
        .where((item) => item.key == key)
        .firstOrNull;
    final center = item != null
        ? OverlayWorkspaceLayoutGeometry.resolve(item).center
        : key == 'Events'
        ? OverlayWorkspaceLayoutGeometry.resolveEventNotificationRect(
            surfaceWidth: 1920,
            surfaceHeight: 1080,
            side:
                widget.projection.settings!['eventNotificationSide'] as String,
            normalizedY:
                (widget.projection.settings!['eventNotificationY'] as num)
                    .toDouble(),
            preferredHeight: 90,
          ).center
        : const Offset(960, 540);
    final dx = (_viewport.width / 2 - center.dx).clamp(
      math.min(0.0, _viewport.width - 1920),
      0.0,
    );
    final dy = (_viewport.height / 2 - center.dy).clamp(
      math.min(0.0, _viewport.height - 1080),
      0.0,
    );
    _transform.value = Matrix4.translationValues(
      dx.toDouble(),
      dy.toDouble(),
      0,
    );
  }

  Future<void> _selectBackground(String value) async {
    if (value != 'image') {
      setState(() => _background = value);
      return;
    }
    setState(() => _picking = true);
    try {
      final bytes = await pickOverlayPreviewBackground();
      if (mounted && bytes != null) {
        setState(() {
          _image = bytes;
          _background = 'image';
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_copy(context, 'overlay.preview.imageFailed')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final canvas = OverlayWorkspaceInteractivePreview(
      module: widget.module,
      editor: widget.editor,
      selectionOnly: true,
      showGrid: _background == 'grid',
      background: switch (_background) {
        'space' => const CustomPaint(painter: _SpacePainter()),
        'image' when _image != null => Image.memory(
          _image!,
          fit: BoxFit.cover,
          cacheWidth: 1920,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        _ => null,
      },
    );
    return StarBridgeSurface(
      key: const Key('overlay-preview-stage'),
      role: SurfaceRole.panel,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _copy(context, 'overlay.preview.stageTitle'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Material(
                  type: MaterialType.transparency,
                  child: PopupMenuButton<String>(
                    key: const Key('overlay-preview-background'),
                    enabled: !_picking,
                    tooltip: _copy(context, 'overlay.preview.background'),
                    onSelected: _selectBackground,
                    itemBuilder: (context) => [
                      for (final value in ['grid', 'space', 'image'])
                        PopupMenuItem(
                          value: value,
                          child: Text(
                            _copy(context, 'overlay.preview.background.$value'),
                          ),
                        ),
                    ],
                    child: OverlayMenuTrigger(
                      enabled: !_picking,
                      label: _copy(
                        context,
                        'overlay.preview.background.$_background',
                      ),
                    ),
                  ),
                ),
                OutlinedButton(
                  key: const Key('overlay-preview-zoom'),
                  onPressed: () {
                    setState(() => _actualSize = !_actualSize);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _focusSelected();
                    });
                  },
                  child: Text(
                    _actualSize
                        ? '100%'
                        : _copy(context, 'overlay.preview.fit'),
                  ),
                ),
                if (widget.fullscreenButton != null) widget.fullscreenButton!,
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewport = constraints.biggest;
                  if (_actualSize) {
                    return ClipRect(
                      child: InteractiveViewer(
                        key: const Key('overlay-preview-actual-size'),
                        transformationController: _transform,
                        constrained: false,
                        scaleEnabled: false,
                        minScale: 1,
                        maxScale: 1,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 1920,
                          height: 1080,
                          child: canvas,
                        ),
                      ),
                    );
                  }
                  final width = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight * 16 / 9,
                  );
                  return Center(
                    child: SizedBox(
                      width: width,
                      height: width * 9 / 16,
                      child: canvas,
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _copy(
                context,
                widget.projection.dirty
                    ? 'overlay.preview.draft'
                    : 'overlay.preview.saved',
              ),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deterministic, original neutral star field; no game imagery or network data.
class _SpacePainter extends CustomPainter {
  const _SpacePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: overlayPreviewSpaceColors,
        ).createShader(rect),
    );
    final random = math.Random(417);
    for (var i = 0; i < 140; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .4 + random.nextDouble() * .7,
        Paint()
          ..color = Color.fromRGBO(
            180,
            204,
            222,
            .15 + random.nextDouble() * .4,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_SpacePainter oldDelegate) => false;
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
