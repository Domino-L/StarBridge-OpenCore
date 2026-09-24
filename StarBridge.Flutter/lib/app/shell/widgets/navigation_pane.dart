import 'package:flutter/material.dart';

import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../feature_registry.dart';
import '../../localization/app_strings.dart';
import '../shell_layout_mode.dart';
import '../shell_navigation_controller.dart';
import 'brand_home_button.dart';
import 'navigation_item.dart';

class StarBridgeNavigationPane extends StatelessWidget {
  const StarBridgeNavigationPane({
    required this.registry,
    required this.mode,
    required this.selected,
    required this.onSelect,
    this.onActivate,
    super.key,
  });

  final FeatureRegistry registry;
  final ShellLayoutMode mode;
  final FeatureDescriptor selected;
  final void Function(
    FeatureDescriptor descriptor,
    NavigationInteraction interaction,
  )
  onSelect;

  final Future<bool> Function(FeatureDescriptor)? onActivate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final width = switch (mode) {
      ShellLayoutMode.wide => tokens.density.navigationWide,
      ShellLayoutMode.compact => tokens.density.navigationCompact,
      ShellLayoutMode.iconOnly => tokens.density.navigationIconOnly,
    };
    return Container(
      key: Key('navigation-pane-${mode.name}'),
      width: width,
      decoration: BoxDecoration(
        color: tokens.surfaces.navigation.fill,
        border: BorderDirectional(
          end: BorderSide(
            color: tokens.surfaces.navigation.border,
            width: tokens.stroke.hairline,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandHomeButton(
            mode: mode,
            selected: selected == registry.home,
            onPressed: () =>
                onSelect(registry.home, NavigationInteraction.pointer),
            onKeyboardPressed: () =>
                onSelect(registry.home, NavigationInteraction.keyboard),
            onPrevious: () => _move(context, registry.home, -1),
            onNext: () => _move(context, registry.home, 1),
          ),
          Divider(height: tokens.stroke.hairline),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(top: tokens.space.sm),
              children: [
                ..._items(context, NavigationRegion.primary),
                for (final descriptor in registry.inRegion(
                  NavigationRegion.primary,
                ))
                  if (descriptor.buildNavigationPanel != null)
                    descriptor.buildNavigationPanel!(
                      context,
                      mode == ShellLayoutMode.iconOnly,
                      descriptor.ownsNavigationSelection(selected),
                      () async {
                        if (onActivate != null) return onActivate!(descriptor);
                        onSelect(descriptor, NavigationInteraction.pointer);
                        return true;
                      },
                    ),
              ],
            ),
          ),
          Divider(height: tokens.stroke.hairline),
          if (mode != ShellLayoutMode.iconOnly)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: tokens.space.md,
                top: tokens.space.sm,
                bottom: tokens.space.xs,
              ),
              child: Text(
                AppStrings.of(context).text('navigation.personal'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            )
          else
            SizedBox(height: tokens.space.xs),
          ..._items(context, NavigationRegion.personal),
          SizedBox(height: tokens.space.sm),
        ],
      ),
    );
  }

  Iterable<Widget> _items(BuildContext context, NavigationRegion region) sync* {
    final tokens = context.tokens;
    for (final descriptor in registry.inRegion(region)) {
      yield Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.space.sm),
        child: descriptor.primaryNavigationSelected == null
            ? _item(context, descriptor, true)
            : ValueListenableBuilder<bool>(
                valueListenable: descriptor.primaryNavigationSelected!,
                builder: (context, isPrimary, _) =>
                    _item(context, descriptor, isPrimary),
              ),
      );
      yield SizedBox(height: tokens.space.xs);
    }
  }

  Widget _item(
    BuildContext context,
    FeatureDescriptor descriptor,
    bool primary,
  ) => ShellNavigationItem(
    key: ValueKey(descriptor.route),
    descriptor: descriptor,
    mode: mode,
    selected: primary && descriptor.ownsNavigationSelection(selected),
    onPressed: () =>
        _activatePrimary(descriptor, NavigationInteraction.pointer),
    onKeyboardPressed: () =>
        _activatePrimary(descriptor, NavigationInteraction.keyboard),
    onPrevious: () => _move(context, descriptor, -1),
    onNext: () => _move(context, descriptor, 1),
  );

  Future<void> _activatePrimary(
    FeatureDescriptor descriptor,
    NavigationInteraction interaction,
  ) async {
    final landing = descriptor.onPrimaryNavigation;
    if (landing == null) {
      onSelect(descriptor, interaction);
      return;
    }
    if (onActivate != null) {
      if (!await onActivate!(descriptor)) return;
    } else {
      onSelect(descriptor, interaction);
    }
    await landing();
  }

  void _move(BuildContext context, FeatureDescriptor current, int delta) {
    final destinations = [
      registry.home,
      ...registry.inRegion(NavigationRegion.primary),
      ...registry.inRegion(NavigationRegion.personal),
    ];
    final currentIndex = destinations.indexOf(current);
    final targetIndex = (currentIndex + delta).clamp(
      0,
      destinations.length - 1,
    );
    if (targetIndex == currentIndex) {
      return;
    }
    if (delta > 0) {
      FocusScope.of(context).nextFocus();
    } else {
      FocusScope.of(context).previousFocus();
    }
    _activatePrimary(destinations[targetIndex], NavigationInteraction.keyboard);
  }
}
