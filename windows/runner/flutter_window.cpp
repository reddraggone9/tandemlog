#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <string>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  time_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "tandemlog/time",
      &flutter::StandardMethodCodec::GetInstance());
  time_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "start" || call.method_name() == "stop") {
      observe_time_ = call.method_name() == "start";
      result->Success(); return;
    }
    if (call.method_name() != "zone") { result->NotImplemented(); return; }
    DYNAMIC_TIME_ZONE_INFORMATION zone = {};
    const DWORD current_zone = GetDynamicTimeZoneInformation(&zone);
    if (current_zone == TIME_ZONE_ID_INVALID) {
      result->Error("zone", "Windows time zone unavailable"); return;
    }
    if (zone.DynamicDaylightTimeDisabled && zone.DaylightDate.wMonth != 0) {
      result->Error("zone", "Custom disabled-DST configuration is unsupported"); return;
    }
    // Windows provides ICU on supported Windows 10/11. Load only the system DLL.
    HMODULE icu = LoadLibraryExW(L"icu.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    using MapZone = int32_t (__cdecl*)(const wchar_t*, int32_t, const char*, wchar_t*, int32_t, int32_t*);
    auto map_zone = icu ? reinterpret_cast<MapZone>(GetProcAddress(icu, "ucal_getTimeZoneIDForWindowsID")) : nullptr;
    wchar_t iana[256] = {};
    int32_t status = 0;
    const int32_t length = map_zone ? map_zone(zone.TimeZoneKeyName, -1, nullptr, iana, 256, &status) : 0;
    if (icu) FreeLibrary(icu);
    if (status > 0 || length <= 0 || length >= 256) {
      result->Error("zone", "Windows to IANA time zone mapping unavailable"); return;
    }
    const int bytes = WideCharToMultiByte(CP_UTF8, 0, iana, length, nullptr, 0, nullptr, nullptr);
    std::string name(bytes, '\0');
    WideCharToMultiByte(CP_UTF8, 0, iana, length, name.data(), bytes, nullptr, nullptr);
    const LONG bias = zone.Bias + (current_zone == TIME_ZONE_ID_DAYLIGHT ? zone.DaylightBias : zone.StandardBias);
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("id"), flutter::EncodableValue(name)},
      {flutter::EncodableValue("offsetSeconds"), flutter::EncodableValue(static_cast<int32_t>(-bias * 60))}
    }));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  time_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (observe_time_ && time_channel_ &&
      (message == WM_TIMECHANGE || message == WM_SETTINGCHANGE)) {
    time_channel_->InvokeMethod("changed", nullptr);
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
