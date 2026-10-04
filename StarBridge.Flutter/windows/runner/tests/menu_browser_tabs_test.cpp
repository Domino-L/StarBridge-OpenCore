#include "menu_local_tools.h"
#include <chrono>
#include <cstdio>
#include <set>
#include <limits>

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
Response ConfigureOptions(MenuLocalTools& tools, const Map& options) {
  Response response;
  tools.Handle(Map{{Value("action"), Value("browserConfigure")}, {Value("preferences"), Value(options)}}, std::make_unique<Result>(response));
  return response;
}
Response Configure(MenuLocalTools& tools, int32_t limit, bool links, bool pause) {
  return ConfigureOptions(tools, Map{
    {Value("provider"), Value("bing-global")}, {Value("tabLimit"), Value(limit)},
    {Value("openLinksInNewTab"), Value(links)}, {Value("pauseWhenHidden"), Value(pause)}});
}
std::string Active(const Map& state) { return std::get<std::string>(state.at(Value("activeTabId"))); }
List Tabs(const Map& state) { return std::get<List>(state.at(Value("tabs"))); }
Map Visual(MenuLocalTools& tools) { return std::get<Map>(Call(tools, "browserTestVisualState").value); }
void Bounds(MenuLocalTools& tools, double x, double y, double width, double height, bool visible, const List& occlusions = {}, double opacity = 1) {
  Response response;
  tools.Handle(Map{{Value("action"), Value("browserBounds")}, {Value("x"), Value(x)}, {Value("y"), Value(y)},
    {Value("width"), Value(width)}, {Value("height"), Value(height)}, {Value("visible"), Value(visible)},
    {Value("occlusions"), Value(occlusions)}, {Value("opacity"), Value(opacity)}}, std::make_unique<Result>(response));
}
bool Interaction(MenuLocalTools& tools, double x, double y, bool focused = false) {
  Response response;
  tools.Handle(Map{{Value("action"), Value("browserTestInteraction")}, {Value("x"), Value(x)},
    {Value("y"), Value(y)}, {Value("focused"), Value(focused)}}, std::make_unique<Result>(response));
  return std::get<bool>(response.value);
}
bool ViewportContains(HWND parent, MenuLocalTools& tools, int x, int y) {
  const auto visual = Visual(tools);
  HWND child = GetWindow(parent, GW_CHILD);
  for (const auto& value : std::get<List>(visual.at(Value("children")))) {
    if (std::get<bool>(std::get<Map>(value).at(Value("browserViewport")))) {
      HRGN region = CreateRectRgn(0, 0, 0, 0);
      const int kind = GetWindowRgn(child, region);
      const bool inside = kind != ERROR && PtInRegion(region, x, y);
      DeleteObject(region);
      return inside;
    }
    child = GetWindow(child, GW_HWNDNEXT);
  }
  return false;
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
    MenuLocalTools tools(window, [] { return true; }, [](bool) {}, [] {});
    const std::string home = "http://127.0.0.1:9/search-home";
    check(Call(tools, "browserOpen", "", "javascript:alert(1)").error == "menu.browser_failed",
        "unsafe initial homepage rejected before tab creation");
    Call(tools, "browserOpen", "", home);
    auto state = State(tools);
    const auto first = Active(state);
    check(std::get<std::string>(state.at(Value("url"))) == home,
        "initial homepage is queued before asynchronous controller creation");
    Call(tools, "browserOpen", "", "http://127.0.0.1:9/other");
    check(Active(State(tools)) == first && std::get<std::string>(State(tools).at(Value("url"))) == home,
        "reopening never overwrites retained page with homepage");
    Call(tools, "browserNewTab", "", home);
    check(std::get<std::string>(State(tools).at(Value("url"))) == home && Tabs(State(tools)).size() == 2,
        "new tab queues selected homepage without a followup navigate race");
    const auto second = Active(State(tools));
    Call(tools, "browserCloseTab", first, home);
    Call(tools, "browserCloseTab", second, home);
    check(Tabs(State(tools)).size() == 1 && std::get<std::string>(State(tools).at(Value("url"))) == home,
        "closing final tab creates replacement with selected homepage");
    check(Call(tools, "browserNewTab", "", "file:///C:/private").error == "menu.browser_failed" && Tabs(State(tools)).size() == 1,
        "unsafe new-tab URL cannot add a page");
  }
  {
    bool current = true;
    MenuLocalTools tools(window, [&current] { return current; }, [](bool) {}, [] {});
    check(Call(tools, "browserOpen").replies == 1, "open replies once without blocking controller creation");
    const auto first = Active(State(tools));
    check(!first.empty() && Tabs(State(tools)).size() == 1, "one native identity on first open");
    Call(tools, "browserOpen");
    check(Active(State(tools)) == first && Tabs(State(tools)).size() == 1, "open is idempotent while pending");
    for (int i = 0; i < 7; ++i) Call(tools, "browserNewTab");
    const auto full = State(tools);
    std::set<std::string> ids;
    for (const auto& value : Tabs(full)) ids.insert(std::get<std::string>(std::get<Map>(value).at(Value("id"))));
    check(ids.size() == 8 && std::get<int32_t>(full.at(Value("tabLimit"))) == 8, "eight unique native IDs and WPF default cap");
    check(Call(tools, "browserNewTab").error == "menu.browser_tab_limit" && Tabs(State(tools)).size() == 8, "ninth tab rejected");
    check(Configure(tools, 1, true, true).error.empty() && Tabs(State(tools)).size() == 8 &&
        std::get<int32_t>(State(tools).at(Value("tabLimit"))) == 1, "lowering limit retains eight existing native identities");
    check(Call(tools, "browserNewTab").error == "menu.browser_tab_limit", "lowered cap blocks new tab");
    check(Configure(tools, 0, true, true).error == "menu.browser_preferences_invalid" &&
        std::get<int32_t>(State(tools).at(Value("tabLimit"))) == 1, "invalid cap preserves current options");
    check(Configure(tools, 13, true, true).error == "menu.browser_preferences_invalid", "absolute cap remains twelve");
    const Map valid{{Value("provider"), Value("bing-global")}, {Value("tabLimit"), Value(1)},
        {Value("openLinksInNewTab"), Value(true)}, {Value("pauseWhenHidden"), Value(true)}};
    for (const auto& field : Map{{Value("provider"), Value("unknown")}, {Value("tabLimit"), Value(1.5)},
        {Value("openLinksInNewTab"), Value("true")}, {Value("pauseWhenHidden"), Value(1)}}) {
      auto invalid = valid; invalid[field.first] = field.second;
      check(ConfigureOptions(tools, invalid).error == "menu.browser_preferences_invalid" &&
          std::get<int32_t>(State(tools).at(Value("tabLimit"))) == 1,
          "invalid native preference type or provider preserves existing settings");
    }
    auto extra = valid; extra.emplace(Value("url"), Value("https://example.invalid/"));
    check(ConfigureOptions(tools, extra).error == "menu.browser_preferences_invalid", "browser preferences cannot carry a URL");
    auto missing = valid; missing.erase(Value("pauseWhenHidden"));
    check(ConfigureOptions(tools, missing).error == "menu.browser_preferences_invalid", "partial native preferences rejected");
    Configure(tools, 12, true, true);
    for (int i = 0; i < 4; ++i) Call(tools, "browserNewTab");
    check(Tabs(State(tools)).size() == 12 && Call(tools, "browserNewTab").error == "menu.browser_tab_limit", "configured twelve native tabs, thirteenth denied");
    Configure(tools, 8, true, true);
    const auto active_after_growth = Active(State(tools));
    check(Call(tools, "browserCloseTab", first).error.empty() && Active(State(tools)) == active_after_growth, "background close preserves active while creation pending");
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
    const auto cover = [](double x, double y, double width, double height) {
      return Value(Map{{Value("x"), Value(x)}, {Value("y"), Value(y)},
        {Value("width"), Value(width)}, {Value("height"), Value(height)}});
    };
    Bounds(tools, 100, 120, 500, 300, true, {cover(100, 120, 220, 300)});
    check(std::get<bool>(Controller(tools, reset_id).at(Value("visible"))) &&
        !ViewportContains(window, tools, 50, 100) && ViewportContains(window, tools, 300, 100),
        "background browser retains uncovered pixels and excludes foreground panel hit area");
    Bounds(tools, 100, 120, 500, 300, true, {cover(100, 120, 220, 300)}, .7);
    printf("IDLE|alpha=%d|supported=%d\n", std::get<int32_t>(Visual(tools).at(Value("alpha"))), std::get<bool>(State(tools).at(Value("opacitySupported"))));
    check(std::get<int32_t>(Visual(tools).at(Value("alpha"))) == 179 &&
        std::get<bool>(State(tools).at(Value("opacitySupported"))), "idle opacity reaches actual child HWND alpha");
    check(!Interaction(tools, 50, 100) && Interaction(tools, 300, 100) &&
        !Interaction(tools, 600, 100), "native hover uses viewport bounds and clipped region");
    check(Interaction(tools, 600, 100, true), "native keyboard focus conservatively protects editing");
    check(!ViewportContains(window, tools, 50, 100) && ViewportContains(window, tools, 300, 100) &&
        std::get<bool>(Controller(tools, reset_id).at(Value("visible"))), "faded viewport keeps clipping and controller visibility");
    Bounds(tools, 100, 120, 500, 300, false, {}, .7);
    check(!Interaction(tools, 300, 100, true), "hidden browser never reports active interaction");
    for (const double opacity : {1.0, std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::infinity(), -1.0}) {
      Bounds(tools, 100, 120, 500, 300, true, {}, opacity);
      check(std::get<int32_t>(Visual(tools).at(Value("alpha"))) == 255, "opaque restore and invalid opacity use safe full alpha");
    }
    Bounds(tools, 100, 120, 500, 300, true, {cover(300.5, 180.5, 80.25, 100.25), cover(500, 120, 100, 300)});
    check(ViewportContains(window, tools, 50, 100) && !ViewportContains(window, tools, 200, 60) &&
        !ViewportContains(window, tools, 280, 160) && !ViewportContains(window, tools, 450, 100),
        "moving multiple occluders updates region with outward physical pixel rounding");
    Bounds(tools, 100, 120, 500, 300, true, {cover(0, 0, 1000, 1000)});
    check(!std::get<bool>(Controller(tools, reset_id).at(Value("visible"))) &&
        !ViewportContains(window, tools, 100, 100), "fully covered viewport hides native controller");
    Bounds(tools, 100, 120, 500, 300, true, {Value("invalid")});
    check(!std::get<bool>(Visual(tools).at(Value("requestedVisible"))),
        "malformed occlusion fails closed instead of covering Flutter controls");
    Bounds(tools, 100, 120, 500, 300, true);
    check(ViewportContains(window, tools, 50, 100) && ViewportContains(window, tools, 450, 100),
        "activation clears stale clipped regions");
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
    check(Ready(tools), "page settles before resource policy checks");
    Bounds(tools, 100, 120, 500, 300, false);
    const auto suspend_deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (!std::get<bool>(Controller(tools, reset_id).at(Value("suspended"))) && std::chrono::steady_clock::now() < suspend_deadline) {
      Pump(); MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
    }
    check(std::get<bool>(Controller(tools, reset_id).at(Value("suspended"))), "hidden real WebView suspends with pause enabled");
    Configure(tools, 8, true, false); Pump();
    check(!std::get<bool>(Controller(tools, reset_id).at(Value("suspended"))) &&
        !std::get<bool>(Controller(tools, reset_id).at(Value("visible"))), "turning pause off resumes hidden page without showing it");
    Configure(tools, 8, true, true); Configure(tools, 8, true, false); Pump();
    check(!std::get<bool>(Controller(tools, reset_id).at(Value("suspended"))), "late suspension cannot freeze disabled pause policy");
    Bounds(tools, 100, 120, 500, 300, true);
    Call(tools, "browserTestPopup"); Call(tools, "browserTestUnsafeWindow");
    check(Tabs(State(tools)).size() == 1 && Active(State(tools)) == reset_id, "automatic popups and unsafe new-window schemes still denied");
    Configure(tools, 8, false, true);
    Call(tools, "browserTestNewWindow");
    check(Tabs(State(tools)).size() == 1 && Active(State(tools)) == reset_id, "new-window event consumer navigates current identity when option is off");
    Call(tools, "browserNavigate", reset_id, "about:blank"); Ready(tools);
    Configure(tools, 8, true, true);
    Call(tools, "browserTestNewWindow");
    const auto requested_tab = Active(State(tools));
    check(Tabs(State(tools)).size() == 2 && requested_tab != reset_id, "new-window event consumer creates native tab when option is on");
    Call(tools, "browserCloseTab", requested_tab);
    Configure(tools, 1, true, true);
    Call(tools, "browserTestNewWindow");
    check(Tabs(State(tools)).size() == 1 && Active(State(tools)) == reset_id, "new-window request at limit does not replace current page");
    Configure(tools, 8, true, true);
    tools.Hide(); current = false;
    check(Call(tools, "browserNewTab").error == "menu.closed", "closed menu rejects new pages");
    Pump(); current = true; Call(tools, "browserOpen");
    check(Active(State(tools)) == reset_id && Tabs(State(tools)).size() == 1, "ordinary hide preserves page identity");
    std::string multilingual = "https://example.invalid/";
    for (int i = 0; i < 1800; ++i) multilingual += "\xE6\x98\x9F";
    check(multilingual.size() > 4096 && Call(tools, "browserNavigate", reset_id, multilingual).error.empty(),
        "bounded multilingual resume URL uses UTF-16 character limit, not UTF-8 byte truncation");
    Call(tools, "browserStop", reset_id);
    Call(tools, "browserNavigate", reset_id, "about:blank");
    check(Ready(tools), "multilingual navigation leaves initialized browser usable");
    for (int i = 0; i < 2400; ++i) multilingual += "\xE6\x98\x9F";
    check(Call(tools, "browserNavigate", reset_id, multilingual).error == "menu.browser_failed",
        "multilingual URL still respects existing 4096 UTF-16 character cap");
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
