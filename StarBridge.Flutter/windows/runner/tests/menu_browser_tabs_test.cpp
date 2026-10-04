#include "menu_local_tools.h"
#include <chrono>
#include <cstdio>
#include <set>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
struct Response { Value value; std::string error; int replies = 0; };
class Result : public flutter::MethodResult<Value> {
 public:
  explicit Result(Response& response) : response_(response) {}
 protected:
  void SuccessInternal(const Value* value) override { ++response_.replies; if (value) response_.value = *value; }
  void ErrorInternal(const std::string& error, const std::string&, const Value*) override { ++response_.replies; response_.error = error; }
  void NotImplementedInternal() override { ++response_.replies; response_.error = "notImplemented"; }
 private:
  Response& response_;
};
Response Call(MenuLocalTools& tools, const std::string& action, const std::string& tab = "", const std::string& url = "") {
  Response response;
  tools.Handle(Map{{Value("action"), Value(action)}, {Value("tabId"), Value(tab)}, {Value("url"), Value(url)}}, std::make_unique<Result>(response));
  return response;
}
Map State(MenuLocalTools& tools) { return std::get<Map>(Call(tools, "browserState").value); }
std::string Active(const Map& state) { return std::get<std::string>(state.at(Value("activeTabId"))); }
List Tabs(const Map& state) { return std::get<List>(state.at(Value("tabs"))); }
Map Visual(MenuLocalTools& tools) { return std::get<Map>(Call(tools, "browserTestVisualState").value); }
void Bounds(MenuLocalTools& tools, double x, double y, double width, double height, bool visible) {
  Response response;
  tools.Handle(Map{{Value("action"), Value("browserBounds")}, {Value("x"), Value(x)}, {Value("y"), Value(y)},
    {Value("width"), Value(width)}, {Value("height"), Value(height)}, {Value("visible"), Value(visible)}}, std::make_unique<Result>(response));
}
Map Controller(MenuLocalTools& tools, const std::string& id) {
  const auto visual = Visual(tools);
  for (const auto& value : std::get<List>(visual.at(Value("controllers")))) {
    const auto row = std::get<Map>(value);
    if (std::get<std::string>(row.at(Value("id"))) == id) return row;
  }
  return {};
}
bool ViewportOnTop(MenuLocalTools& tools, int x, int y) {
  const auto visual = Visual(tools);
  for (const auto& value : std::get<List>(visual.at(Value("children")))) {
    const auto child = std::get<Map>(value);
    if (std::get<bool>(child.at(Value("visibleStyle"))) &&
        std::get<int32_t>(child.at(Value("left"))) <= x && std::get<int32_t>(child.at(Value("right"))) > x &&
        std::get<int32_t>(child.at(Value("top"))) <= y && std::get<int32_t>(child.at(Value("bottom"))) > y) {
      return std::get<bool>(child.at(Value("browserViewport")));
    }
  }
  return false;
}
void Pump() {
  MSG message{};
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
}
bool Ready(MenuLocalTools& tools) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(20);
  while (std::chrono::steady_clock::now() < deadline) {
    Pump();
    const auto state = State(tools);
    if (!std::get<bool>(state.at(Value("loading")))) return !std::get<bool>(state.at(Value("failed")));
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
  }
  return false;
}
}
int main() {
  setvbuf(stdout, nullptr, _IONBF, 0);
  if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) return 2;
  const HWND window = CreateWindowExW(0, L"STATIC", L"Menu browser hidden fixture", WS_OVERLAPPED, 0, 0, 800, 600, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  if (!window) { CoUninitialize(); return 2; }
  // Match the native hierarchy: the fullscreen Flutter child is attached
  // before the WebView controller. Keep the owner hidden throughout.
  const HWND sibling = CreateWindowExW(0, L"STATIC", L"Synthetic Flutter sibling", WS_CHILD | WS_VISIBLE,
      0, 0, 800, 600, window, nullptr, GetModuleHandleW(nullptr), nullptr);
  int failed = 0;
  const auto check = [&failed](bool ok, const char* name) { printf("%s|%s\n", ok ? "PASS" : "FAIL", name); if (!ok) ++failed; };
  {
    bool current = true;
    MenuLocalTools tools(window, [&current] { return current; }, [](bool) {}, [] {});
    check(Call(tools, "browserOpen").replies == 1, "open replies once without blocking controller creation");
    const auto first = Active(State(tools));
    check(!first.empty() && Tabs(State(tools)).size() == 1, "one native identity on first open");
    Call(tools, "browserOpen");
    check(Active(State(tools)) == first && Tabs(State(tools)).size() == 1, "open is idempotent while pending");
    for (int i = 0; i < 7; ++i) Call(tools, "browserNewTab");
    const auto full = State(tools); const auto last = Active(full);
    std::set<std::string> ids;
    for (const auto& value : Tabs(full)) ids.insert(std::get<std::string>(std::get<Map>(value).at(Value("id"))));
    check(ids.size() == 8 && std::get<int32_t>(full.at(Value("tabLimit"))) == 8, "eight unique native IDs and WPF default cap");
    check(Call(tools, "browserNewTab").error == "menu.browser_tab_limit" && Tabs(State(tools)).size() == 8, "ninth tab rejected");
    check(Call(tools, "browserCloseTab", first).error.empty() && Active(State(tools)) == last, "background close preserves active while creation pending");
    check(Call(tools, "browserSelectTab", first).error == "menu.browser_tab_stale", "closed identity cannot be selected");
    for (const auto* action : {"browserNavigate", "browserBack", "browserForward", "browserReload", "browserStop", "browserFocus"}) {
      check(Call(tools, action, first, "about:blank").error == "menu.browser_tab_stale", action);
    }
    const auto remaining = Tabs(State(tools));
    const auto other = std::get<std::string>(std::get<Map>(remaining.front()).at(Value("id")));
    check(Call(tools, "browserNavigate", other, "about:blank").error == "menu.browser_tab_stale", "existing inactive tab cannot receive stale navigation");
    for (const auto& value : remaining) Call(tools, "browserCloseTab", std::get<std::string>(std::get<Map>(value).at(Value("id"))));
    const auto reset = State(tools); const auto reset_id = Active(reset);
    check(Tabs(reset).size() == 1 && ids.count(reset_id) == 0, "last close creates a fresh blank identity");
    check(Ready(tools), "real isolated WebView controller initializes after pending tabs closed");
    Bounds(tools, 100, 120, 500, 300, true);
    const auto visible = Controller(tools, reset_id);
    check(std::get<bool>(Visual(tools).at(Value("requestedVisible"))) && std::get<bool>(visible.at(Value("visible"))),
        "actual browserBounds requests and enables current controller");
    check(std::get<int32_t>(visible.at(Value("left"))) == 0 && std::get<int32_t>(visible.at(Value("top"))) == 0 &&
        std::get<int32_t>(visible.at(Value("right"))) == 500 && std::get<int32_t>(visible.at(Value("bottom"))) == 300,
        "controller bounds fill only their bounded viewport");
    std::string top_at_center;
    bool viewport_at_center = false;
    const auto children = std::get<List>(Visual(tools).at(Value("children")));
    for (const auto& item : children) {
      const auto child = std::get<Map>(item);
      printf("CHILD|%s|visible=%d|%d,%d,%d,%d\n", std::get<std::string>(child.at(Value("class"))).c_str(),
          std::get<bool>(child.at(Value("visibleStyle"))), std::get<int32_t>(child.at(Value("left"))),
          std::get<int32_t>(child.at(Value("top"))), std::get<int32_t>(child.at(Value("right"))), std::get<int32_t>(child.at(Value("bottom"))));
      if (top_at_center.empty() && std::get<bool>(child.at(Value("visibleStyle"))) &&
          std::get<int32_t>(child.at(Value("left"))) <= 350 && std::get<int32_t>(child.at(Value("right"))) > 350 &&
          std::get<int32_t>(child.at(Value("top"))) <= 270 && std::get<int32_t>(child.at(Value("bottom"))) > 270) {
        top_at_center = std::get<std::string>(child.at(Value("class")));
        viewport_at_center = std::get<bool>(child.at(Value("browserViewport")));
      }
    }
    check(viewport_at_center,
        "WebView content is not occluded by fullscreen Flutter sibling at its center");
    check(!ViewportOnTop(tools, 25, 25), "bounded viewport does not cover other Flutter panels");
    Call(tools, "browserNewTab");
    const auto switch_id = Active(State(tools));
    check(Ready(tools), "new tab initializes inside the same viewport");
    check(std::get<bool>(Controller(tools, switch_id).at(Value("visible"))) &&
        !std::get<bool>(Controller(tools, reset_id).at(Value("visible"))) && ViewportOnTop(tools, 350, 270),
        "switching tabs leaves only selected controller visible above sibling");
    Call(tools, "browserCloseTab", switch_id);
    check(Active(State(tools)) == reset_id && std::get<bool>(Controller(tools, reset_id).at(Value("visible"))) &&
        ViewportOnTop(tools, 350, 270), "closing selected tab restores previous page above sibling");
    Bounds(tools, -20, 100, 640, 300, true);
    check(std::get<bool>(Controller(tools, reset_id).at(Value("visible"))), "partially clipped valid WebView region remains enabled");
    Bounds(tools, 900, 100, 640, 300, true);
    check(!std::get<bool>(Controller(tools, reset_id).at(Value("visible"))), "entirely out-of-parent bounds hide controller");
    Bounds(tools, 100, 120, 500, 300, false);
    check(!std::get<bool>(Controller(tools, reset_id).at(Value("visible"))), "occluded browserBounds hides native controller");
    check(!ViewportOnTop(tools, 350, 270), "occluded viewport stops covering other panels");
    Bounds(tools, 100, 120, 500, 300, true);
    check(std::get<bool>(Controller(tools, reset_id).at(Value("visible"))) && ViewportOnTop(tools, 350, 270),
        "returning browserBounds restores controller and viewport above sibling");
    check(!std::get<bool>(State(tools).at(Value("unavailable"))), "ready controller is distinct from unavailable environment");
    check(Tabs(State(tools)).size() == 1 && Active(State(tools)) == reset_id, "late closed controllers cannot resurrect their tabs");
    for (const auto* url : {"file:///C:/", "javascript:alert(1)", "starbridge://account", "data:text/html,test"}) {
      check(Call(tools, "browserNavigate", reset_id, url).error == "menu.browser_failed", url);
      const auto rejected = State(tools);
      check(!std::get<bool>(rejected.at(Value("failed"))) && !std::get<bool>(rejected.at(Value("unavailable"))) &&
          !std::get<bool>(rejected.at(Value("loading"))), "rejected protocol leaves current page state intact");
    }
    Call(tools, "browserTestRejectedNavigation");
    const auto navigation_deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (std::get<int32_t>(State(tools).at(Value("rejectedNavigationCount"))) == 0 &&
        std::chrono::steady_clock::now() < navigation_deadline) {
      Pump(); MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
    }
    // Cancellation completion is a separate callback from NavigationStarting.
    // Observe the settled page, not its transient pending Source property.
    const auto settle = std::chrono::steady_clock::now() + std::chrono::milliseconds(100);
    while (std::chrono::steady_clock::now() < settle) { Pump(); MsgWaitForMultipleObjects(0, nullptr, FALSE, 10, QS_ALLINPUT); }
    const auto rejected_event = State(tools);
    check(std::get<int32_t>(rejected_event.at(Value("rejectedNavigationCount"))) == 1,
        "real NavigationStarting rejected the fixed inert data URI");
    check(!std::get<bool>(rejected_event.at(Value("failed"))) && !std::get<bool>(rejected_event.at(Value("loading"))) &&
        !std::get<bool>(rejected_event.at(Value("unavailable"))) &&
        std::get<std::string>(rejected_event.at(Value("url"))) == "about:blank",
        "NavigationStarting rejection preserves the current successful page");
    check(Call(tools, "browserReload", reset_id).error.empty(), "reload targets selected initialized tab");
    check(Call(tools, "browserStop", reset_id).error.empty(), "stop targets selected initialized tab");
    tools.Hide(); current = false;
    check(Call(tools, "browserNewTab").error == "menu.closed", "closed menu rejects new pages");
    Pump(); current = true; Call(tools, "browserOpen");
    check(Active(State(tools)) == reset_id && Tabs(State(tools)).size() == 1, "ordinary hide preserves page identity");
    Call(tools, "browserNewTab");
    const auto retired = Active(State(tools));
    tools.Reset();
    check(Call(tools, "browserState").error == "menu.browser_unavailable", "session reset immediately clears all page state");
    Call(tools, "browserOpen");
    check(Tabs(State(tools)).size() == 1 && Active(State(tools)) != retired, "next session starts with fresh blank tab");
    check(Call(tools, "browserSelectTab", retired).error == "menu.browser_tab_stale", "previous session tab identity is rejected");
    check(Ready(tools), "reset during pending creation allows fresh controller");
    Call(tools, "browserNewTab");
    // Destruction intentionally races a pending CreateController callback.
  }
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(1);
  while (std::chrono::steady_clock::now() < deadline) { Pump(); MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT); }
  check(!IsWindowVisible(window), "fixture never shows an acceptance window");
  check(IsWindow(sibling) != FALSE, "Flutter sibling survives browser controller lifecycles");
  DestroyWindow(window); CoUninitialize();
  return failed ? 1 : 0;
}
