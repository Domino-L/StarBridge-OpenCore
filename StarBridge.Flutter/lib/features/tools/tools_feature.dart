import 'package:flutter/material.dart';

import '../../app/feature_registry.dart';
import 'exec_hangar_page.dart';
import 'exec_hangar_port.dart';
import 'cached_exec_hangar.dart';
import 'key_bindings_page.dart';
import 'key_bindings_port.dart';
import 'tools_page.dart';
import 'catalog_recent.dart';
import 'tools_snapshot_cache.dart';
import 'catalog_page.dart';
import 'catalog_port.dart';
import 'mission_records_port.dart';
import '../../app/routing/open_destination_intent.dart';
import '../../platform/window/menu_window_preferences.dart';

List<FeatureDescriptor> createToolsFeatures({
  ExecHangarPort Function()? createPort,
  MenuWindowPreferencesPort Function()? createMenuPreferences,
  KeyBindingsPort Function()? createKeyBindings,
  Future<Set<String>> Function()? readShortcuts,
  CatalogPort Function()? createCatalog,
  MissionRecordsPort Function()? createMissionRecords,
  CatalogRecent? recent,
  VoidCallback? onShown,
  VoidCallback? disposeRecent,
}) {
  final key = GlobalKey<ExecHangarPageState>();
  CachedExecHangar? cached;
  ObservedCatalogPort? catalog;
  final snapshots = ToolsSnapshotCache();
  var recentScope = recent?.scopeRevision;
  void scopeChanged() {
    if (recent?.scopeRevision == recentScope) return;
    recentScope = recent?.scopeRevision;
    if (catalog != null) {
      catalog!.retire();
    } else {
      snapshots.retire();
    }
  }

  recent?.addListener(scopeChanged);
  MissionRecordsPort? records;
  CatalogPort catalogPort() => catalog ??= ObservedCatalogPort(
    createCatalog?.call() ?? const UnavailableCatalogPort(),
    snapshots,
  );
  MissionRecordsPort? recordsPort() => records ??= createMissionRecords?.call();
  void openRecent(BuildContext context, CatalogRecentEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/tools/${entry.kind.name}'),
        builder: (context) => Scaffold(
          body: SafeArea(
            child: CatalogPage(
              kind: entry.kind,
              port: catalogPort(),
              recordsPort: recordsPort(),
              recent: recent,
              selection: entry.id,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }

  return [
    FeatureDescriptor(
      id: 'tools',
      route: '/tools',
      labelKey: 'navigation.tools',
      descriptionKey: 'navigation.tools.description',
      icon: StarBridgeIconSemantic.tools,
      navigationRegion: NavigationRegion.personal,
      order: 30,
      buildDestination: (_) {
        onShown?.call();
        return ToolsPage(
          hangar: createPort == null
              ? null
              : cached ??= CachedExecHangar(createPort()),
          cache: snapshots,
          recordsPort: recordsPort(),
          recent: recent,
          onOpenRecent: openRecent,
        );
      },
      onDispose: () {
        recent?.removeListener(scopeChanged);
        records?.dispose();
        catalog?.dispose();
        snapshots.dispose();
        disposeRecent?.call();
      },
    ),
    FeatureDescriptor(
      id: 'keyBindings',
      route: keyBindingsRoute,
      labelKey: 'keyBindings.title',
      descriptionKey: 'tools.keyBindings.description',
      icon: StarBridgeIconSemantic.tools,
      navigationRegion: NavigationRegion.shortcut,
      navigationParentId: 'tools',
      order: 31,
      buildDestination: (context) => KeyBindingsPage(
        port: createKeyBindings == null
            ? null
            : ObservedKeyBindingsPort(createKeyBindings(), snapshots),
        shortcuts: readShortcuts,
        onBack: () =>
            Actions.invoke(context, const OpenDestinationIntent('/tools')),
      ),
    ),
    for (final kind in CatalogKind.values)
      FeatureDescriptor(
        id: kind.name,
        route: '/tools/${kind.name}',
        labelKey: 'catalog.${kind.name}',
        descriptionKey: 'catalog.${kind.name}.description',
        icon: kind == CatalogKind.missions
            ? StarBridgeIconSemantic.operation
            : StarBridgeIconSemantic.generalData,
        navigationRegion: NavigationRegion.shortcut,
        navigationParentId: 'tools',
        order: kind == CatalogKind.missions ? 32 : 33,
        buildDestination: (context) {
          onShown?.call();
          return CatalogPage(
            kind: kind,
            port: catalogPort(),
            recordsPort: recordsPort(),
            recent: recent,
            onBack: () =>
                Actions.invoke(context, const OpenDestinationIntent('/tools')),
          );
        },
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
