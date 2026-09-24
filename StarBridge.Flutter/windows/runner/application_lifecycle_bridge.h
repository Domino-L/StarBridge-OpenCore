#ifndef RUNNER_APPLICATION_LIFECYCLE_BRIDGE_H_
#define RUNNER_APPLICATION_LIFECYCLE_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

class ApplicationLifecycleBridge {
 public:
  ApplicationLifecycleBridge(HWND window,
                             flutter::BinaryMessenger* messenger,
                             bool startup_launch);
  ~ApplicationLifecycleBridge();

  ApplicationLifecycleBridge(const ApplicationLifecycleBridge&) = delete;
  ApplicationLifecycleBridge& operator=(const ApplicationLifecycleBridge&) =
      delete;

  void OnFirstFrameReady();
  bool HandleCloseRequest() noexcept;
  bool HandleWindowMessage(UINT message,
                           WPARAM wparam,
                           LPARAM lparam) noexcept;
  void Shutdown() noexcept;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_APPLICATION_LIFECYCLE_BRIDGE_H_
