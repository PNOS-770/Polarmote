# Polarmote

跨平台终端模拟器与远程管理工具，目前仅支持Android和Windows。

![Platform](https://img.shields.io/badge/platform-Windows%20|%20Android%20|%20)
[![Release](https://img.shields.io/github/v/release/PNOS-770/Polarmote)](https://github.com/PNOS-770/Polarmote/releases)

## 截图

![主界面](screenshots/main.png)

## 功能

**连接管理**
- SSH（密码/密钥/Agent 认证）、本地终端、串口、Telnet
- SSH ProxyJump 跳板、SOCKS5 代理
- 会话树分组管理，支持搜索、筛选、排序、常用主机固定

**终端**
- 多标签页（Stage）管理，网格概览
- 分屏终端，支持最大化/还原、广播输入
- 终端搜索（正则）、块选择模式
- 字体/字号/行高/光标样式可配置

**文件传输与浏览**
- SFTP 文件传输（Rust 原生加速引擎），支持队列、断点续传、自动重试
- 远程文件树浏览，在线预览和编辑

**脚本自动化**
- 脚本管理，支持文件夹分组和参数变量
- 工作流编排、批量模板
- Cron 定时调度、连接/命令事件触发

**端口转发**
- 本地转发、远程转发、SOCKS5 动态代理
- 模板保存，连接时自动启动

**服务器监控**
- 实时 CPU、内存指标，仪表盘展示

**快捷键**
- 所有快捷键可自由重绑定，内置多套预设

**界面**
- 中文 / English 多语言
- 终端背景图片、透明度设置

## 下载

[Releases](https://github.com/PNOS-770/Polarmote/releases)

## 构建

```bash
flutter build apk --release    # Android
flutter build windows --release  # Windows
flutter build linux --release    # Linux
flutter build macos --release    # macOS
flutter build ios --release      # iOS
```

## License

GNU General Public License v3.0
