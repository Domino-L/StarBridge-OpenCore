#ifndef RUNNER_MENU_OVERLAY_WINDOW_H_
#define RUNNER_MENU_OVERLAY_WINDOW_H_

#include <windows.h>
#include <functional>
#include <optional>
#include "menu_overlay_session.h"

// Owns only the native tool window and input lifetime, never the app/HUD window.
// All methods are called on the window's platform thread. No input injection.
class MenuOverlayWindow {
 public:
  using MessageHandler = std::function<std::optional<LRESULT>(HWND, UINT, WPARAM, LPARAM)>;
  MenuOverlayWindow() = default;
  ~MenuOverlayWindow();
  MenuOverlayWindow(const MenuOverlayWindow&) = delete;
  MenuOverlayWindow& operator=(const MenuOverlayWindow&) = delete;
  bool Create();
  bool Attach(HWND child);
  // Begin is user initiated. No visibility until Reveal accepts its lease.
  uint64_t Begin(HWND expected_foreground = nullptr);
  bool Reveal(uint64_t opening);
  void Hide(bool return_focus = false);
  void SetLocalModal(bool active);
  bool RegisterShortcut(UINT modifiers, UINT key);
  void UnregisterShortcut();
  HWND handle() const { return window_; }
  const MenuOverlaySession& session() const { return session_; }
  std::function<void()> on_shortcut;
  std::function<void()> on_hidden;
  MessageHandler on_message;

 private:
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
  bool Fit(HMONITOR monitor);
  bool Owns(HWND window) const;
  bool ReturnTargetValid() const;
  bool ConfigureComposition();
  HWND window_ = nullptr;
  HWND child_ = nullptr;
  HWND return_target_ = nullptr;
  DWORD return_pid_ = 0;
  int shortcut_id_ = 0;
  bool destroying_ = false;
  bool local_modal_ = false;
  MenuOverlaySession session_;
};
#endif
