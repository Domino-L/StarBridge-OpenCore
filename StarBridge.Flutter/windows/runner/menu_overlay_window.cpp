#include "menu_overlay_window.h"
#include "menu_overlay_focus.h"
#include <dwmapi.h>

namespace {
constexpr wchar_t kClass[] = L"StarBridge.Flutter.MenuOverlay.v1";
constexpr UINT_PTR kFrameTimeout = 0x534d;
constexpr UINT_PTR kInputAcknowledgement = 0x534f;
class ScopedMenuThreadInput {
 public:
  ScopedMenuThreadInput(DWORD current, DWORD target) : current_(current), target_(target),
      attached_(target && current != target && AttachThreadInput(current, target, TRUE)) {}
  ~ScopedMenuThreadInput() { if (attached_) AttachThreadInput(current_, target_, FALSE); }
  bool attached() const { return attached_; }
 private:
  DWORD current_, target_;
  bool attached_;
};
}

MenuOverlayWindow::~MenuOverlayWindow() {
  destroying_ = true;
  on_hidden = nullptr;
  on_visible = nullptr;
  on_message = nullptr;
  Hide();
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
  // Disabled while hidden: the engine focuses its own view during startup and
  // frame preparation, and SetFocus would otherwise activate this hidden HWND
  // and take foreground from an idle game. Only Reveal enables it.
  window_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kClass,
      L"StarBridge", WS_POPUP | WS_DISABLED, 0, 0, 1, 1, nullptr, nullptr, wc.hInstance, this);
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

bool MenuOverlayWindow::Prepare() {
  if (!window_ || !IsWindow(child_) || session_.wanted()) return false;
  // Same size Begin applies on the primary display, so a cold opening does not
  // also wait for the first full-size surface. Begin still refits per game.
  return Fit(MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY));
}

uint64_t MenuOverlayWindow::Begin(HWND expected_foreground, bool may_join_game_input) {
  if (!window_ || !IsWindow(child_) || session_.wanted()) return 0;
  if (expected_foreground && GetForegroundWindow() != expected_foreground) return 0;
  abandoned_target_ = nullptr;
  may_join_game_input_ = may_join_game_input;
  return_target_ = GetForegroundWindow();
  return_pid_ = 0;
  if (return_target_) GetWindowThreadProcessId(return_target_, &return_pid_);
  if (!Fit(MonitorFromWindow(return_target_, MONITOR_DEFAULTTOPRIMARY))) return 0;
  const auto opening = session_.Begin();
  if (!SetTimer(window_, kFrameTimeout, 4000, nullptr)) {
    Hide(false, "timerFailed");
    return 0;
  }
  return opening;
}

bool MenuOverlayWindow::TakeForegroundInput() {
  if (!session_.wanted() || !ReturnTargetValid() ||
      !IsMenuRevealForeground(GetForegroundWindow(), return_target_, window_)) return false;
  if (Owns(GetForegroundWindow())) return true;
  // A Host raw-input event does not grant the Flutter process foreground rights,
  // and Windows refuses this request in the game. A system hotkey never fires there
  // and Raw Input gives no right to pass on (both measured 2026-11-01), so the only
  // retry joins the game's input queue, for this one call. The user chose this.
  const bool requested = SetForegroundWindow(window_) != FALSE;
  if (!session_.wanted() || !ReturnTargetValid()) return false;
  const HWND after_request = GetForegroundWindow();
  if (Owns(after_request)) return true;
  // Only hand off from the original game HWND. An Alt-Tab to any other window
  // cancels the opening rather than pulling focus back from that application.
  // Across input queues Windows can accept activation before foreground
  // ownership changes. Let the platform loop acknowledge it; attaching here
  // would unnecessarily synchronize our UI with the game's input queue.
  if (requested && (!after_request || after_request == return_target_)) return true;
  if (after_request != return_target_ || !may_join_game_input_) return false;
  const DWORD foreground_thread = GetWindowThreadProcessId(return_target_, nullptr);
  ScopedMenuThreadInput input(GetCurrentThreadId(), foreground_thread);
  if (!input.attached() || !session_.wanted() || !ReturnTargetValid()) return false;
  // Input-queue attachment can finish the pending foreground handoff itself.
  // Accept our menu/view before requiring the game for an activation retry.
  if (Owns(GetForegroundWindow())) return true;
  if (GetForegroundWindow() != return_target_) return false;
  BringWindowToTop(window_);
  if (!session_.wanted() || !IsMenuRevealForeground(GetForegroundWindow(), return_target_, window_)) return false;
  const bool retried = SetForegroundWindow(window_) != FALSE;
  const HWND after_retry = GetForegroundWindow();
  return session_.wanted() && ReturnTargetValid() && (Owns(after_retry) ||
      (retried && (!after_retry || after_retry == return_target_)));
}

