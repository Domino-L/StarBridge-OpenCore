/// A bounded tool projection and explicit intent, not a Host RPC tunnel.
abstract interface class MenuFeatureLease {
  void show(bool visible);
  void act(String key, String value);
  void dispose();
}

typedef MenuFeatureFactory = MenuFeatureLease Function(
  void Function(Map<String, Object?>) publish,
);
