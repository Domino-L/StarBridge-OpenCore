import 'package:flutter/material.dart';

import '../../../design_system/interaction/starbridge_activation_origin.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../../design_system/appearance/appearance_scope.dart';
import '../../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../../design_system/tokens/color_tokens.dart';
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
    this.onActivateWithSource,
    this.onPrimaryInteractionFinished,
    this.interaction = NavigationInteraction.keyboard,
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
  final Future<bool> Function(FeatureDescriptor, NavigationInteraction)?
  onActivateWithSource;
  final void Function(FeatureDescriptor, NavigationInteraction)?
  onPrimaryInteractionFinished;
  final NavigationInteraction interaction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final width = switch (mode) {
      ShellLayoutMode.wide => tokens.density.navigationWide,
      ShellLayoutMode.compact => tokens.density.navigationCompact,
      ShellLayoutMode.iconOnly => tokens.density.navigationIconOnly,
    };
    return Container(
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 节日印花垫在底色和导航项之间，不挡字。
          const AppearanceSurfaceBackdrop(role: SurfaceRole.navigation),
          StarBridgeInteractionRegion(
            child: Builder(
              builder: (context) => AnimatedBuilder(
                animation: Listenable.merge([
                  for (final descriptor in registry.all)
                    if (descriptor.primaryNavigationSelected != null)
                      descriptor.primaryNavigationSelected!,
                ]),
                builder: (context, _) {
                  final destinations = [
                    registry.home,
                    ...registry.inRegion(NavigationRegion.primary),
                    ...registry.inRegion(NavigationRegion.personal),
                  ];
                  FeatureDescriptor? owner;
                  for (final descriptor in destinations) {
                    if (descriptor.ownsNavigationSelection(selected)) {
                      owner = descriptor;
                      break;
                    }
                  }
                  return SuiteSideNav.tracked(
                    homeId: registry.home.route,
                    primaryIds: registry
                        .inRegion(NavigationRegion.primary)
                        .map((d) => d.route)
                        .toList(),
                    personalIds: registry
                        .inRegion(NavigationRegion.personal)
                        .map((d) => d.route)
                        .toList(),
                    selectedId:
                        owner != null &&
                            (owner.primaryNavigationSelected?.value ?? true)
                        ? owner.route
                        : '',
                    changeSource: interaction == NavigationInteraction.keyboard
                        ? InteractionSource.keyboard
                        : InteractionSource.pointer,
                    layoutBuilder: _layout,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layout(BuildContext context, SideNavLayout layout) {
    final tokens = context.tokens;
    return Column(
      key: Key('navigation-pane-${mode.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        layout.anchor(
          registry.home.route,
          BrandHomeButton(
            focusNode: layout.focusNode(registry.home.route),
            mode: mode,
            selected: selected == registry.home,
            onPressed: () =>
                onSelect(registry.home, NavigationInteraction.pointer),
            onKeyboardPressed: () {
              layout.finishMotion();
              onSelect(registry.home, NavigationInteraction.keyboard);
            },
            onPrevious: () => _move(layout, registry.home, -1),
            onNext: () => _move(layout, registry.home, 1),
          ),
        ),
        Divider(height: tokens.stroke.hairline),
        Expanded(
          child: ListView(
            key: layout.viewportKey,
            controller: layout.scrollController,
            padding: EdgeInsets.only(top: tokens.space.sm),
            children: [
              ..._items(context, NavigationRegion.primary, layout),
              for (final descriptor in registry.inRegion(
                NavigationRegion.primary,
              ))
                if (descriptor.buildNavigationPanel != null)
                  descriptor.buildNavigationPanel!(
                    context,
                    mode == ShellLayoutMode.iconOnly,
                    descriptor.ownsNavigationSelection(selected),
                    () async {
                      return _activateDescriptor(
                        descriptor,
                        currentStarBridgeActivationSource ==
                                InteractionSource.keyboard
                            ? NavigationInteraction.keyboard
                            : NavigationInteraction.pointer,
                      );
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
        ..._items(context, NavigationRegion.personal, layout),
        SizedBox(height: tokens.space.sm),
      ],
    );
  }

  Iterable<Widget> _items(
    BuildContext context,
    NavigationRegion region,
    SideNavLayout layout,
  ) sync* {
    final tokens = context.tokens;
    for (final descriptor in registry.inRegion(region)) {
      yield Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.space.sm),
        child: descriptor.primaryNavigationSelected == null
            ? layout.anchor(
                descriptor.route,
                _item(context, descriptor, true, layout),
              )
            : ValueListenableBuilder<bool>(
                valueListenable: descriptor.primaryNavigationSelected!,
                builder: (context, isPrimary, _) => layout.anchor(
                  descriptor.route,
                  _item(context, descriptor, isPrimary, layout),
                ),
              ),
      );
      yield SizedBox(height: tokens.space.xs);
    }
  }

  Widget _item(
    BuildContext context,
    FeatureDescriptor descriptor,
    bool primary,
    SideNavLayout layout,
  ) => ShellNavigationItem(
    key: ValueKey(descriptor.route),
    descriptor: descriptor,
    mode: mode,
    selected: primary && descriptor.ownsNavigationSelection(selected),
    focusNode: layout.focusNode(descriptor.route),
    sharedSelection: true,
    onPressed: () =>
        _activatePrimary(descriptor, NavigationInteraction.pointer, layout),
    onKeyboardPressed: () =>
        _activatePrimary(descriptor, NavigationInteraction.keyboard, layout),
    onPrevious: () => _move(layout, descriptor, -1),
    onNext: () => _move(layout, descriptor, 1),
  );

  Future<void> _activatePrimary(
    FeatureDescriptor descriptor,
    NavigationInteraction interaction,
    SideNavLayout layout,
  ) async {
    if (interaction == NavigationInteraction.keyboard) layout.finishMotion();
    final landing = descriptor.onPrimaryNavigation;
    if (landing == null) {
      onSelect(descriptor, interaction);
      return;
    }
    if (!await _activateDescriptor(descriptor, interaction)) return;
    await runStarBridgeActivation(
      interaction == NavigationInteraction.keyboard
          ? InteractionSource.keyboard
          : InteractionSource.pointer,
      () async {
        await landing();
        onPrimaryInteractionFinished?.call(
          descriptor,
          currentStarBridgeActivationSource == InteractionSource.keyboard
              ? NavigationInteraction.keyboard
              : NavigationInteraction.pointer,
        );
      },
    );
  }

  Future<bool> _activateDescriptor(
    FeatureDescriptor descriptor,
    NavigationInteraction interaction,
  ) async {
    if (onActivateWithSource != null) {
      return onActivateWithSource!(descriptor, interaction);
    }
    if (onActivate != null) return onActivate!(descriptor);
    onSelect(descriptor, interaction);
    return true;
  }

  void _move(SideNavLayout layout, FeatureDescriptor current, int delta) {
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
    layout.focus(destinations[targetIndex].route);
    _activatePrimary(
      destinations[targetIndex],
      NavigationInteraction.keyboard,
      layout,
    );
  }
}
