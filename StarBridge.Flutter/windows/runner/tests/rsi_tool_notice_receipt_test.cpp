#include <windows.h>
#include <winioctl.h>
#include <cstddef>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <vector>
#include <functional>
#include <memory>
#include "../rsi_tool_notice_async.h"
#include "../rsi_tool_notice_store.h"

namespace fs = std::filesystem;
using rsi_tool_notice::NoticeFolder;

// Mount-point junctions need no symbolic-link privilege; every link and
// target stays inside the scratch fixture.
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

fs::path Final(const fs::path& path) {
  const auto handle = CreateFileW(path.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS, nullptr);
  fs::path final_path;
  if (handle != INVALID_HANDLE_VALUE) {
    rsi_tool_notice::FinalPath(handle, final_path);
    CloseHandle(handle);
  }
  return final_path;
}

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  const auto root = fs::absolute(argv[1]) / (L"rsi-receipt-" + std::to_wstring(GetTickCount64()));
  // Callers supply a scratch directory, never a real user data root.
  if (fs::exists(root)) return 2;
  fs::create_directories(root / L"local");
  const auto local = Final(root / L"local");
  const NoticeFolder folder{local / L"StarBridge" / L"Notices", local / L"StarBridge" / L"Notices"};
  const auto marker = folder.spelled / L"rsiToolNotice.2026-11-03.seen";
  const auto temporary = folder.spelled / L"rsiToolNotice.2026-11-03.seen.tmp";
  int passed = 0, failed = 0;
  const auto check = [&](bool condition, const char* name) {
    if (condition) { ++passed; } else { ++failed; std::cerr << "FAIL " << name << '\n'; }
  };
  check(!local.empty(), "fixture final path resolved");

  check(!rsi_tool_notice::Read(folder), "missing is unread");
  check(rsi_tool_notice::Write(folder), "first acknowledgement creates folders and commits");
  check(rsi_tool_notice::Read(folder), "next launch reads committed marker");
  check(rsi_tool_notice::Write(folder), "acknowledgement is idempotent");
  { std::ofstream file(marker, std::ios::binary | std::ios::trunc); file << "partial"; }
  check(!rsi_tool_notice::Read(folder), "partial marker is unread");
  check(rsi_tool_notice::Write(folder), "partial marker can be replaced");
  { std::ofstream file(marker, std::ios::binary | std::ios::app); file << 'x'; }
  check(!rsi_tool_notice::Read(folder), "extra bytes invalidate marker");
  fs::remove(marker);
  fs::create_directory(marker);
  check(!rsi_tool_notice::Write(folder), "failed replacement reports failure");
  check(!rsi_tool_notice::Read(folder), "failed replacement remains unread");
  check(!fs::exists(temporary), "failed write leaves no temporary file");
  fs::remove(marker);

  const NoticeFolder wrong_case{folder.spelled, local / L"starbridge" / L"notices"};
  check(!rsi_tool_notice::Write(wrong_case) && !rsi_tool_notice::Read(wrong_case),
      "expected folder differing only in case is refused");

  {
    const rsi_tool_notice::PinnedFolder pinned(folder);
    check(pinned.Valid() && !MoveFileExW(folder.spelled.c_str(), (local / L"StarBridge" / L"moved").c_str(), 0),
        "pinned Notices folder cannot be renamed");
    check(pinned.Valid() && !MoveFileExW((local / L"StarBridge").c_str(), (local / L"moved").c_str(), 0),
        "ancestor of the pinned folder cannot be renamed");
  }

  // Notices itself is a link: nothing is written at the link target.
  const auto outside = root / L"outside";
  fs::create_directories(outside);
  fs::remove_all(local / L"StarBridge");
  fs::create_directories(local / L"StarBridge");
  const bool notices_link = Junction(folder.spelled, outside);
  check(notices_link, "Notices junction fixture created");
  check(notices_link && !rsi_tool_notice::Write(folder) && !rsi_tool_notice::Read(folder) &&
      fs::is_empty(outside), "Notices junction is refused without touching its target");
  RemoveDirectoryW(folder.spelled.c_str());

  // StarBridge is a link: no folder or marker is created at its target.
  RemoveDirectoryW((local / L"StarBridge").c_str());
  const bool app_link = Junction(local / L"StarBridge", outside);
  check(app_link, "StarBridge junction fixture created");
  check(app_link && !rsi_tool_notice::Write(folder) && fs::is_empty(outside),
      "StarBridge junction is refused without creating anything at its target");
  RemoveDirectoryW((local / L"StarBridge").c_str());

  // LocalAppData moved to another place: spelled through a link, expected is final.
  const auto alias = root / L"alias";
  const bool moved = Junction(alias, local);
  const NoticeFolder redirected{alias / L"StarBridge" / L"Notices", folder.expected};
  check(moved && rsi_tool_notice::Write(redirected) && rsi_tool_notice::Read(redirected) &&
      fs::exists(marker), "redirected LocalAppData still records the marker in the real folder");
  RemoveDirectoryW(alias.c_str());

  fs::remove_all(local / L"StarBridge");
  fs::remove_all(root);

  // Off-thread work: a stuck file operation must not hold the calling thread,
  // and a result that arrives after destruction must be dropped quietly.
  const auto pump_until = [](const std::function<bool()>& condition, DWORD limit) {
    const auto start = GetTickCount64();
    MSG message{};
    while (!condition() && GetTickCount64() - start < limit) {
      while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
      Sleep(5);
    }
    return condition();
  };
  {
    const auto release = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    rsi_tool_notice::AsyncWork work;
    bool called = false, value = false;
    const auto start = GetTickCount64();
    work.Submit([release] { WaitForSingleObject(release, 10000); return true; },
        [&](bool outcome) { called = true; value = outcome; });
    check(GetTickCount64() - start < 200 && work.Pending() == 1 && !called,
        "blocked work returns to the caller at once");
    pump_until([&] { return called; }, 300);
    check(!called, "no reply while the work is still blocked");
    SetEvent(release);
    check(pump_until([&] { return called; }, 3000) && value && work.Pending() == 0,
        "late result is delivered on the calling thread");
    CloseHandle(release);
  }
  {
    const auto release = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    auto called = std::make_shared<bool>(false);
    {
      rsi_tool_notice::AsyncWork work;
      work.Submit([release] { WaitForSingleObject(release, 10000); return true; },
          [called](bool) { *called = true; });
    }
    SetEvent(release);
    pump_until([] { return false; }, 300);
    check(!*called, "result after destruction is dropped without a reply");
    CloseHandle(release);
  }
  std::cout << "Native receipt: " << passed << " passed, " << failed << " failed\n";
  return failed ? 1 : 0;
}
