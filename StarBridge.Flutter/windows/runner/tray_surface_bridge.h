#ifndef STARBRIDGE_TRAY_SURFACE_BRIDGE_H_
#define STARBRIDGE_TRAY_SURFACE_BRIDGE_H_
#include <flutter/binary_messenger.h>
#include <windows.h>
#include <functional>
#include <memory>

// One lazily created auxiliary Flutter view in this process. No plugin/Host,
// credentials, application bootstrap or second tray icon is created in it.
class TraySurfaceBridge {
 public:
  TraySurfaceBridge(HWND owner, flutter::BinaryMessenger* messenger,
                    std::function<void()> open, std::function<void()> exit,
                    std::function<void()> fallback);
  ~TraySurfaceBridge();
  bool Show(POINT anchor, bool keyboard);
  void Hide();
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
