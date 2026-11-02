import '../../app/feature_registry.dart';
import '../account/account_module.dart';
import '../account/account_models.dart';
import '../communities/community_hangar_sharing_port.dart';
import 'hangar_page.dart';
import 'hangar_reader_port.dart';
import 'hangar_inventory_port.dart';
import 'local_hangar_port.dart';
import 'cached_local_hangar.dart';
import 'hangar_display_session.dart';
import '../onboarding/connection_mode_port.dart';

FeatureDescriptor createHangarFeature(
  AccountModule account,
  HangarPreviewPort Function() previewFactory, {
  HangarInventoryPort? inventoryPort,
  LocalHangarPort Function()? localFactory,
  CommunityHangarSharingPort? sharingPort,
  ConnectionModeControl? connectionMode,
  LocalHangarPort Function(int revision)? offlineFactory,
  LocalHangarPort Function(String readId)? retainedFactory,
}) {
  CachedLocalHangar? local;
  int? generation;
  Object? sessionState;
  Object? localMode;
  Object modeScope() => (
    connectionMode?.snapshot.scope,
    connectionMode?.snapshot.revision,
    connectionMode?.snapshot.state,
    connectionMode?.failed,
    connectionMode?.snapshot.offlineAccount?.displayName,
    connectionMode?.snapshot.offlineAccount?.cachedAtUtc,
  );
  LocalHangarPort scopedLocal() {
    final projection = account.projection.value;
    final currentMode = modeScope();
    if (local == null ||
        generation != projection.generation ||
        sessionState != projection.sessionState ||
        localMode != currentMode) {
      final boundGeneration = projection.generation;
      final boundState = projection.sessionState;
      generation = boundGeneration;
      sessionState = boundState;
      localMode = currentMode;
      local = CachedLocalHangar(
        localFactory!(),
        isCurrent: () =>
            account.projection.value.generation == boundGeneration &&
            account.projection.value.sessionState == boundState &&
            modeScope() == currentMode &&
            (connectionMode == null ||
                !connectionMode.failed && connectionMode.allowsOnlineTraffic),
      );
    }
    return local!;
  }

  final display = retainedFactory == null || localFactory == null
      ? null
      : HangarDisplaySession(
          account: account.projection,
          retainedFactory: retainedFactory,
          localFactory: scopedLocal,
          mode: connectionMode,
        );
  return FeatureDescriptor(
    id: 'hangar',
    route: '/hangar',
    labelKey: 'navigation.hangar',
    descriptionKey: 'navigation.hangar.description',
    icon: StarBridgeIconSemantic.hangar,
    navigationRegion: NavigationRegion.personal,
    order: 10,
    onDispose: display?.dispose,
    prefetch: localFactory == null
        ? null
        : () async {
            if (connectionMode?.allowsOnlineTraffic == false ||
                connectionMode?.failed == true) {
              return;
            }
            final state = account.projection.value.sessionState;
            if (state != AccountSessionState.signedIn &&
                state != AccountSessionState.legacySignedIn) {
              return;
            }
            final cached = scopedLocal() as CachedLocalHangar;
            if (cached.snapshot == null) await cached.read();
          },
    buildDestination: (_) => HangarPage(
      account: account,
      previewFactory: previewFactory,
      inventoryPort: inventoryPort,
      localFactory: localFactory == null ? null : scopedLocal,
      sharingPort: sharingPort,
      connectionMode: connectionMode,
      offlineFactory: offlineFactory,
      retainedFactory: retainedFactory,
      displaySession: display,
    ),
  );
}
