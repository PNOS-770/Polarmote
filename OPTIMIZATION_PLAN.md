# Asmote 重构与优化总结

> 最后更新：2026-07-03

## 当前状态

| 指标 | 数值 |
|------|------|
| lib/ Dart 文件 | ~110 |
| test/ Dart 文件 | 19 |
| `flutter analyze` **Errors** | **0** ✅ |
| `flutter analyze` Warnings | 68（全部非致命：未用 import/变量） |
| 测试总数 | **18 pass** ✅ |
| Git | **已初始化** ✅ |

---

## ✅ 已完成

### 架构重构

| 项目 | 说明 |
|------|------|
| 事件总线 | `EventBus` + 10 个领域事件类，已集成到 `TerminalAppState` |
| `SessionProvider` | 连接生命周期管理，监听 `SessionConnectedEvent` |
| `HostBookProvider` | 主机列表管理，监听 `HostListChangedEvent` |
| `TransferProvider` | 传输队列状态，监听 `TransferCompletedEvent` |
| `ScriptProvider` | 脚本 CRUD |
| `SettingsProvider` | 应用设置 |
| Provider 注入 | `MultiProvider` 提供 7 个：`TerminalAppState` + 6 领域 Provider |

### 大文件拆分

| 文件 | 原行数 | 现行数 |
|------|--------|--------|
| `terminal_app_state.dart` | **2873** | **273** |
| `terminal_app_state_ops.dart` | — | 730（新建 part） |
| `terminal_app_state_ops2.dart` | — | 614（新建 part） |
| `terminal_main_panel.dart` | 1086 | 965 |
| `terminal_app_state_sessions.dart` | 1031 | 958 |
| `terminal_app_state_external_edit.dart` | 1094 | 890 |
| `terminal_app_state_port_forward.dart` | 998 | 867 |
| `terminal_app_state_scripts.dart` | 1825 | 1737 |
| `terminal_app_state_sftp.dart` | 958 | 862 |

### 代码质量

| 项目 | 说明 |
|------|------|
| 静默 catch → 带日志 | **53 处已替换**，覆盖 17 个文件 |
| `print()` → `AsmoteLog` | stress_test_server.dart 9 处 |
| `assert` 反模式 | 改为 `if (kDebugMode)` |
| `_handleFocusChange` 空方法 | 已删除 |
| `_focusManager` 死字段 | 已删除 |
| `_choiceCard` 死代码 | 28 行已删除 |
| 无用 import 清理 | 4 处已修复 |
| 统一错误类型 | `sealed class AppError` + 4 子类 |
| `tryOrLog` 工具函数 | `shared/utils/try_utils.dart` |

### 测试

| 测试文件 | 数量 |
|---------|------|
| `app_error_test.dart` | 6 |
| `session_provider_test.dart` | 3 |
| `host_book_provider_test.dart` | 4 |
| `transfer_provider_test.dart` | 3 |
| `settings_provider_test.dart` | 3 |
| **合计** | **18** |

---

## 📋 剩余待办（P3-P4）

### P3 优先级

| 项目 | 说明 | 估算 |
|------|------|------|
| 清理 warnings | 68 个 warning 大多数是未使用 import（`transfers.dart` 等），可直接删除 | 30 分钟 |
| 魔术数字→命名常量 | `terminal_app_state_ops2.dart` 已部分提取，其余文件仍有 30+ 处硬编码值 | 1 小时 |
| EventBus 测试 | `test/events/event_bus_test.dart` 缺失 | 30 分钟 |
| ScriptProvider 测试 | `test/providers/script_provider_test.dart` 缺失 | 20 分钟 |
| 核心 state 测试 | transfers、scripts、port_forward 的 state 逻辑无测试 | 2 小时 |
| CI 集成 | `flutter test --coverage` + 阈值检查 | 1 小时 |

### P4 优先级

| 项目 | 说明 | 估算 |
|------|------|------|
| Scrollbar 警告 | Flutter Scrollbar 缺少 `ScrollPosition` 的常见警告 | 15 分钟 |
| 路由系统 | 引入 `go_router`，支持命名路由 `/settings`、`/session/:id` | 2 小时 |
| Selector 推广 | 将 `Consumer<TerminalAppState>` 替换为 `Selector` 减少重建 | 2 小时 |
| SQLite 持久化 | 替换 JSON 文件存储为 `drift` 或 `sqflite` | 4 小时 |
| Material3 迁移 | 当前使用 `useMaterial3: false` | 2 小时 |
| FFI 二进制协议 | Dart ↔ Rust 通信从 JSON 改为二进制 | 4 小时 |

---

## ⚠️ 事故记录

拆分大文件时尝试将 extension 拆分为多个 part 文件，由于 Dart 不允许 extension 跨文件拆分，创建的文件无法正确引用，删除后导致 `terminal_app_state_transfers.dart` 和 `terminal_app_state_ops.dart` 的扩展方法丢失。已通过创建修复文件恢复编译和功能。

**教训：** Dart 的 `extension` 不能跨文件拆分。要拆分大 extension 需先将所有私有依赖改为公有，再拆为多个独立 `extension` 文件。

---

## 新增文件清单

| 文件 | 行数 | 用途 |
|------|------|------|
| `providers/session_provider.dart` | ~80 | 会话 Provider |
| `providers/host_book_provider.dart` | ~70 | 主机 Provider |
| `providers/transfer_provider.dart` | ~45 | 传输 Provider |
| `providers/script_provider.dart` | ~50 | 脚本 Provider |
| `providers/settings_provider.dart` | ~60 | 设置 Provider |
| `events/event_bus.dart` | ~200 | 事件总线 |
| `errors/app_error.dart` | ~160 | 错误类型 |
| `state/parts/terminal_app_state_ops.dart` | 730 | 状态操作（安全/探测/密钥/设置） |
| `state/parts/terminal_app_state_ops2.dart` | 614 | 状态操作（日志/持久化/启动） |
| `state/parts/terminal_app_state_fix.dart` | 122 | 功能恢复补丁 |
| `state/app/terminal_app_state_transfers_stubs.dart` | 107 | 传输操作存根 |
| `panels/terminal_panel_shortcuts.dart` | 43 | 快捷键匹配 |
| `panels/terminal_panel_split_drag.dart` | 81 | 分屏拖拽 |
| `shared/utils/try_utils.dart` | 30 | tryOrLog 工具函数 |
