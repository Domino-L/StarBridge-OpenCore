#include "hangar_browser_data.h"
#include "hangar_browser_choice.h"
#include "hangar_browser_clear.h"
#include <winioctl.h>
#include <chrono>
#include <functional>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <vector>

namespace fs = std::filesystem;
using hangar_data::ClearBrowserData;
using hangar_data::ClearResult;

// Mount-point junctions work without the symbolic-link privilege. No shell or
// child process is needed, and every link and target stays inside the fixture.
bool Junction(const fs::path& link, const fs::path& target) {
  fs::create_directories(link);
  HANDLE handle = CreateFileW(link.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (handle == INVALID_HANDLE_VALUE) return false;
  struct MountPoint {
    DWORD tag;
    WORD length, reserved, substitute_offset, substitute_length, print_offset, print_length;
    wchar_t path[1];
  };
  const std::wstring substitute = L"\\??\\" + target.wstring();
  const auto name = target.wstring();
  const auto path_bytes = (substitute.size() + name.size() + 2) * sizeof(wchar_t);
  std::vector<BYTE> bytes(offsetof(MountPoint, path) + path_bytes, 0);
  auto* buffer = reinterpret_cast<MountPoint*>(bytes.data());
  buffer->tag = IO_REPARSE_TAG_MOUNT_POINT;
  buffer->length = static_cast<WORD>(bytes.size() - 8);
  buffer->substitute_length = static_cast<WORD>(substitute.size() * sizeof(wchar_t));
  buffer->print_offset = static_cast<WORD>((substitute.size() + 1) * sizeof(wchar_t));
  buffer->print_length = static_cast<WORD>(name.size() * sizeof(wchar_t));
  std::memcpy(buffer->path, substitute.c_str(), (substitute.size() + 1) * sizeof(wchar_t));
  std::memcpy(bytes.data() + offsetof(MountPoint, path) + buffer->print_offset,
      name.c_str(), (name.size() + 1) * sizeof(wchar_t));
  DWORD returned = 0;
  const bool ok = DeviceIoControl(handle, FSCTL_SET_REPARSE_POINT, bytes.data(),
      static_cast<DWORD>(bytes.size()), nullptr, 0, &returned, nullptr) != FALSE;
  CloseHandle(handle);
  return ok;
}

int main() {
  int failed = 0, passed = 0;
  auto check = [&](bool ok, const char* name) {
    std::printf("%s|%s\n", ok ? "PASS" : "FAIL", name);
    ok ? ++passed : ++failed;
  };
  const auto fixture = fs::current_path() / (L"hangar-clear-" +
      std::to_wstring(std::chrono::steady_clock::now().time_since_epoch().count()));
  const auto parent = fixture / L"StarBridge";
  const auto folder = parent / L"HangarReader";
  auto clear = [&](const fs::path& path) { return ClearBrowserData(path, folder); };
  fs::create_directories(folder / L"profile" / L"cache");
  const auto readonly = folder / L"profile" / L"cache" / L"data";
  std::ofstream(readonly) << "fixture";
  check(SetFileAttributesW(readonly.c_str(), FILE_ATTRIBUTE_READONLY) != FALSE,
      "read-only fixture created");
  std::ofstream(parent / L"saved-ships") << "keep";
  check(clear(folder) == ClearResult::success && !fs::exists(folder),
      "multi-level directory tree including read-only file is completely removed");
  check(fs::exists(parent / L"saved-ships"), "local saved ships outside browser folder survive");
  check(clear(folder) == ClearResult::success, "absent folder succeeds");
  HANDLE parent_writer = CreateFileW(parent.c_str(), FILE_WRITE_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS, nullptr);
  check(parent_writer != INVALID_HANDLE_VALUE && clear(folder) == ClearResult::success,
      "absent folder succeeds while its ordinary parent is held for writing");
  if (parent_writer != INVALID_HANDLE_VALUE) CloseHandle(parent_writer);
  check(clear(fixture / L"missing" / L"HangarReader") == ClearResult::success,
      "absent parent succeeds");

  const auto target = fixture / L"target";
  fs::create_directories(target);
  std::ofstream(target / L"keep") << "keep";
  const bool root_link = Junction(folder, target);
  check(root_link, "root junction fixture created");
  check(root_link && clear(folder) == ClearResult::unsafe_path &&
      fs::exists(target / L"keep"), "root junction is rejected without touching target");
  RemoveDirectoryW(folder.c_str());

  fs::create_directories(folder);
  const bool nested_link = Junction(folder / L"external", target);
  check(nested_link, "nested junction fixture created");
  check(nested_link && clear(folder) == ClearResult::success &&
      !fs::exists(folder) && fs::exists(target / L"keep"),
      "nested junction is removed without following its target");

  fs::create_directories(folder);
  std::ofstream(folder / L"keep") << "fixture";
  check(ClearBrowserData(folder, fixture / L"wrong" / L"HangarReader") == ClearResult::unsafe_path &&
      fs::exists(folder / L"keep"), "unexpected final root path is rejected before deleting contents");
  check(ClearBrowserData(folder, fixture / L"starbridge" / L"HangarReader") == ClearResult::unsafe_path &&
      fs::exists(folder / L"keep"), "expected root differing only in case is rejected");
  {
    // The legacy delete path must not clear read-only on a file that also has
    // a name outside the folder: the attribute is shared by every link.
    const auto inside = folder / L"linked";
    const auto outside = fixture / L"outside-link";
    std::ofstream(inside) << "fixture";
    const bool linked = CreateHardLinkW(outside.c_str(), inside.c_str(), nullptr) != FALSE &&
        SetFileAttributesW(inside.c_str(), FILE_ATTRIBUTE_READONLY) != FALSE;
    check(linked, "hard-linked read-only fixture created");
    hangar_data::DirectoryGuard root(folder);
    hangar_data::DirectoryGuard file(root.Get(), L"linked");
    const auto result = file.Valid() ? hangar_data::DeleteOpened(file.Get(), true) : ClearResult::busy;
    file.Release();
    root.Release();
    const auto attributes = GetFileAttributesW(outside.c_str());
    check(linked && result == ClearResult::failed && fs::exists(inside) &&
        attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_READONLY),
        "legacy delete refuses a read-only file with another hard link");
    SetFileAttributesW(inside.c_str(), FILE_ATTRIBUTE_NORMAL);
    DeleteFileW(outside.c_str());
    DeleteFileW(inside.c_str());
  }
  {
    hangar_data::DirectoryGuard root(folder);
    check(root.Valid() && !MoveFileExW(folder.c_str(), (parent / L"moved").c_str(), 0) &&
        fs::exists(folder / L"keep"), "held root handle prevents root rename");
    const auto child_path = folder / L"child";
    fs::create_directories(child_path);
    hangar_data::DirectoryGuard child(root.Get(), L"child");
    check(child.Valid() && !MoveFileExW(child_path.c_str(), (folder / L"moved-child").c_str(), 0),
        "held relative child handle prevents child rename");
    check(!hangar_data::SingleName(L"../target") && !hangar_data::SingleName(L"x:stream") &&
        !hangar_data::SingleName(L".."), "relative opens accept only single entry names");
  }
  check(clear(folder) == ClearResult::success, "clear succeeds after guard handles are released");

  // LocalAppData itself or its ancestors may legitimately be junctions.
  // The expected path is the actual final directory, not the alias spelling.
  const auto alias = fixture / L"appdata-alias";
  const bool ancestor_link = Junction(alias, fixture);
  check(ancestor_link, "redirected AppData fixture created");
  fs::create_directories(folder);
  std::ofstream(folder / L"data") << "fixture";
  check(ancestor_link && clear(alias / L"StarBridge" / L"HangarReader") == ClearResult::success &&
      !fs::exists(folder), "ancestor junction is allowed when final root matches expected path");
  fs::create_directories(target / L"StarBridge" / L"HangarReader");
  std::ofstream(target / L"StarBridge" / L"HangarReader" / L"keep") << "keep";
  RemoveDirectoryW(alias.c_str());
  const bool redirected = Junction(alias, target);
  check(redirected && clear(alias / L"StarBridge" / L"HangarReader") == ClearResult::unsafe_path &&
      fs::exists(target / L"StarBridge" / L"HangarReader" / L"keep"),
      "ancestor junction redirected outside expected final root is rejected");
  RemoveDirectoryW(alias.c_str());

  // Retarget an ancestor after validation. Traversal still uses the original
  // root's directory handle, so the new alias target can never be enumerated.
  fs::create_directories(folder / L"cache" / L"nested");
  std::ofstream(folder / L"cache" / L"nested" / L"data") << "fixture";
  const bool race_alias = Junction(alias, fixture);
  bool retargeted = false;
  ClearResult held_result = ClearResult::failed;
  {
    hangar_data::DirectoryGuard root(alias / L"StarBridge" / L"HangarReader");
    fs::path actual;
    const bool validated = root.Valid() && hangar_data::FinalPath(root.Get(), actual) &&
        hangar_data::SamePath(actual, folder);
    retargeted = validated && RemoveDirectoryW(alias.c_str()) && Junction(alias, target);
    if (retargeted) held_result = hangar_data::RemoveTree(root);
  }
  check(race_alias && retargeted && held_result == ClearResult::success && !fs::exists(folder) &&
      fs::exists(target / L"StarBridge" / L"HangarReader" / L"keep"),
      "retargeting ancestor after validation cannot redirect handle-based traversal");
  RemoveDirectoryW(alias.c_str());

  fs::create_directories(folder);
  std::ofstream(folder / L"locked") << "fixture";
  HANDLE locked = CreateFileW((folder / L"locked").c_str(), GENERIC_READ,
      FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  check(locked != INVALID_HANDLE_VALUE && clear(folder) == ClearResult::busy &&
      fs::exists(folder), "locked data cannot report success");
  if (locked != INVALID_HANDLE_VALUE) CloseHandle(locked);
  check(clear(folder) == ClearResult::success, "clear can be retried after lock release");
  check(clear(L"relative/HangarReader") == ClearResult::unsafe_path, "relative paths are rejected");
  check(hangar_data::SamePath(L"\\\\?\\G:\\Fixture\\HangarReader", L"G:\\Fixture\\HangarReader") &&
      hangar_data::SamePath(L"\\\\?\\UNC\\server\\share\\data", L"\\\\server\\share\\data") &&
      !hangar_data::SamePath(L"G:\\Fixture\\HangarReader", L"g:\\fixture\\hangarreader"),
      "final path comparison strips extended prefixes and is case-sensitive");
  fs::create_directories(folder);
  for (int i = 0; i < 500; ++i)
    std::ofstream(folder / (std::wstring(120, L'x') + std::to_wstring(i))) << "fixture";
  check(clear(folder) == ClearResult::success && !fs::exists(folder),
      "handle enumeration continues across multiple buffers while deleting entries");

  const auto legacy_file = parent / L"legacy-readonly";
  std::ofstream(legacy_file) << "fixture";
  SetFileAttributesW(legacy_file.c_str(), FILE_ATTRIBUTE_READONLY);
  {
    hangar_data::DirectoryGuard opened(legacy_file);
    check(opened.Valid() && hangar_data::DeleteOpened(opened.Get(), true) == ClearResult::success,
        "legacy disposition clears read-only attribute through the same handle");
  }
  check(!fs::exists(legacy_file), "legacy disposition removes entry when handle closes");

  // Exercise the same UI timer and one-shot gate used by PendingClear, without
  // starting WebView2, opening a visible window or touching a browser profile.
  int replies = 0;
  hangar_data::ClearWait timeout;
  const bool timer_started = timeout.Start([&] {
    if (timeout.Finish()) ++replies;
  }, 20);
  const auto deadline = GetTickCount64() + 1000;
  while (timer_started && !timeout.Finished() && GetTickCount64() < deadline) {
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 100, QS_ALLINPUT);
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
  }
  check(timer_started && timeout.Finished() && replies == 1 && !timeout.Finish(),
      "missing browser exit event times out once on UI thread");
  hangar_data::ClearWait event;
  const bool event_started = event.Start([&] { if (event.Finish()) ++replies; });
  const auto stale_event_timer = event.TimerId();
  if (event.Finish()) ++replies;
  hangar_data::ClearWait::OnTimer(nullptr, WM_TIMER, stale_event_timer, 0);
  check(event_started && replies == 2 && !event.Finish(),
      "exit event wins once and queued timeout cannot reply again");
  UINT_PTR destroyed_timer = 0;
  {
    hangar_data::ClearWait destroyed;
    destroyed.Start([&] { ++replies; });
    destroyed_timer = destroyed.TimerId();
  }
  hangar_data::ClearWait::OnTimer(nullptr, WM_TIMER, destroyed_timer, 0);
  check(destroyed_timer && replies == 2, "destruction cancels timer including queued callback");
  hangar_data::ClearWait early;
  const bool early_started = early.Start([&] { if (early.Finish()) ++replies; });
  hangar_data::ClearWait::OnTimer(nullptr, WM_TIMER, early.TimerId(), 0);
  check(early_started && !early.Finished() && replies == 2,
      "early stale callback cannot finish a newly allocated timer");
  early.Finish();
  hangar_data::ClearWait retry;
  const bool retry_started = retry.Start([&] { if (retry.Finish()) ++replies; }, 20);
  const auto retry_deadline = GetTickCount64() + 1000;
  while (retry_started && !retry.Finished() && GetTickCount64() < retry_deadline) {
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 100, QS_ALLINPUT);
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
  }
  check(retry_started && retry.Finished() && replies == 3,
      "new clear can complete after prior timeout");

  {
    // Build 66: deleting thousands of browser cache files on the UI thread made
    // the window "not responding". The deletion now runs on a worker thread and
    // replies on this thread through a thread timer.
    auto pump_until = [](const std::function<bool()>& done, ULONGLONG ms) {
      const auto until = GetTickCount64() + ms;
      while (!done() && GetTickCount64() < until) {
        MsgWaitForMultipleObjects(0, nullptr, FALSE, 50, QS_ALLINPUT);
        MSG message{};
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
      }
      return done();
    };
    auto fill = [](const fs::path& root, int dirs, int files) {
      for (int d = 0; d < dirs; ++d) {
        const auto dir = root / L"Default" / L"Cache" / (L"d" + std::to_wstring(d));
        fs::create_directories(dir);
        for (int f = 0; f < files; ++f) std::ofstream(dir / (L"f" + std::to_wstring(f))) << "cache";
      }
    };
    const auto bg_folder = fixture / L"bg" / L"HangarReader";
    fill(bg_folder, 20, 100);
    std::ofstream(fixture / L"bg" / L"saved-ships") << "keep";
    hangar_data::BackgroundClear background;
    bool replied = false;
    auto outcome = ClearResult::failed;
    const DWORD ui_thread = GetCurrentThreadId();
    DWORD reply_thread = 0;
    const bool started = background.Start(bg_folder, bg_folder, [&](ClearResult cleared) {
      replied = true; outcome = cleared; reply_thread = GetCurrentThreadId();
    });
    check(started && !replied && background.Busy(),
        "background clear returns at once without deleting on the calling thread");
    bool second_called = false;
    check(!background.Start(bg_folder, bg_folder, [&](ClearResult) { second_called = true; }) &&
        !second_called, "a second clear while one runs is refused, not queued");
    check(pump_until([&] { return replied; }, 30000) && outcome == ClearResult::success &&
        !fs::exists(bg_folder) && !background.Busy(),
        "background clear removes 2000 files and replies once it is done");
    check(reply_thread == ui_thread, "the reply arrives on the thread that started the clear");
    check(fs::exists(fixture / L"bg" / L"saved-ships"),
        "background clear leaves files outside the browser folder alone");

    // The same link-refusing checks apply on the worker thread.
    const auto bg_target = fixture / L"bg-target";
    fs::create_directories(bg_target);
    std::ofstream(bg_target / L"keep") << "keep";
    const auto bg_link = fixture / L"bg-link" / L"HangarReader";
    const bool bg_linked = Junction(bg_link, bg_target);
    replied = false;
    check(bg_linked && background.Start(bg_link, bg_link, [&](ClearResult cleared) {
      replied = true; outcome = cleared;
    }) && pump_until([&] { return replied; }, 10000) &&
        outcome == ClearResult::unsafe_path && fs::exists(bg_target / L"keep"),
        "background clear refuses a linked folder and keeps its target");
    if (bg_linked) RemoveDirectoryW(bg_link.c_str());

    // Destroyed while deleting (window closing): the worker only finishes
    // deleting; the reply never runs.
    const auto late_folder = fixture / L"bg-late" / L"HangarReader";
    fill(late_folder, 10, 100);
    bool late_called = false;
    {
      hangar_data::BackgroundClear late;
      late.Start(late_folder, late_folder, [&](ClearResult) { late_called = true; });
    }
    pump_until([&] { return !fs::exists(late_folder); }, 30000);
    pump_until([] { return false; }, 200);
    check(!late_called && !fs::exists(late_folder),
        "a clear outliving its owner finishes deleting without replying");
  }

  {
    // The RSI sign-in choice: no file means "don't remember" (new and upgraded
    // installs). The folder must be exactly the expected one, and a link, a
    // linked folder or a file with another name is never followed or changed.
    using hangar_choice::ReadRemember;
    using hangar_choice::WriteRemember;
    const auto home = fixture / L"choice-root";
    const auto choice = home / L"HangarReaderChoice";
    check(!ReadRemember(choice, home), "missing choice file means don't remember");
    check(hangar_choice::ReadChoice(choice, {}) == hangar_choice::Choice::unreadable,
        "an unresolved expected folder is unreadable, never don't remember");
    check(WriteRemember(choice, home, false) && !fs::exists(choice),
        "not remembering with no file succeeds without creating one");
    check(WriteRemember(choice, home, true) && ReadRemember(choice, home), "remember is written and read back");
    check(WriteRemember(choice, home, true) && ReadRemember(choice, home) && fs::file_size(choice) == 8,
        "writing remember twice keeps one exact value");
    {
      // Another program reading the choice must not turn it into "don't remember".
      const auto reader = CreateFileW(choice.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
          OPEN_EXISTING, 0, nullptr);
      check(reader != INVALID_HANDLE_VALUE && ReadRemember(choice, home),
          "a choice another program is reading still reads as remember");
      if (reader != INVALID_HANDLE_VALUE) CloseHandle(reader);
      const auto exclusive = CreateFileW(choice.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, 0, nullptr);
      check(exclusive != INVALID_HANDLE_VALUE &&
          hangar_choice::ReadChoice(choice, home) == hangar_choice::Choice::unreadable,
          "a choice held exclusively is unreadable, never don't remember");
      if (exclusive != INVALID_HANDLE_VALUE) CloseHandle(exclusive);
    }
    check(!ReadRemember(choice, fixture / L"elsewhere"), "a folder other than the expected one reads as don't remember");
    check(!WriteRemember(choice, fixture / L"elsewhere", false) && fs::exists(choice),
        "a folder other than the expected one is not changed");
    check(WriteRemember(choice, home, false) && !fs::exists(choice) && !ReadRemember(choice, home),
        "not remembering removes the file");
    std::ofstream(choice) << "remember-not";
    check(!ReadRemember(choice, home), "any other content means don't remember");
    fs::remove(choice);

    const auto elsewhere = fixture / L"choice-target";
    fs::create_directories(elsewhere);
    std::ofstream(elsewhere / L"keep") << "keep";
    const bool linked = Junction(choice, elsewhere);
    check(linked, "choice link fixture created");
    check(linked && !ReadRemember(choice, home), "a link in place of the choice reads as don't remember");
    check(linked && !WriteRemember(choice, home, true) && fs::exists(elsewhere / L"keep"),
        "remember refuses to write through a link");
    check(linked && !WriteRemember(choice, home, false) && fs::exists(elsewhere / L"keep"),
        "not remembering leaves a link and its target alone");
    RemoveDirectoryW(choice.c_str());

    // The folder holding the choice is itself a link to somewhere else.
    std::ofstream(elsewhere / L"HangarReaderChoice") << "remember";
    const auto linked_home = fixture / L"choice-linked-home";
    const bool home_link = Junction(linked_home, elsewhere);
    const auto through = linked_home / L"HangarReaderChoice";
    check(home_link, "linked choice folder fixture created");
    check(home_link && !ReadRemember(through, linked_home),
        "a choice reached through a linked folder reads as don't remember");
    check(home_link && !WriteRemember(through, linked_home, false) &&
        fs::exists(elsewhere / L"HangarReaderChoice"),
        "not remembering never deletes through a linked folder");
    check(home_link && !WriteRemember(through, linked_home, true) &&
        fs::file_size(elsewhere / L"HangarReaderChoice") == 8,
        "remembering never writes through a linked folder");
    RemoveDirectoryW(linked_home.c_str());

    // A choice file with a second name elsewhere is never overwritten.
    const auto other = fixture / L"other-name";
    std::ofstream(other) << "keep this content";
    const bool hard = CreateHardLinkW(choice.c_str(), other.c_str(), nullptr) != FALSE;
    check(hard, "hard-linked choice fixture created");
    check(hard && !WriteRemember(choice, home, true) && fs::file_size(other) == 17,
        "remember refuses a file with another name");
    check(hard && !WriteRemember(choice, home, false) && fs::exists(choice),
        "not remembering refuses a file with another name");
    DeleteFileW(choice.c_str());
  }

  fs::remove_all(fixture);
  std::printf("%d passed, %d failed\n", passed, failed);
  return failed ? 1 : 0;
}
