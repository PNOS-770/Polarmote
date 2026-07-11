# safe_layout_x

SafeLayoutX 是从主应用抽离出的通用开发骨架，用于承载可复用的 UI 安全层、布局层和通知组件。

## 模块结构

- `foundation/`：约束与溢出保护基础能力
- `flex/`、`containers/`、`text/`、`scroll/`：安全 UI 组件封装
- `dock/`、`panel/`、`state/`、`persistence/`：Dock 与面板骨架能力
- `banner/`：统一横幅通知系统
- `responsive/`、`theme/`、`debug/`、`plugins/`：响应式、主题、调试与扩展接口
- `shell/`：桌面/移动通用壳层（导航、抽屉、主区域）

## 使用方式

在主应用 `pubspec.yaml` 添加：

```yaml
dependencies:
  safe_layout_x:
    path: packages/safe_layout_x
```

导入统一入口：

```dart
import 'package:safe_layout_x/safe_layout_x.dart';
```

## UI 骨架二次开发

`shell/` 提供了可配置的桌面/移动壳层，业务只需传入导航项和内容插槽：

- `SafeDesktopShell`：桌面 Rail + 侧栏 + 主内容
- `SafeMobileShell`：移动 AppBar + Drawer + 主内容
- `SafeAdaptiveShell`：自动检测屏宽并切换桌面/移动壳
- `SafeResizablePane`：通用可拖拽侧栏
- `SafeSidePane`：通用侧栏内容区域（标题/动作/内容）
- `SafePanelLayout`：主面板四段布局（Top/Tab/Body/Bottom）
- `SafeActionBar`：可溢出保护的顶部动作条
- `SafeTabBar`：通用可配置标签栏
- `SafeStatusBar`：底部状态栏

支持通过样式对象快速改 UI：

- `SafeDesktopRailStyle`
- `SafeMobileShellStyle`
- `SafeResizablePaneStyle`

典型做法：

1. 在业务层拼装 `ShellNavItem` 列表（新增按钮、排序、显隐）。
2. 把业务内容作为 `main` / `drawerBody` / `pane` 传入骨架。
3. 通过 style 参数统一换导航栏视觉样式。
