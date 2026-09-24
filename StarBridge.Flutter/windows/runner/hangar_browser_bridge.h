#pragma once
#include <flutter/binary_messenger.h>
#include <windows.h>
#include <memory>

// Native browser viewport only; Flutter owns every visible control and status.
class HangarBrowserBridge {
 public:
  HangarBrowserBridge(HWND flutter_view, flutter::BinaryMessenger* messenger);
  ~HangarBrowserBridge();
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
