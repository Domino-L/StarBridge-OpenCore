import 'package:flutter/material.dart';

import '../../app/feature_registry.dart';
import 'exec_hangar_page.dart';
import 'exec_hangar_port.dart';
import 'cached_exec_hangar.dart';
import 'tools_page.dart';
import '../../app/routing/open_destination_intent.dart';
import '../../platform/window/menu_window_preferences.dart';

List<FeatureDescriptor> createToolsFeatures({
  ExecHangarPort Function()? createPort,
  MenuWindowPreferencesPort Function()? createMenuPreferences,
}) {
  final key = GlobalKey<ExecHangarPageState>();
  CachedExecHangar? cached;
  return [
    FeatureDescriptor(
      id: 'tools',
      route: '/tools',
      labelKey: 'navigation.tools',
      descriptionKey: 'navigation.tools.description',
      icon: StarBridgeIconSemantic.tools,
      navigationRegion: NavigationRegion.personal,
      order: 30,
      buildDestination: (_) => const ToolsPage(),
    ),
    FeatureDescriptor(
      id: 'execHangar',
      route: '/tools/exec-hangar',
      labelKey: 'execHangar.title',
      descriptionKey: 'tools.execHangar.description',
      icon: StarBridgeIconSemantic.tools,
      navigationRegion: NavigationRegion.shortcut,
      navigationParentId: 'tools',
      order: 30,
      buildDestination: (context) => ExecHangarPage(
        key: key,
        port: createPort == null
            ? null
            : cached ??= CachedExecHangar(createPort()),
        menuPreferences: createMenuPreferences?.call(),
        onBack: () =>
            Actions.invoke(context, const OpenDestinationIntent('/tools')),
      ),
      confirmLeave: (context) =>
          key.currentState?.confirmLeave(context) ?? Future.value(true),
    ),
  ];
}
