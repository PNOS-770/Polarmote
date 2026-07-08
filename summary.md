# 背景图 Bug 分析 — 根因

## 问题
终端背景图片选择后不显示，切换背景不会立即变化。

## 日志发现（已修复）
- `backgroundImagePathForActiveStage()` 成功返回路径（`C:\Users\UserX\...\bg-1.png`）
- `_onAppStateChanged` 正确触发并调用 `setState`
- 但图片未渲染

## 根因
`Image.file` 的 `errorBuilder` 使用 `debugPrint` 记录错误。在 **release 模式** 下 `debugPrint` 被抑制，错误静默丢失，`errorBuilder` 返回 `SizedBox.shrink()` 导致图片不显示。

## 已修复
1. `_logBackgroundError` → `addStructuredLog`（release 模式也可见）
2. `$e.path` → `${e.path}`（String interpolation bug）

## 下一步
重启应用 → 选背景图 → Settings → Logs 找 `Background image load error:` 错误信息
