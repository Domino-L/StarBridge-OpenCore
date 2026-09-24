#ifndef RUNNER_MENU_OVERLAY_BRIDGE_H_
#define RUNNER_MENU_OVERLAY_BRIDGE_H_
#include <flutter/binary_messenger.h>
#include <memory>
#include <windows.h>

// Opt-in bridge. Construction registers a channel, not a shortcut or window.
// The auxiliary engine has no plugins, Native Host or account bootstrap.
class MenuOverlayBridge {
 public:
  explicit MenuOverlayBridge(flutter::BinaryMessenger* messenger, HWND client = nullptr);
  ~MenuOverlayBridge();
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
