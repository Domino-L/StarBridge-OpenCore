#include <windows.h>
#include <cstdio>
#include <string>

// Exercise the actual native Reveal method while every focus/show operation
// is substituted. The fixture never reveals an HWND or changes OS focus.
static HWND observed_foreground = nullptr;
static HWND game_target = nullptr;
static HWND unrelated_target = nullptr;
static HWND focus_target = nullptr;
enum class Scenario { denied_then_handoff, direct, moved_with_false_result,
  delayed_foreground, delayed_null_foreground, retried_delayed_null_foreground, denied_null_foreground,
  attach_denied, external_switch, switch_during_attach, retry_denied, canceled_during_activation,
  moved_to_menu_during_attach, moved_to_child_during_attach,
  canceled_during_attach, destroyed_target_during_attach };
static Scenario scenario = Scenario::denied_then_handoff;
static bool attached = false;
static int attach_count = 0, detach_count = 0, activation_count = 0, raise_count = 0;
static ULONGLONG observed_tick = 100;
ULONGLONG ProbeGetTickCount64() { return observed_tick; }
HWND ActualForeground() { return ::GetForegroundWindow(); }
HWND ProbeGetForegroundWindow() { return observed_foreground; }
BOOL ProbeSetForegroundWindow(HWND window) {
  focus_target = window;
  ++activation_count;
  if (scenario == Scenario::delayed_foreground) return TRUE;
  if (scenario == Scenario::denied_null_foreground) { observed_foreground=nullptr; return FALSE; }
  if (scenario == Scenario::delayed_null_foreground ||
      (scenario == Scenario::retried_delayed_null_foreground && attached)) {
    observed_foreground=nullptr;
    return TRUE;
  }
  if (scenario == Scenario::canceled_during_activation) {
    SendMessageW(window, WM_ACTIVATE, WA_INACTIVE, reinterpret_cast<LPARAM>(unrelated_target));
    return FALSE;
  }
  if (scenario == Scenario::external_switch) { observed_foreground=unrelated_target; return FALSE; }
  if (scenario == Scenario::direct || scenario == Scenario::moved_with_false_result) {
    observed_foreground=window; return scenario == Scenario::direct;
  }
  if (!attached) return FALSE; // Windows denies the direct background request.
  if (scenario == Scenario::retry_denied) return FALSE;
  observed_foreground = window;
  return TRUE;
}
BOOL ProbeShowWindow(HWND, int) { return FALSE; }
HWND ProbeSetFocus(HWND window) { return window; }
HWND ProbeSetActiveWindow(HWND window) { return window; }
BOOL ProbeBringWindowToTop(HWND) { ++raise_count; return TRUE; }
BOOL ProbeAttachThreadInput(DWORD, DWORD, BOOL attach) {
  if (attach && scenario == Scenario::attach_denied) return FALSE;
  attached = attach != FALSE;
  if (attach) ++attach_count; else ++detach_count;
  if (attach && scenario == Scenario::switch_during_attach) observed_foreground=unrelated_target;
  // Real Windows input-queue attachment can itself make the already-active
  // menu/view become foreground before an explicit activation retry.
  if (attach && scenario == Scenario::moved_to_menu_during_attach) observed_foreground=focus_target;
  if (attach && scenario == Scenario::moved_to_child_during_attach)
    observed_foreground=::GetWindow(focus_target, GW_CHILD);
  if (attach && scenario == Scenario::canceled_during_attach) {
    observed_foreground=unrelated_target;
    SendMessageW(focus_target, WM_ACTIVATE, WA_INACTIVE, reinterpret_cast<LPARAM>(unrelated_target));
  }
  if (attach && scenario == Scenario::destroyed_target_during_attach) {
    ::DestroyWindow(game_target);
    observed_foreground=focus_target;
  }
  return TRUE;
}
DWORD ProbeGetWindowThreadProcessId(HWND window, LPDWORD process) {
  const DWORD thread = ::GetWindowThreadProcessId(window, process);
  return window == game_target ? ::GetCurrentThreadId() + 1 : thread;
}
// Fixture targets stay hidden on the real desktop; model the game as visible.
BOOL ProbeIsWindowVisible(HWND window) {
  return window && window == game_target ? ::IsWindow(window) : ::IsWindowVisible(window);
}
#define GetForegroundWindow ProbeGetForegroundWindow
#define IsWindowVisible ProbeIsWindowVisible
#define SetForegroundWindow ProbeSetForegroundWindow
#define ShowWindow ProbeShowWindow
#define SetFocus ProbeSetFocus
#define SetActiveWindow ProbeSetActiveWindow
#define BringWindowToTop ProbeBringWindowToTop
#define AttachThreadInput ProbeAttachThreadInput
#define GetWindowThreadProcessId ProbeGetWindowThreadProcessId
#define GetTickCount64 ProbeGetTickCount64
#ifndef MENU_WINDOW_SOURCE
#define MENU_WINDOW_SOURCE "../menu_overlay_window.cpp"
#endif
#include MENU_WINDOW_SOURCE

