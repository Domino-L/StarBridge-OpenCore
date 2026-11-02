import 'package:flutter/material.dart';

import '../interaction/starbridge_interaction_theme.dart';
import '../tokens/color_tokens.dart';
import '../tokens/starbridge_tokens.dart';
import 'appearance_layers.dart';
import 'surface_print.dart';
import 'user_background.dart';

/// 把当前的外观层交给外壳用。没有包在作用域里时，一律按平时的外观。
class AppearanceScope extends InheritedWidget {
  const AppearanceScope({
    required this.layers,
    required super.child,
    super.key,
  });

  final AppearanceLayers layers;

  static AppearanceLayers of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.layers ??
      AppearanceLayers.standard;

  @override
  bool updateShouldNotify(AppearanceScope oldWidget) =>
      oldWidget.layers != layers;
}

/// 节日生效时，把"平时的那套主题"传给 [HolidayColorExempt] 用；平时 [data] 是 null。
class HolidayExemptThemeScope extends InheritedWidget {
  const HolidayExemptThemeScope({
    required this.data,
    required super.child,
    super.key,
  });

  final ThemeData? data;

  static ThemeData? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<HolidayExemptThemeScope>()
      ?.data;

  @override
  bool updateShouldNotify(HolidayExemptThemeScope oldWidget) =>
      oldWidget.data != data;
}

/// 里面的内容不跟节日配色走，颜色和平时一样。
///
/// 交易大厅用它（用户 10-30："交易这里的蓝色不能改"）。侧栏、顶栏照常是节日外观。
/// 里面弹出的对话框会带上这里的主题（`InheritedTheme.capture`）。
/// 不管节日在不在都包这一层：外观切换时页面不会因此重建、丢掉滚动位置。
class HolidayColorExempt extends StatelessWidget {
  const HolidayColorExempt({
    required this.child,
    this.restoreGround = false,
    super.key,
  });

  final Widget child;

  /// 连页面底色也还原，盖住下面的节日底色和印花。整页用；嵌在别的页面里的一块不用。
  final bool restoreGround;

  @override
  Widget build(BuildContext context) {
    final standard = HolidayExemptThemeScope.maybeOf(context);
    final current = Theme.of(context);
    final content = Theme(
      // 用户当前选的交互风格是外层单独发布的，换颜色时要带上。
      data: standard == null
          ? current
          : standard.copyWith(
              extensions: [
                ...standard.extensions.values.where(
                  (extension) => extension is! StarBridgeInteractionTheme,
                ),
                ?current.extension<StarBridgeInteractionTheme>(),
              ],
            ),
      // 弹窗边线、光晕用的是交互调色板，也要跟着还原。
      child: StarBridgeInteractionRegion(child: child),
    );
    if (!restoreGround) return content;
    // 用户自己的背景图优先于节日，不盖它。
    final covered =
        standard != null && AppearanceScope.of(context).userBackground == null;
    return ColoredBox(
      color: covered
          ? standard.extension<StarBridgeTokens>()!.surfaces.ground.fill
          : Colors.transparent,
      child: content,
    );
  }
}

/// 垫在一个面的底色和内容之间的那一层：用户背景图或者节日印花。
///
/// 放在 Stack 最底下，内容照常画在上面，所以不会挡字。
class AppearanceSurfaceBackdrop extends StatelessWidget {
  const AppearanceSurfaceBackdrop({required this.role, super.key});

  final SurfaceRole role;

  @override
  Widget build(BuildContext context) {
    final layers = AppearanceScope.of(context);
    final tokens = context.tokens;
    final background = layers.userBackground;
    final spec = layers.printFor(role, tokens.appearanceMode);
    if (background != null && role == SurfaceRole.ground) {
      return UserBackgroundLayer(
        key: const Key('appearance-user-background'),
        image: background,
        scrimColor: tokens.surfaces.ground.fill,
      );
    }
    if (spec == null) return const SizedBox.shrink();
    return SurfacePrint(spec: spec, role: role);
  }
}
