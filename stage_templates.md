# Workspace 方案

> 将一组关联的远程主机组织为 **Workspace**，创建、编辑、进入、使用。

---

## 一、核心概念

```
Polarmote
├── Workspace: Production
│   ├── Stage: Web 服务器
│   │   ├── Host: prod-web-01
│   │   └── Host: prod-web-02
│   ├── Stage: 数据库
│   │   └── Host: prod-db-01
│   └── Stage: 监控
│       └── Host: grafana
├── Workspace: Staging
│   ├── Stage: Web
│   │   └── Host: stg-web-01
│   └── Stage: DB
│       └── Host: stg-db-01
└── Workspace: Dev
    └── Stage: Local
        └── Host: localhost
```

```
Workspace = 持久化组织结构
Stage     = 逻辑分组
Host      = 主机定义
Session   = 运行时连接（Stage 不关心 Session 生命周期）
```

---

## 二、数据模型

### 2.1 Workspace

```dart
class Workspace {
  final String id;
  String name;
  List<String> stageIds;        // 只存 ID，不直接持有 Stage 实体
  int sortOrder;
  DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toJson();
  factory Workspace.fromJson(Map<String, dynamic> json);
}
```

### 2.2 Stage

```dart
class Stage {
  final String id;
  String workspaceId;
  String name;
  List<String> hostIds;         // 该 Stage 关联的主机。不保存 Session

  Map<String, dynamic> toJson();
  factory Stage.fromJson(Map<String, dynamic> json);
}
```

### 2.3 规范化存储

```dart
// TerminalAppState 中
List<Workspace> workspaces;
Map<String, Stage> stageMap;   // id → Stage，方便按 workspaceId 查询
```

Workspace 通过 `stageIds` 引用 Stage，Stage 通过 `workspaceId` 反向引用，以 `stageIds` 为准。

### 2.4 模板（预留模型，暂不实现 UI）

```dart
class WorkspaceTemplate {
  final String id;
  String name;
  List<TemplateStage> stages;
  DateTime createdAt;
}
```

仅数据模型，不做 UI。为后续"另存为模板/从模板恢复"预留。

### 2.5 导航状态

```dart
enum AppPage { overview, workspace }

AppPage currentPage = AppPage.overview;
String? activeWorkspaceId;
```

---

## 三、用户体验流程

```
启动 ──→ 概览页
              │
              ├── 点击 [🚀 进入] ──→ Workspace 页
              │                        │
              │                        ├── 左侧 = 该 Workspace 的 Stage 树
              │                        ├── 右侧 = 终端显示区
              │                        └── [← 概览] → 返回概览页
              │
              ├── 点击 [+ 新建]
              ├── 编辑 Workspace
              └── 删除 Workspace
```

---

## 四、页面设计

### 4.1 概览页

Workspace 卡片横向排列，超出宽度自动换行。

```
┌─────────────────────────────────────────────────────────────────────┐
│  Polarmote                            [+ 新建] [⚙ 设置]           │
├─────────────────────────────────────────────────────────────────────┤
│  最近打开                                                           │
│  ┌──────────────┐  ┌──────────────┐                                │
│  │ Production   │  │ Staging      │                                │
│  │ 5 分钟前     │  │ 2 小时前     │                                │
│  └──────────────┘  └──────────────┘                                │
│                                                                     │
│  所有 Workspace                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────┐ │
│  │ Production   │  │ Staging      │  │ Dev          │  │  +     │ │
│  │  [✎] [×]    │  │  [✎] [×]    │  │  [✎] [×]    │  │ 新建   │ │
│  │━━━━━━━━━━━━━━│  │━━━━━━━━━━━━━━│  │━━━━━━━━━━━━━━│  └────────┘ │
│  │ 🖥  6 Hosts   │  │ 🖥  2 Hosts   │  │ 🖥  1 Host    │            │
│  │ 🔗  5 在线    │  │ 🔗  1 在线    │  │ 🔗  1 在线    │            │
│  │ 📂  3 Stages  │  │ 📂  2 Stages  │  │ 📂  1 Stage   │            │
│  │──────────────│  │──────────────│  │──────────────│            │
│  │ [🚀 进入]   │  │ [🚀 进入]   │  │ [🚀 进入]   │            │
│  └──────────────┘  └──────────────┘  └──────────────┘            │
└─────────────────────────────────────────────────────────────────────┘
```

