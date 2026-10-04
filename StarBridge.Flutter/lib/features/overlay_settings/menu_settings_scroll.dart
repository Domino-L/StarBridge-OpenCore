import 'package:flutter/material.dart';

/// A panel-edge scrollbar, independent of the padded setting controls.
class MenuSettingsScroll extends StatefulWidget {
  const MenuSettingsScroll({super.key, required this.child});
  final Widget child;

  @override
  State<MenuSettingsScroll> createState() => _MenuSettingsScrollState();
}

class _MenuSettingsScrollState extends State<MenuSettingsScroll> {
  final controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: ScrollbarTheme(
      data: ScrollbarTheme.of(context).copyWith(crossAxisMargin: 2),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        thickness: 6,
        scrollbarOrientation: ScrollbarOrientation.right,
        child: SingleChildScrollView(
          controller: controller,
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 0, 24, 16),
          child: widget.child,
        ),
      ),
    ),
  );
}
