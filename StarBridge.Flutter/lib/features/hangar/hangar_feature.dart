import '../../app/feature_registry.dart';
import '../account/account_module.dart';
import '../account/account_models.dart';
import '../communities/community_hangar_sharing_port.dart';
import 'hangar_page.dart';
import 'hangar_reader_port.dart';
import 'hangar_inventory_port.dart';
import 'local_hangar_port.dart';
import 'cached_local_hangar.dart';

FeatureDescriptor createHangarFeature(
  AccountModule account,
  HangarPreviewPort Function() previewFactory, {
  HangarInventoryPort? inventoryPort,
  LocalHangarPort Function()? localFactory,
  CommunityHangarSharingPort? sharingPort,
}) {
  CachedLocalHangar? local;
  int? generation;
  Object? sessionState;
  LocalHangarPort scopedLocal() {
    final projection = account.projection.value;
    if (local == null ||
        generation != projection.generation ||
        sessionState != projection.sessionState) {
      final boundGeneration = projection.generation;
      final boundState = projection.sessionState;
      generation = boundGeneration;
      sessionState = boundState;
      local = CachedLocalHangar(
        localFactory!(),
        isCurrent: () =>
            account.projection.value.generation == boundGeneration &&
            account.projection.value.sessionState == boundState,
      );
    }
    return local!;
  }

  return FeatureDescriptor(
    id: 'hangar',
    route: '/hangar',
    labelKey: 'navigation.hangar',
    descriptionKey: 'navigation.hangar.description',
    icon: StarBridgeIconSemantic.hangar,
    navigationRegion: NavigationRegion.personal,
    order: 10,
    prefetch: localFactory == null
        ? null
        : () async {
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
    ),
  );
}