**操作**（全部在概览页完成，无弹窗）：

| 操作 | 交互 |
|------|------|
| [+ 新建] | 末尾出现空白卡片，名称直接进入编辑状态。输入名称回车即创建。 |
| [✎ 重命名] | 名称变为行内编辑框，回车或失焦保存 |
| [× 删除] | 确认后删除 |
| [🚀 进入] | 进入 Workspace 页 |
| 拖拽排序 | 长按后拖拽调整 Workspace 顺序（可选） |

**Stage/Host 管理**在进入 Workspace 后通过左侧栏操作，概览页不管理 Stage 和 Host。

**背景动效**：概览页和空状态复用现有 `BreatheGrid`（`lib/shared/design_system/components/indicators/breathe_grid.dart`），使用方式同 `session_tree_panel.dart`：

```dart
Stack(
  children: [
    const Positioned.fill(child: BreatheGrid()),
    Container(
      color: AppColors.terminalBackground.withValues(alpha: 0.85),
      child: /* 实际内容 */,
    ),
  ],
)
```

**空状态**：

```
┌──────────────────────────────────────────────────────────────┐
│  [BreatheGrid 动效铺满全屏]                                  │
│   ┌────────────────────────────────────────────────────┐    │
│   │             欢迎使用 Polarmote                     │    │
│   │                                                    │    │
│   │        还没有任何 Workspace                        │    │
│   │                                                    │    │
│   │        [➕ 创建第一个 Workspace]                    │    │
│   └────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

### 4.3 Workspace 页（进入后）

```
┌───────────────┬──────────────────────────────────────────────┐
│ Workspace     │  [Terminal Content]                           │
│ Production    │                                               │
│ [← 概览]      │  user@prod-web-01:~$                         │
│───────────────│                                               │
│ 🌐 Web        │                                               │
│   ├prod-web-01│                                               │
│   └prod-web-02│                                               │
│ 🗄  数据库    │                                               │
│   └prod-db-01 │                                               │
│ 📊 监控      │                                               │
│   └grafana    │                                               │
│               │                                               │
│ [+ Add]      │                                               │
└───────────────┴──────────────────────────────────────────────┘
```

左侧显示 Workspace 内按 Stage 分组的主机树，不显示 Session 信息。

---

## 实现进度

| 模块 | 状态 |
|------|------|
| `Workspace` + `Stage` 数据模型 | ✅ 已完成 |
| `AppPage` 枚举 + 导航状态 | ✅ 已完成 |
| Overview 概览页 UI（含空状态 + BreatheGrid） | ✅ 已完成 |
| 概览页横向 Workspace 列 + 竖向 Stage 卡片 | ✅ 已完成 |
| Stage 卡片复用（StageCard 共享组件） | ✅ 已完成 |
| Workspace 持久化（保存/加载/迁移） | ✅ 已完成 |
| 阻止 startup 自动连接（workspaces 模式） | ✅ 已完成 |
| 新建 Stage 自动加入当前 Workspace | ✅ 已完成 |
| 双模式导航（`terminal_home_page.dart`） | ✅ 已完成 |
| 终端模式侧边栏按 Workspace 过滤 | ✅ 已完成 |
| 设计系统 + i18n 文字归入 | ✅ 已完成 |
| 白色系 UI（暗色背景上白色文字/按钮） | ✅ 已完成 |
| 数据迁移（旧 Stages → Legacy Workspace） | ⬜ |

---

## 五、状态管理变更

| 现有 | 变为 |
|------|------|
| `List<TerminalStage> terminalStages` | `List<Workspace> workspaces` + `Map<String, Stage> stageMap` |
| `String activeTerminalStageId` | 不变 |
| `bool stageManagerEnabled` | 废弃 |
| — | 新增 `AppPage currentPage` |
| — | 新增 `String? activeWorkspaceId` |
| — | 新增 `List<Workspace> recentWorkspaces`（最近访问） |

---

## 六、数据关系

```
Workspace
  └── stageIds: List<String>     ← Workspace 持有

