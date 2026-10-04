#ifndef RUNNER_FRIENDS_WINDOW_BRIDGE_H_
#define RUNNER_FRIENDS_WINDOW_BRIDGE_H_
#include <windows.h>
#include <flutter/binary_messenger.h>
#include <memory>
#include <string>

// Ordinary desktop window, independent of the menu overlay. Presentation only.
class FriendsWindowBridge {
 public:
  FriendsWindowBridge(HWND owner, flutter::BinaryMessenger* messenger,
                      std::wstring data_path = L"data", std::string kind = "friends");
  ~FriendsWindowBridge();
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
