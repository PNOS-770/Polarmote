#include "flutter_window.h"

#include <chrono>
#include <functional>
#include <optional>
#include <sstream>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kMsgKeyboardRecovery = WM_APP + 0x124;
constexpr char kRecoveryChannelName[] = "asmote/runtime_recovery";

class StderrMirrorBuffer : public std::streambuf {
 public:
  StderrMirrorBuffer(std::streambuf* downstream,
                     std::function<void(const std::string&)> on_line)
      : downstream_(downstream), on_line_(std::move(on_line)) {}

 protected:
  int overflow(int ch) override {
    if (ch == EOF) {
      return sync() == 0 ? 0 : EOF;
    }
    const char c = static_cast<char>(ch);
    if (downstream_ != nullptr) {
      downstream_->sputc(c);
    }
    if (c == '\n') {
      FlushLine();
    } else if (c != '\r') {
      line_buffer_.push_back(c);
    }
    return ch;
  }

  int sync() override {
    if (downstream_ != nullptr) {
      downstream_->pubsync();
    }
    FlushLine();
    return 0;
  }

 private:
  void FlushLine() {
    if (line_buffer_.empty()) {
      return;
    }
    if (on_line_) {
      on_line_(line_buffer_);
    }
    line_buffer_.clear();
  }

  std::streambuf* downstream_;
  std::function<void(const std::string&)> on_line_;
  std::string line_buffer_;
};
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() { UninstallStderrMonitor(); }

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
  SetupRecoveryChannel();
  InstallStderrMonitor();
  RegisterPlugins(flutter_controller_->engine());
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
  UninstallStderrMonitor();
  runtime_recovery_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case kMsgKeyboardRecovery:
      NotifyKeyboardRecoveryRequested();
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetupRecoveryChannel() {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    return;
  }
  runtime_recovery_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kRecoveryChannelName,
          &flutter::StandardMethodCodec::GetInstance());
}

void FlutterWindow::InstallStderrMonitor() {
  if (stderr_monitor_buffer_ != nullptr) {
    return;
  }
  previous_stderr_buffer_ = std::cerr.rdbuf();
  stderr_monitor_buffer_ = std::make_unique<StderrMirrorBuffer>(
      previous_stderr_buffer_, [this](const std::string& line) {
        if (!ShouldTriggerRecoveryForLine(line)) {
          return;
        }
        if (GetHandle() != nullptr) {
          PostMessage(GetHandle(), kMsgKeyboardRecovery, 0, 0);
        }
      });
  std::cerr.rdbuf(stderr_monitor_buffer_.get());
}

void FlutterWindow::UninstallStderrMonitor() {
  if (previous_stderr_buffer_ != nullptr) {
    std::cerr.rdbuf(previous_stderr_buffer_);
    previous_stderr_buffer_ = nullptr;
  }
  stderr_monitor_buffer_.reset();
}

bool FlutterWindow::ShouldTriggerRecoveryForLine(const std::string& line) const {
  static auto last_trigger_at = std::chrono::steady_clock::time_point{};
  if (line.find("Unable to parse JSON message:") == std::string::npos &&
      line.find("The document is empty.") == std::string::npos) {
    return false;
  }
  const auto now = std::chrono::steady_clock::now();
  if (last_trigger_at.time_since_epoch().count() != 0 &&
      now - last_trigger_at < std::chrono::seconds(5)) {
    return false;
  }
  last_trigger_at = now;
  return true;
}

void FlutterWindow::NotifyKeyboardRecoveryRequested() {
  if (!runtime_recovery_channel_) {
    return;
  }
  runtime_recovery_channel_->InvokeMethod("keyboardJsonParseError", nullptr);
}
