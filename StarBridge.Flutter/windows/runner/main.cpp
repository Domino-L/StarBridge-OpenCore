#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <string>
#include <thread>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutex[] =
    L"Local\\StarBridge.Flutter.Singleton.v1";
constexpr wchar_t kFlutterWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
// Keep the old title discoverable when an earlier client is already running.
constexpr const wchar_t* kWindowTitles[] = {
    L"StarBridge", L"\u661f\u6d77\u8230\u6865", L"\u661f\u6d77\u8266\u6a4b",
    L"starbridge_flutter"};

const wchar_t* ProductWindowTitle() {
  const LANGID language = GetUserDefaultUILanguage();
  if (PRIMARYLANGID(language) != LANG_CHINESE) return kWindowTitles[0];
  switch (language) {
    case 0x0404:
    case 0x0c04:
    case 0x1404:
      return kWindowTitles[2];
    default:
      return kWindowTitles[1];
  }
}
constexpr wchar_t kActivateInstanceMessage[] =
    L"StarBridge.Flutter.ActivateInstance.v1";

bool IsStartupLaunch(const std::vector<std::string>& arguments) {
  return std::any_of(arguments.begin(), arguments.end(), [](std::string value) {
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char character) {
                     return static_cast<char>(std::tolower(character));
                   });
    return value == "--startup";
  });
}

void ActivateExistingInstance(bool startup_launch) {
  if (startup_launch) {
    return;
  }
  HWND existing = nullptr;
  for (int attempt = 0; attempt < 40 && !existing; ++attempt) {
    for (const auto* title : kWindowTitles) {
      existing = FindWindowW(kFlutterWindowClass, title);
      if (existing) break;
    }
    if (!existing) {
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
  }
  if (!existing) {
    return;
  }
  PostMessageW(existing, RegisterWindowMessageW(kActivateInstanceMessage), 0,
               0);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  HANDLE single_instance = CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (single_instance && GetLastError() == ERROR_ALREADY_EXISTS) {
    const auto arguments = GetCommandLineArguments();
    ActivateExistingInstance(IsStartupLaunch(arguments));
    CloseHandle(single_instance);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool startup_launch = IsStartupLaunch(command_line_arguments);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, startup_launch);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(ProductWindowTitle(), origin, size)) {
    if (single_instance) {
      ReleaseMutex(single_instance);
      CloseHandle(single_instance);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance) {
    ReleaseMutex(single_instance);
    CloseHandle(single_instance);
  }
  return EXIT_SUCCESS;
}
