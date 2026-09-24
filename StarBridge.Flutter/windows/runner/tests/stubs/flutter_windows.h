#pragma once
#include <windows.h>
// Native regression links the real Win32Window without starting a Flutter engine.
UINT FlutterDesktopGetDpiForMonitor(HMONITOR monitor);
UINT FlutterDesktopGetDpiForHWND(HWND window);
