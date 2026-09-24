#ifndef RUNNER_NATIVE_HOST_BRIDGE_H_
#define RUNNER_NATIVE_HOST_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

class NativeHostBridge {
 public:
  NativeHostBridge(HWND window, flutter::BinaryMessenger* messenger);
  ~NativeHostBridge();

  NativeHostBridge(const NativeHostBridge&) = delete;
  NativeHostBridge& operator=(const NativeHostBridge&) = delete;

  bool HandleWindowMessage(UINT message, LPARAM lparam) noexcept;
  void Shutdown() noexcept;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_NATIVE_HOST_BRIDGE_H_