int main() {
  const HWND actual_foreground=ActualForeground();
  game_target = CreateWindowExW(0, L"STATIC", L"", WS_POPUP, 0, 0, 10, 10,
      nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  observed_foreground = game_target;
  unrelated_target = CreateWindowExW(0, L"STATIC", L"", WS_POPUP, 0, 0, 10, 10,
      nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  int failed = 0;
  auto check = [&failed](bool condition, const char* name) {
    std::printf("%s|%s\n", condition ? "PASS" : "FAIL", name);
    if (!condition) ++failed;
  };
  {
    MenuOverlayWindow menu;
    check(menu.Create(), "create hidden fixture");
    HWND child = CreateWindowExW(0, L"STATIC", L"", WS_CHILD, 0, 0, 10, 10,
        menu.handle(), nullptr, GetModuleHandleW(nullptr), nullptr);
    check(menu.Attach(child), "attach hidden fixture child");
    const auto opening = menu.Begin(game_target, true);
    check(opening > 0, "actual Begin accepts unchanged game target");
    check(menu.Reveal(opening), "game hotkey reveals after direct foreground activation is denied");
    check(menu.session().phase() == MenuOverlaySession::Phase::visible,
        "accepted opening retains visible lease");
    check(::IsWindowEnabled(menu.handle()) != FALSE, "revealed menu is enabled for input");
    menu.Hide();
    check(!::IsWindowEnabled(menu.handle()), "hidden menu is disabled again");
    check(activation_count >= 2, "bounded foreground handoff retries activation");
    check(attach_count == 1 && detach_count == 1 && !attached,
        "input attachment is always released");
    check(!::IsWindowVisible(menu.handle()), "fixture never displays an OS window");
  }
  {
    // Settings and preview openings carry no permission: refused means closed, no queue join.
    scenario=Scenario::denied_then_handoff; attached=false; attach_count=detach_count=activation_count=raise_count=0;
    observed_foreground=game_target;
    MenuOverlayWindow menu;
    check(menu.Create(), "unpermitted opening creates hidden fixture");
    HWND child=CreateWindowExW(0,L"STATIC",L"",WS_CHILD,0,0,10,10,
        menu.handle(),nullptr,GetModuleHandleW(nullptr),nullptr);
    check(menu.Attach(child), "unpermitted opening attaches child");
    const auto opening=menu.Begin(game_target);
    check(opening>0 && !menu.Reveal(opening), "a refused opening without permission closes");
    check(attach_count==0 && detach_count==0, "an opening without permission never joins an input queue");
    check(std::string(menu.hide_reason())=="handoffRefused", "the refusal names its reason");
  }
  for (const auto next : { Scenario::direct, Scenario::moved_with_false_result,
      Scenario::denied_null_foreground,
      Scenario::attach_denied, Scenario::external_switch, Scenario::switch_during_attach,
      Scenario::retry_denied, Scenario::canceled_during_activation,
      Scenario::moved_to_menu_during_attach, Scenario::moved_to_child_during_attach,
      Scenario::canceled_during_attach, Scenario::destroyed_target_during_attach }) {
    scenario=next; attached=false; attach_count=detach_count=activation_count=raise_count=0;
    observed_foreground=game_target;
    MenuOverlayWindow menu;
    check(menu.Create(), "scenario creates hidden menu");
    HWND child=CreateWindowExW(0,L"STATIC",L"",WS_CHILD,0,0,10,10,
        menu.handle(),nullptr,GetModuleHandleW(nullptr),nullptr);
    check(menu.Attach(child), "scenario attaches hidden child");
    const auto opening=menu.Begin(game_target, true);
    const bool moved_during_attach=next==Scenario::moved_to_menu_during_attach ||
        next==Scenario::moved_to_child_during_attach;
    const bool successful=next==Scenario::direct || next==Scenario::moved_with_false_result || moved_during_attach;
    check(menu.Reveal(opening)==successful, "Reveal follows actual ownership and cancels unsafe handoffs");
    check(menu.session().wanted()==successful, "failed handoff closes its opening lease");
    check((::IsWindowEnabled(menu.handle()) != FALSE)==successful, "only an accepted opening enables the menu");
    check(!attached && attach_count==detach_count, "all success and failure exits detach input");
    if(next==Scenario::external_switch || next==Scenario::switch_during_attach)
      check(observed_foreground==unrelated_target, "Alt-Tab target retains focus");
    if(next==Scenario::direct || next==Scenario::moved_with_false_result ||
        next==Scenario::external_switch || next==Scenario::canceled_during_activation)
      check(attach_count==0 && activation_count==1, "direct and revoked routes never attach queues");
    if(moved_during_attach) {
      check(observed_foreground==menu.handle() || ::IsChild(menu.handle(), observed_foreground),
          "ownership acquired during attachment remains accepted");
      check(attach_count==1 && detach_count==1 && activation_count==1 && raise_count==0,
          "successful attachment returns without a redundant activation and always detaches");
    }
    if(next==Scenario::canceled_during_attach)
      check(observed_foreground==unrelated_target && activation_count==1 && raise_count==0,
          "revocation during attachment preserves the user's external target");
    if(next==Scenario::destroyed_target_during_attach)
      check(!::IsWindow(game_target) && activation_count==1 && raise_count==0,
          "destroyed game target cancels even after menu acquires foreground");
    check(!::IsWindowVisible(menu.handle()), "scenario never displays an OS window");
  }
  {
    game_target=CreateWindowExW(0,L"STATIC",L"",WS_POPUP,0,0,10,10,
        nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
    observed_foreground=nullptr;
    MenuOverlayWindow menu;
    check(menu.Create(), "missing initial foreground creates hidden fixture");
    HWND child=CreateWindowExW(0,L"STATIC",L"",WS_CHILD,0,0,10,10,
        menu.handle(),nullptr,GetModuleHandleW(nullptr),nullptr);
    check(menu.Attach(child), "missing initial foreground attaches child");
    check(menu.Begin(game_target)==0 && !menu.session().wanted(),
        "NULL before Begin is not an accepted game hotkey opening");
    DestroyWindow(game_target);
  }
  // Windows may accept activation before GetForegroundWindow reflects it.
  // Reproduce the actual show -> hide -> late-foreground ordering without
  // changing the user's foreground or displaying a fixture window.
  for (const auto pending : {Scenario::delayed_foreground, Scenario::delayed_null_foreground,
      Scenario::retried_delayed_null_foreground}) {
  for (int outcome = 0; outcome < 7; ++outcome) {
    game_target=CreateWindowExW(0,L"STATIC",L"",WS_POPUP,0,0,10,10,
        nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
    scenario=pending;
    attach_count=detach_count=activation_count=raise_count=0;
    observed_foreground=game_target;
    MenuOverlayWindow menu;
    int visible_count=0, hidden_count=0;
    menu.on_visible=[&visible_count]() { ++visible_count; };
    menu.on_hidden=[&hidden_count]() { ++hidden_count; };
    check(menu.Create(), "delayed activation creates hidden fixture");
    HWND child=CreateWindowExW(0,L"STATIC",L"",WS_CHILD,0,0,10,10,
        menu.handle(),nullptr,GetModuleHandleW(nullptr),nullptr);
    check(menu.Attach(child), "delayed activation attaches child");
    const auto opening=menu.Begin(game_target, true);
    check(menu.Reveal(opening), "accepted asynchronous foreground request is not immediately hidden");
    check(menu.session().wanted(), "opening stays wanted until foreground acknowledgement");
    const int expected_attachments=pending==Scenario::retried_delayed_null_foreground ? 1 : 0;
    check(visible_count==0 && attach_count==expected_attachments && detach_count==attach_count && !attached,
        "accepted request never reports visible early; only a denied direct request uses the released fallback attachment");
    if (outcome == 0) {
      SendMessageW(menu.handle(), WM_ACTIVATE, WA_INACTIVE, reinterpret_cast<LPARAM>(game_target));
      check(menu.session().wanted(), "transitional game deactivation does not dismiss pending activation");
      observed_foreground=menu.handle();
    } else if (outcome == 1) observed_foreground=child;
    else if (outcome == 2) observed_foreground=unrelated_target;
    else if (outcome == 3) observed_tick+=751;
    else if (outcome == 4) menu.Hide(true);
    else if (outcome == 5) DestroyWindow(game_target);
    else SendMessageW(menu.handle(), WM_ACTIVATE, WA_INACTIVE, reinterpret_cast<LPARAM>(unrelated_target));
    SendMessageW(menu.handle(), WM_TIMER, 0x534f, 0);
    check(menu.session().wanted()==(outcome < 2),
        "late menu/child completes; external switch, timeout, close, invalid target and external cancel dismiss");
    check(visible_count==(outcome < 2 ? 1 : 0), "visible is reported only after actual input ownership");
    check(hidden_count==(outcome < 2 ? 0 : 1), "cancellation reports hidden once");
    if (outcome >= 2 && outcome != 4 && outcome != 5) {
      const char* expected = outcome == 2 ? "externalSwitch" : outcome == 3 ? "inputTimeout" : "deactivated";
      check(std::string(menu.hide_reason()) == expected, "pending handoff cancellation names its reason");
    }
    if(outcome >= 2) {
      // The cancelled request lands late on the hidden menu. Only a timeout or
      // close while the game still held foreground returns it to that game.
      observed_foreground=menu.handle();
      focus_target=nullptr;
      const int activations=activation_count;
      SendMessageW(menu.handle(), WM_ACTIVATE, WA_ACTIVE, 0);
      const bool returns=outcome == 3 || outcome == 4;
      check((focus_target==game_target && activation_count==activations + 1)==returns &&
          (returns || activation_count==activations),
          "late activation of a cancelled handoff returns only to the original game");
      observed_foreground=menu.handle();
      SendMessageW(menu.handle(), WM_ACTIVATE, WA_ACTIVE, 0);
      check(activation_count==activations + (returns ? 1 : 0),
          "abandoned handoff return is one-shot");
    }
    SendMessageW(menu.handle(), WM_TIMER, 0x534f, 0);
    check(visible_count==(outcome < 2 ? 1 : 0), "late timers never report a dismissed or duplicate opening");
    check(!::IsWindowVisible(menu.handle()), "delayed activation fixture stays hidden on the real desktop");
    DestroyWindow(game_target);
  }
  }
  DestroyWindow(game_target);
  DestroyWindow(unrelated_target);
  check(ActualForeground()==actual_foreground,"fixture never changes actual OS foreground");
  return failed == 0 ? 0 : 1;
}
