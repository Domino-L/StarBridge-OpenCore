import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'menu_local_tools.dart' show MenuLocalToolsController;
import 'menu_workspace_controller.dart';
import 'menu_workspace_viewport.dart';

// Frame preparation shares the image state and existing native pin owner.
// No additional storage, timer, or overlay lifecycle is introduced.
mixin MenuImagePinLifecycle<T extends StatefulWidget> on State<T> {
  MenuLocalToolsController get tools;
  GlobalKey get viewport;
  bool get capturesScreenshot;
  MenuWorkspaceController? get imageWorkspace;
  bool get imageReady;
  bool get cropping;
  bool capturingFrame = false, preparingPin = false, prepareQueued = false;
  bool autoPinQueued = false,
      prepareAgain = false,
      pinPreparationFailed = false;
  int autoPinEpoch = 0, preparedSerial = -1;
  Rect? preparedRect;
  void queuePreparedReferencePin() {
    if (preparingPin) {
      prepareAgain = true;
      return;
    }
    if (capturesScreenshot ||
        imageWorkspace == null ||
        prepareQueued ||
        !mounted) {
      return;
    }
    prepareQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prepareQueued = false;
      if (mounted && !tools.closed) _reportPaintBounds();
      if (!mounted ||
          tools.closed ||
          tools.busy ||
          capturingFrame ||
          tools.referenceAutoPinPending ||
          !imageReady ||
          cropping ||
          !tools.referenceAutoPinOnClose ||
          tools.reference == null ||
          imageWorkspace?.visible == false) {
        return;
      }
      final box = viewport.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final rect = physicalReferenceViewport(box);
      if (preparedSerial == tools.referenceEditSerial && preparedRect == rect) {
        return;
      }
      preparedSerial = tools.referenceEditSerial;
      preparedRect = rect;
      unawaited(pinReference(prepare: true));
    });
  }

  void _reportPaintBounds() {
    final workspace = imageWorkspace;
    final size = MenuWorkspaceViewport.sizeOf(context);
    final box = viewport.currentContext?.findRenderObject();
    if (workspace == null || size == null || box is! RenderBox) return;
    for (final lease in workspace.openPanels) {
      if (lease.id != 'image') continue;
      final rect = tools.referenceImageOnly
          ? MenuWorkspaceViewport.logicalRect(context, box)
          : null;
      workspace.setPaintBounds(
        lease,
        rect?.shift(-workspace.boundsFor('image', size).topLeft),
      );
      break;
    }
  }

  Rect physicalReferenceViewport(RenderBox box) {
    final painted = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Rect.fromLTWH(
      painted.left * dpr,
      painted.top * dpr,
      painted.width * dpr,
      painted.height * dpr,
    );
  }

  void queueDefaultReferencePin() {
    if (capturesScreenshot ||
        autoPinQueued ||
        !imageReady ||
        cropping ||
        tools.busy ||
        !tools.referenceAutoPinPending ||
        tools.reference == null) {
      return;
    }
    final owner = tools, revision = owner.revision;
    final epoch = ++autoPinEpoch;
    autoPinQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (epoch != autoPinEpoch) return;
      autoPinQueued = false;
      if (!mounted ||
          !identical(tools, owner) ||
          owner.closed ||
          owner.revision != revision ||
          !owner.referenceAutoPinPending ||
          !imageReady ||
          cropping ||
          capturingFrame ||
          owner.busy) {
        return;
      }
      owner.referenceAutoPinPending =
          false; // One attempt; failure has an explicit retry action.
      unawaited(pinReference());
    });
  }

  Future<void> pinReference({bool prepare = false}) async {
    if (capturingFrame ||
        preparingPin ||
        tools.busy ||
        tools.reference == null) {
      return;
    }
    if (!imageReady) {
      setState(() => tools.notice = '图片仍在加载，请稍后固定。');
      return;
    }
    final owner = tools;
    final revision = owner.revision;
    final editSerial = tools.referenceEditSerial;
    if (prepare) {
      preparingPin = true;
    } else {
      setState(() => capturingFrame = true);
    }
    ui.Image? image;
    try {
      if (prepare) {
        await owner.call('imageCancelPreparedPin', const {});
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !identical(tools, owner) ||
          owner.closed ||
          owner.revision != revision) {
        return;
      }
      final box = viewport.currentContext?.findRenderObject();
      if (box is! RenderRepaintBoundary || !box.hasSize) return;
      final rect = physicalReferenceViewport(box);
      final physical = rect.size;
      final ratio = physical.width / box.size.width;
      if (physical.width > 4096 ||
          physical.height > 4096 ||
          physical.width * physical.height > 16000000) {
        throw StateError('viewport too large');
      }
      image = await box.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted ||
          !identical(tools, owner) ||
          owner.closed ||
          owner.revision != revision ||
          data == null) {
        return;
      }
      final frame = <String, Object?>{
        'bytes': data.buffer.asUint8List(),
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      };
      if (prepare) {
        if (editSerial != owner.referenceEditSerial ||
            !owner.referenceAutoPinOnClose) {
          return;
        }
        final result = await owner.call('imagePreparePin', frame);
        if (result != true) throw StateError('pin preparation failed');
        if (mounted && pinPreparationFailed) {
          setState(() {
            pinPreparationFailed = false;
            tools.notice = '';
          });
        }
      } else {
        await owner.pin(frame, editSerial: editSerial);
      }
    } on Object {
      if (mounted && identical(tools, owner) && !owner.closed) {
        if (prepare) pinPreparationFailed = true;
        setState(
          () => tools.notice = prepare
              ? '自动固定尚未准备好，请缩小图片窗口，或双击恢复工具后手动固定。'
              : '固定未完成，请缩小图片窗口后重试。',
        );
      }
    } finally {
      image?.dispose();
      preparingPin = false;
      if (mounted && !prepare) setState(() => capturingFrame = false);
      if (mounted &&
          prepare &&
          (prepareAgain || editSerial != owner.referenceEditSerial)) {
        prepareAgain = false;
        queuePreparedReferencePin();
        WidgetsBinding.instance.scheduleFrame();
      }
    }
  }

  void checkReferencePinPosition() {
    if (!tools.pinned || tools.pinDirty || tools.pinnedBounds == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || tools.closed) return;
      final box = viewport.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final rect = physicalReferenceViewport(box);
      if (rect != tools.pinnedBounds) tools.markPinDirty();
    });
  }
}