Stage
  ├── workspaceId                 ← 反向引用（以 stageIds 为准）
  └── hostIds: List<String>       ← 不存 Session

Host（已有 HostEntry，不变）
  └── (无 Workspace/Stage 引用)

Session（运行时，不变）
  └── (由 TerminalAppState 管理，Stage 不关心)
```

**操作一致性**：

```
删除 Stage
  → Workspace.stageIds 同步移除
  → stageMap 同步移除
  → 不涉及 Session

移动 Stage 到另一 Workspace
  → 原 Workspace.stageIds 移除
  → 目标 Workspace.stageIds 添加
  → Stage.workspaceId 更新
```

---

## 七、设计差距分析与补充（2026-07 修订）

以下分析基于当前代码库（commit `efb3b30`）的实际结构与本文档之间的差异。当前代码库**不包含**任何 Workspace、AppPage、Overview 页等实现——所有功能需从零构建。

### 7.1 Stage 概念冲突

| 本文档定义 | 当前代码 `TerminalStage` | 冲突 |
|---|---|---|
| `Stage` = 主机逻辑分组（`hostIds`） | 是**会话**分组（`sessionIds` + `connectedHostIds`） | 语义不同 |
| `Stage.workspaceId` 反向引用 | 无 workspace 概念 | 缺失 |

**决议**：保留现有 `TerminalStage` 作为运行时会话分组（负责 session 恢复、`backgroundImageId`），新增 `StageGroup` 作为持久化主机分组模型。两套概念并存：

```
StageGroup（新）── 持久化，hostIds，隶属于 Workspace
TerminalStage  ── 运行时，sessionIds，backgroundImageId，auto-reconnect
```

迁移时，将旧 `TerminalStage.connectedHostIds` 提取到新的 `StageGroup.hostIds`，`TerminalStage` 继续保留。

### 7.2 导航架构需分层

文档 `AppPage` 定义的是顶层页面路由，而当前 `NavSection`（sessions/sftp/transfers/scripts/settings）管理的是终端侧栏面板。两者是上下层关系：

```
AppPage.overview  ── 全屏概览页
     ↓
AppPage.workspace ── 终端页
     ├─ 左侧: Workspace Stage 树
     ├─ 中间: 终端区 + NavSection 侧栏面板
     └─ [← 概览]
```

`terminal_home_page.dart:41` 目前直接渲染 `MainPanel`。需外层增加 `AppPage` 选择器：

```dart
// terminal_home_page.dart 中
appState.currentPage == AppPage.overview
  ? const OverviewPage()
  : MainPanel(appState: appState)
```

### 7.3 StageCard 组件待抽取

文档 ✓ "Stage 卡片复用"，但代码中不存在独立组件。`stage_manager_sidebar.dart:340-464` 包含 inline 的缩略图渲染逻辑（AspectRatio 16:9 + 背景图 + SessionThumbnail + 渐变叠加 + 名称）。

**实现建议**：新建 `lib/features/terminal/presentation/common/stage_card.dart`，参数化：

```dart
class StageCard extends StatelessWidget {
  const StageCard({
    required this.name,
    this.backgroundImagePath,
    this.child,                    // 缩略图内容（SessionThumbnail 或空状态）
    this.isActive = false,
    this.onTap,
    this.onContextMenu,
  });
}
```

一处定义，同时用于：
- 概览页内 Workspace 下方的 stage 列表
- Workspace 页左侧 stage 树节点
- 现有 `StageManagerSidebar`

### 7.4 持久化集成方案

文档有 `toJson()`/`fromJson()` 但未说明如何接入现有系统。当前保存路径：

```
scheduleStateSave()
  → terminal_app_state_ops2.dart _buildStateJson()
  → terminal_app_state_ops2.dart _loadStateFromData()
