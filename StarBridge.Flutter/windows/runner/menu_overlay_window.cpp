#include "menu_overlay_window.h"
#include "menu_overlay_focus.h"
#include <dwmapi.h>

namespace {
constexpr wchar_t kClass[] = L"StarBridge.Flutter.MenuOverlay.v1";
constexpr UINT_PTR kFrameTimeout = 0x534d;
constexpr int kShortcutA = 0x534d;
constexpr int kShortcutB = 0x534e;
}

MenuOverlayWindow::~MenuOverlayWindow() {
  destroying_ = true;
  on_hidden = nullptr;
  on_shortcut = nullptr;
  on_message = nullptr;
  Hide();
  UnregisterShortcut();
  if (window_) DestroyWindow(window_);
}

bool MenuOverlayWindow::Create() {
  if (window_) return true;
  WNDCLASSW wc{};
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kClass;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
  // Independent, not owned by the desktop client: showing it must not raise
  // the desktop client over the game. No WS_EX_TRANSPARENT during interaction.
  window_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kClass,
      L"StarBridge", WS_POPUP, 0, 0, 1, 1, nullptr, nullptr, wc.hInstance, this);
  if (!window_) return false;
  // Candidate alpha composition path, not a claim of verified GPU transparency.
  if (!ConfigureComposition()) {
    DestroyWindow(window_);
    window_ = nullptr;
    return false;
  }
  return true;
}

bool MenuOverlayWindow::ConfigureComposition() {
  const MARGINS margins{-1, -1, -1, -1};
  BOOL composed = FALSE;
  return SUCCEEDED(DwmIsCompositionEnabled(&composed)) && composed &&
      SUCCEEDED(DwmExtendFrameIntoClientArea(window_, &margins));
}

bool MenuOverlayWindow::Attach(HWND child) {
  if (!window_ || !IsWindow(child)) return false;
  DWORD pid = 0;
  const DWORD thread = GetWindowThreadProcessId(child, &pid);
  if (pid != GetCurrentProcessId() || thread != GetCurrentThreadId()) return false;
  SetLastError(ERROR_SUCCESS);
  if (!SetParent(child, window_) && GetLastError() != ERROR_SUCCESS) return false;
  SetLastError(ERROR_SUCCESS);
  const auto style = GetWindowLongPtrW(child, GWL_STYLE);
  if (!SetWindowLongPtrW(child, GWL_STYLE, (style | WS_CHILD) & ~WS_POPUP) &&
      GetLastError() != ERROR_SUCCESS) return false;
  child_ = child;
  RECT rect{};
  GetClientRect(window_, &rect);
  MoveWindow(child_, 0, 0, rect.right, rect.bottom, FALSE);
  ShowWindow(child_, SW_SHOWNA);
  return true;
}

bool MenuOverlayWindow::Owns(HWND window) const {
  return window_ && window && (window == window_ || IsChild(window_, window));
}

bool MenuOverlayWindow::ReturnTargetValid() const {
  DWORD pid = 0;
  return return_target_ && IsWindow(return_target_) &&
      GetWindowThreadProcessId(return_target_, &pid) != 0 && pid == return_pid_;
}

bool MenuOverlayWindow::Fit(HMONITOR monitor) {
  MONITORINFO info{sizeof(info)};
  if (!GetMonitorInfoW(monitor, &info)) return false;
  const auto& rect = info.rcMonitor;
  return SetWindowPos(window_, HWND_TOPMOST, rect.left, rect.top,
      rect.right - rect.left, rect.bottom - rect.top, SWP_NOACTIVATE) != FALSE;
}

uint64_t MenuOverlayWindow::Begin(HWND expected_foreground) {
  if (!window_ || !IsWindow(child_) || session_.wanted()) return 0;
  if (expected_foreground && GetForegroundWindow() != expected_foreground) return 0;
  return_target_ = GetForegroundWindow();
  return_pid_ = 0;
  if (return_target_) GetWindowThreadProcessId(return_target_, &return_pid_);
  if (!Fit(MonitorFromWindow(return_target_, MONITOR_DEFAULTTOPRIMARY))) return 0;
  const auto opening = session_.Begin();
  if (!SetTimer(window_, kFrameTimeout, 4000, nullptr)) {
    Hide();
    return 0;
  }
  return opening;
}