void MenuOverlayWindow::CheckForegroundInput() {
  if (!awaiting_input_ || !session_.wanted()) return;
  const HWND foreground = GetForegroundWindow();
  const char* reason = !ReturnTargetValid() ? "targetInvalid"
      : foreground && !IsMenuRevealForeground(foreground, return_target_, window_) ? "externalSwitch"
      : !Owns(foreground) && GetTickCount64() >= input_deadline_ ? "inputTimeout" : nullptr;
  if (reason) {
    Hide(true, reason);
    return;
  }
  if (!Owns(foreground)) return;
  awaiting_input_ = false;
  KillTimer(window_, kInputAcknowledgement);
  SetFocus(child_);
  if (session_.wanted() && on_visible) on_visible();
}

bool MenuOverlayWindow::Reveal(uint64_t opening) {
  if (!session_.AcceptFrame(opening)) return false;
  // If the user switched applications while Flutter prepared the frame, do not
  // reveal over that new task or steal focus back from it.
  if (!ReturnTargetValid() ||
      !IsMenuRevealForeground(GetForegroundWindow(), return_target_, window_)) {
    Hide(false, "switchedBeforeReveal"); return false;
  }
  KillTimer(window_, kFrameTimeout);
  awaiting_input_ = true;
  input_deadline_ = GetTickCount64() + 750;
  EnableWindow(window_, TRUE);
  ShowWindow(window_, SW_SHOWNOACTIVATE);
  if (!TakeForegroundInput() || !session_.wanted()) {
    Hide(true, "handoffRefused"); return false;
  }
  if (!SetTimer(window_, kInputAcknowledgement, 16, nullptr)) {
    Hide(true, "timerFailed"); return false;
  }
  CheckForegroundInput();
  return session_.wanted();
}

void MenuOverlayWindow::Hide(bool return_focus, const char* reason) {
  const bool was_wanted = session_.wanted();
  if (was_wanted) hide_reason_ = reason;
  const bool may_return = return_focus && Owns(GetForegroundWindow());
  // Unconfirmed handoff: Windows may still activate this hidden menu after the
  // cancel. Remember only the exact original game for a bounded return.
  const HWND foreground = GetForegroundWindow();
  if (awaiting_input_ && !may_return && ReturnTargetValid() &&
      (!foreground || foreground == return_target_)) {
    abandoned_target_ = return_target_;
    abandoned_pid_ = return_pid_;
    abandoned_deadline_ = GetTickCount64() + 2000;
  }
  session_.Dismiss(); // Do this before ShowWindow dispatches WM_ACTIVATE.
  awaiting_input_ = false;
  input_deadline_ = 0;
  local_modal_ = false;
  if (window_) {
    KillTimer(window_, kFrameTimeout);
    KillTimer(window_, kInputAcknowledgement);
    if (Owns(GetCapture())) ReleaseCapture();
    ShowWindow(window_, SW_HIDE);
    EnableWindow(window_, FALSE);
  }
  if (may_return && ReturnTargetValid() && IsWindowVisible(return_target_) &&
      !IsIconic(return_target_)) SetForegroundWindow(return_target_);
  return_target_ = nullptr;
  return_pid_ = 0;
  if (was_wanted && on_hidden && !destroying_) on_hidden();
}

void MenuOverlayWindow::ReturnAbandonedForeground() {
  const HWND target = abandoned_target_;
  abandoned_target_ = nullptr;
  DWORD pid = 0;
  // Only while this hidden menu holds foreground: a return, never a steal from
  // any other application, and never after the bounded handoff window.
  if (!target || GetTickCount64() >= abandoned_deadline_ || !Owns(GetForegroundWindow()) ||
      !IsWindow(target) || !GetWindowThreadProcessId(target, &pid) || pid != abandoned_pid_ ||
      !IsWindowVisible(target) || IsIconic(target)) return;
  SetForegroundWindow(target);
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
    Hide(false, "localModalLost");
  }
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
      if (!self->ConfigureComposition()) self->Hide(false, "composition");
      break;
    case WM_CLOSE: self->Hide(true, "closeMessage"); return 0;
    case WM_TIMER:
      if (wparam == kFrameTimeout) { self->Hide(false, "frameTimeout"); return 0; }
      if (wparam == kInputAcknowledgement) { self->CheckForegroundInput(); return 0; }
      break;
    case WM_ACTIVATE:
      if (LOWORD(wparam) != WA_INACTIVE && !self->session_.wanted()) {
        self->ReturnAbandonedForeground();
        break;
      }
      if (!self->local_modal_ && LOWORD(wparam) == WA_INACTIVE && !self->Owns(reinterpret_cast<HWND>(lparam))) {
        const HWND destination = reinterpret_cast<HWND>(lparam);
        const HWND foreground = GetForegroundWindow();
        const bool pending_handoff = self->awaiting_input_ &&
            (!destination || destination == self->return_target_) &&
            (!foreground || IsMenuRevealForeground(foreground, self->return_target_, window));
        if (!pending_handoff) {
          self->Hide(false, "deactivated");
          self->abandoned_target_ = nullptr; // The user chose another window.
        }
      }
      break;
    case WM_SETFOCUS:
      if (self->session_.phase() == MenuOverlaySession::Phase::visible && self->child_) SetFocus(self->child_);
      break;
    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
      if (self->session_.wanted() && !self->Fit(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST))) self->Hide(false, "display");
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
