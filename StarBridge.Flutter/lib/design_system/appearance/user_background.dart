import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 用户自己选的一张图片背景。只支持图片，不提供纯色和渐变。
///
/// 这一版只有数据和绘制，选图片的设置界面以后再做。
@immutable
final class UserBackgroundImage {
  const UserBackgroundImage({
    required this.path,
    this.alignment = Alignment.center,
    this.darken = .45,
    this.blurSigma = 0,
  }) : assert(darken >= 0 && darken <= 1),
       assert(blurSigma >= 0);

  /// 本机文件路径。
  final String path;

  /// 按显示尺寸裁剪时，保留图片的哪一部分。
  final Alignment alignment;

  /// 暗化遮罩的浓度（0 到 1）。不会低于 [minimumDarken]，保证前景文字看得清。
  final double darken;

  /// 模糊半径；0 表示不模糊。
  final double blurSigma;

  /// 再亮的图也至少压这么多，否则白字就看不清了。
  static const minimumDarken = .40;

  double get effectiveDarken => darken < minimumDarken ? minimumDarken : darken;

  UserBackgroundImage copyWith({
    String? path,
    Alignment? alignment,
    double? darken,
    double? blurSigma,
  }) => UserBackgroundImage(
    path: path ?? this.path,
    alignment: alignment ?? this.alignment,
    darken: darken ?? this.darken,
    blurSigma: blurSigma ?? this.blurSigma,
  );

  @override
  bool operator ==(Object other) =>
      other is UserBackgroundImage &&
      other.path == path &&
      other.alignment == alignment &&
      other.darken == darken &&
      other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(path, alignment, darken, blurSigma);
}

/// 把用户背景图铺满一个面：按显示尺寸解码、裁剪，再盖一层暗化。
///
/// 大图不会原样解码，解码宽度按这块面的物理像素来。
class UserBackgroundLayer extends StatelessWidget {
  const UserBackgroundLayer({
    required this.image,
    required this.scrimColor,
    super.key,
  });

  final UserBackgroundImage image;

  /// 暗化用的底色，一般是这个面的底色。
  final Color scrimColor;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final width = constraints.hasBoundedWidth
              ? (constraints.maxWidth * ratio).ceil()
              : null;
          Widget picture = Image(
            image: ResizeImage.resizeIfNeeded(
              width,
              null,
              FileImage(File(image.path)),
            ),
            fit: BoxFit.cover,
            alignment: image.alignment,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
          if (image.blurSigma > 0) {
            picture = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: image.blurSigma,
                sigmaY: image.blurSigma,
                tileMode: TileMode.clamp,
              ),
              child: picture,
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              picture,
              ColoredBox(
                color: scrimColor.withValues(alpha: image.effectiveDarken),
              ),
            ],
          );
        },
      ),
    );
  }
}
