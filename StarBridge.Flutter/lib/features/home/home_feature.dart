import '../../app/feature_registry.dart';
import '../../app/presence/manual_presence.dart';
import '../../app/shell/chrome/shell_chrome_port.dart';
import '../party_rooms/party_rooms_module.dart';
import 'home_page.dart';

FeatureDescriptor createHomeFeature(
  PartyRoomsModule rooms,
  ShellChromePort chrome, {
  ManualPresenceController? presence,
}) => FeatureDescriptor(
  id: 'home',
  route: '/',
  labelKey: 'navigation.home',
  descriptionKey: 'navigation.home.description',
  icon: StarBridgeIconSemantic.home,
  navigationRegion: NavigationRegion.brand,
  order: 0,
  buildDestination: (_) =>
      HomePage(chrome: chrome, rooms: rooms, presence: presence),
);