```

**实现方案**：
1. 在 `_buildStateJson()` 中增加 `workspaces` 与 `stageMap` 序列化
2. 在 `_loadStateFromData()` 中反序列化并重建 `stageMap`
3. 检测旧 `terminalStages` 字段——若存在且有数据，自动创建 `workspaces[0] = "Legacy Workspace"`，每个旧 `TerminalStage` 转为 `StageGroup`
4. 写入迁移标记 `_stateMigratedToWorkspaces` 防重复

### 7.5 阻止 startup 自动连接的精确机制

文档 ✓ "阻止 startup 自动连接（workspaces 模式）"。当前 `terminal_app_state.dart:80-85` 的 `_loadState` 后执行 `restoreStageSessions()`。

**实现方案**：新增 `bool workspaceMode = true` 状态字段。当 `workspaceMode == true` 时 `_loadState` 后跳过 `restoreStageSessions()`，改为仅在用户进入 Workspace 页后恢复该 workspace 下 stage 的 session。用户首次迁移后默认启用。

### 7.6 侧边栏按 Workspace 过滤

文档 ✓ "终端模式侧边栏按 Workspace 过滤"，缺少交互细节。

**实现方案**：
- `AppPage.workspace` 状态下，`session_tree_panel.dart` 自动只显示当前 `activeWorkspaceId` 下 stage 内的 hosts
- 在 `session_tree_panel.dart` 搜索栏下方增加 workspace 下拉筛选器（当处于 overview 模式时可用）
- 不覆盖现有 `TreeView<HostEntry>` + `host.group` 文件夹分组，workspace 模式与 folder 模式可切换

### 7.7 空状态 BreatheGridScrim 公共组件

文档描述了一个通用模式（BreatheGrid 背景 + 半透明叠加层 + 内容），用在概览页和空状态。

**实现建议**：新建 `breathe_grid_scrim.dart`：

```dart
class BreatheGridScrim extends StatelessWidget {
  const BreatheGridScrim({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: BreatheGrid()),
        Container(
          color: AppColors.terminalBackground.withValues(alpha: 0.85),
          child: child,
        ),
      ],
    );
  }
}
```

### 7.8 Stage 排序

文档有 `Workspace.sortOrder`，但 `Stage` 缺少排序字段。

**补充**：为 `StageGroup` 添加 `int sortOrder`。概览页 Workspace 内 Stage 按 `sortOrder` 纵向排列。Workspace 列表和 Stage 列表均应支持拖拽重排（可选，P3）。

### 7.9 最近访问判定

文档 `recentWorkspaces` 未定义判定条件。

**规则**：
- 点击 [🚀 进入] 时记录 `lastAccessedAt`
- 按 `lastAccessedAt` 降序取前 3 个
- 新建的 workspace 不自动加入最近打开
- 初始迁移时已有 workspaces 均设 `lastAccessedAt = createdAt`

### 7.10 实现进度（当前真实状态）

所有 ✅ 标记的项目均未实现。以下为实际起点：

| 模块 | 状态 |
|------|------|
| `Workspace` + `StageGroup` 数据模型 | ⬜ |
| `AppPage` 枚举 + 导航状态 | ⬜ |
| Overview 概览页 UI（含空状态 + BreatheGridScrim） | ⬜ |
| 概览页横向 Workspace 列 + 竖向 Stage 卡片 | ⬜ |
| StageCard 共享组件 | ⬜ |
| Workspace 持久化（保存/加载/迁移） | ⬜ |
| 阻止 startup 自动连接（workspaces 模式） | ⬜ |
| 新建 Stage 自动加入当前 Workspace | ⬜ |
| 双模式导航（`terminal_home_page.dart`） | ⬜ |
| 终端模式侧边栏按 Workspace 过滤 | ⬜ |
| 设计系统 + i18n 文字归入 | ⬜ |
| 白色系 UI（暗色背景上白色文字/按钮） | ⬜ |
| 数据迁移（旧 Stages → Legacy Workspace） | ⬜ |
