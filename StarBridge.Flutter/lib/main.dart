import 'app/bootstrap/bootstrap_starbridge.dart';
import 'app/tray/tray_surface_app.dart';
import 'app/menu_overlay/menu_overlay_surface_app.dart';
import 'app/product_features.dart';
import 'app/friends_window/friends_window_app.dart';
import 'app/social_windows/social_window_app.dart';

void main() {
  bootstrapStarBridge();
}

@pragma('vm:entry-point')
void trayMain() => runTraySurface();

@pragma('vm:entry-point')
void friendsMain() => runFriendsWindow();

@pragma('vm:entry-point')
void messagesMain() => runSocialWindow('messages');

@pragma('vm:entry-point')
void notificationsMain() => runSocialWindow('notifications');

@pragma('vm:entry-point')
void menuMain() {
  if (menuOverlayEnabled) runMenuOverlaySurface();
}

// Only the separate, explicitly launched native preview harness selects this.
@pragma('vm:entry-point')
void menuPreviewMain() {
  if (menuOverlayEnabled) runMenuOverlaySurface(workspacePreview: true);
}
