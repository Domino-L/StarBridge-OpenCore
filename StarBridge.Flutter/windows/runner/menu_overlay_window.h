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
  // Idle preparation only: sizes the hidden surface without a session,
  // visibility, activation or focus change.
  bool Prepare();
  // Begin is user initiated. No visibility until Reveal accepts its lease.
  // Only an opening the shortcut made over the game may join its input queue.
  uint64_t Begin(HWND expected_foreground = nullptr, bool may_join_game_input = false);
  // True also covers an accepted, bounded foreground handoff. on_visible is
  // emitted only after the menu/view actually owns foreground input.
  bool Reveal(uint64_t opening);
  // reason: fixed diagnostic code reported with the hidden state; no payload.
  void Hide(bool return_focus = false, const char* reason = "request");
  const char* hide_reason() const { return hide_reason_; }
  void SetLocalModal(bool active);
  bool local_modal() const { return local_modal_; }
  HWND handle() const { return window_; }
  const MenuOverlaySession& session() const { return session_; }
  std::function<void()> on_hidden;
  std::function<void()> on_visible;
  MessageHandler on_message;

 private:
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
  bool Fit(HMONITOR monitor);
  bool Owns(HWND window) const;
  bool ReturnTargetValid() const;
  bool ConfigureComposition();
  bool TakeForegroundInput();
  void CheckForegroundInput();
  void ReturnAbandonedForeground();
  HWND window_ = nullptr;
  HWND child_ = nullptr;
  HWND return_target_ = nullptr;
  DWORD return_pid_ = 0;
  bool destroying_ = false;
  bool local_modal_ = false;
  bool awaiting_input_ = false;
  bool may_join_game_input_ = false;
  ULONGLONG input_deadline_ = 0;
  // A cancelled cross-queue handoff can still activate the hidden menu later.
  HWND abandoned_target_ = nullptr;
  DWORD abandoned_pid_ = 0;
  ULONGLONG abandoned_deadline_ = 0;
  const char* hide_reason_ = "request";
  MenuOverlaySession session_;
};
#endif
