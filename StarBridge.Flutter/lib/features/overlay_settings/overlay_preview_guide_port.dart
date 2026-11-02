/// Device-local help acknowledgement. Never a workspace save or entitlement.
abstract interface class OverlayPreviewGuidePort {
  Future<bool> readPreviewGuideSeen();
  Future<void> markPreviewGuideSeen();
}