bool MenuOverlayWindow::Reveal(uint64_t opening) {
  if (!session_.AcceptFrame(opening)) return false;
  // If the user switched applications while Flutter prepared the frame, do not
  // reveal over that new task or steal focus back from it.
  if (!ReturnTargetValid() ||
      !IsMenuRevealForeground(GetForegroundWindow(), return_target_, window_)) {
    Hide(); return false;
  }
  KillTimer(window_, kFrameTimeout);
  ShowWindow(window_, SW_SHOWNOACTIVATE);
  if (!SetForegroundWindow(window_) || !Owns(GetForegroundWindow())) {
    Hide(); return false;
  }
  SetFocus(child_);
  return true;
}

void MenuOverlayWindow::Hide(bool return_focus) {
  const bool was_wanted = session_.wanted();
  const bool may_return = return_focus && Owns(GetForegroundWindow());
  session_.Dismiss(); // Do this before ShowWindow dispatches WM_ACTIVATE.
  if (window_) {
    KillTimer(window_, kFrameTimeout);
    if (Owns(GetCapture())) ReleaseCapture();
    ShowWindow(window_, SW_HIDE);
  }
  if (may_return && ReturnTargetValid() && IsWindowVisible(return_target_) &&
      !IsIconic(return_target_)) SetForegroundWindow(return_target_);
  return_target_ = nullptr;
  return_pid_ = 0;
  if (was_wanted && on_hidden && !destroying_) on_hidden();
}

void MenuOverlayWindow::SetLocalModal(bool active) {
  local_modal_ = active;
  if (active || !session_.wanted()) return;
  HWND foreground = GetForegroundWindow();
  HWND owner = foreground;
  while (owner && owner != window_) owner = GetWindow(owner, GW_OWNER);
  if (Owns(foreground) || owner == window_ ||
      (ReturnTargetValid() && foreground == return_target_)) {
    if (!Owns(foreground)) SetForegroundWindow(window_);
    SetFocus(child_);
  } else {
    Hide();
  }
}

bool MenuOverlayWindow::RegisterShortcut(UINT modifiers, UINT key) {
  if (!window_ || key == 0 || key > 0xff ||
      (modifiers & ~(MOD_ALT | MOD_CONTROL | MOD_SHIFT | MOD_WIN)) != 0) return false;
  const int candidate = shortcut_id_ == kShortcutA ? kShortcutB : kShortcutA;
  if (!RegisterHotKey(window_, candidate, modifiers | MOD_NOREPEAT, key)) return false;
  UnregisterShortcut();
  shortcut_id_ = candidate;
  return true;
}

void MenuOverlayWindow::UnregisterShortcut() {
  if (shortcut_id_ && window_) UnregisterHotKey(window_, shortcut_id_);
  shortcut_id_ = 0;
}

LRESULT CALLBACK MenuOverlayWindow::WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<MenuOverlayWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<MenuOverlayWindow*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->window_ = window;
  }
  if (!self) return DefWindowProcW(window, message, wparam, lparam);
  switch (message) {
    case WM_DWMCOMPOSITIONCHANGED:
      if (!self->ConfigureComposition()) self->Hide();
      break;
    case WM_CLOSE: self->Hide(true); return 0;
    case WM_HOTKEY:
      if (static_cast<int>(wparam) == self->shortcut_id_ && self->on_shortcut) self->on_shortcut();
      return 0;
    case WM_TIMER:
      if (wparam == kFrameTimeout) { self->Hide(); return 0; }
      break;
    case WM_ACTIVATE:
      if (!self->local_modal_ && LOWORD(wparam) == WA_INACTIVE && !self->Owns(reinterpret_cast<HWND>(lparam))) self->Hide();
      break;
    case WM_SETFOCUS:
      if (self->session_.phase() == MenuOverlaySession::Phase::visible && self->child_) SetFocus(self->child_);
      break;
    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
      if (self->session_.wanted() && !self->Fit(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST))) self->Hide();
      break;
    case WM_SIZE:
      if (self->child_) {
        RECT rect{};
        GetClientRect(window, &rect);
        MoveWindow(self->child_, 0, 0, rect.right, rect.bottom, TRUE);
      }
      break;
    case WM_NCDESTROY:
      self->window_ = nullptr;
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      break;
  }
  if (self->on_message) {
    const auto result = self->on_message(window, message, wparam, lparam);
    if (result) return *result;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
