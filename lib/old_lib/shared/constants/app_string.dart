import 'package:flutter/widgets.dart';

class AppText {
  const AppText({required this.en, required this.zh});

  final String en;
  final String zh;

  String resolve(String localeCode, {Map<String, String> params = const {}}) {
    var template = localeCode == 'en' ? en : zh;
    params.forEach((key, value) {
      template = template.replaceAll('{$key}', value);
    });
    return template;
  }

  String resolveLocale(Locale locale, {Map<String, String> params = const {}}) {
    return resolve(locale.languageCode, params: params);
  }
}

class _AppStringValues {
  const _AppStringValues();

  final addScript = const AppText(en: 'Add script', zh: '添加脚本');
  final add = const AppText(en: 'Add', zh: '新增');
  final asmoteTerminal = const AppText(en: 'Asmote Terminal', zh: 'Asmote 终端');
  final auth = const AppText(en: 'Auth:', zh: '认证方式：');
  final autoReconnect = const AppText(en: 'Auto reconnect', zh: '自动重连');
  final androidKeepSshAliveInBackground = const AppText(
    en: 'Keep SSH alive in background (Android)',
    zh: '后台保持 SSH 连接（Android）',
  );
  final androidKeepSshAliveInBackgroundHint = const AppText(
    en: 'Uses a foreground service notification to reduce background disconnects.',
    zh: '使用前台服务通知降低后台断连概率。',
  );
  final back = const AppText(en: 'Back', zh: '返回');
  final calculatingTransfers = const AppText(
    en: 'Calculating transfers...',
    zh: '正在计算传输任务...',
  );
  final calculatingUploads = const AppText(
    en: 'Calculating uploads...',
    zh: '正在计算上传任务...',
  );
  final calculatingUploadsScannedVarVar = const AppText(
    en: 'Calculating uploads... scanned {scanned}, files {files}',
    zh: '正在计算上传任务... 已扫描 {scanned}，文件 {files}',
  );
  final calculatingUploadsScannedVarFilesVarRateVarEtaVar = const AppText(
    en: 'Calculating uploads... scanned {scanned}, files {files}, {rate}/s, ETA {eta}',
    zh: '正在计算上传任务... 已扫描 {scanned}，文件 {files}，{rate}/秒，预计 {eta}',
  );
  final calculatingDownloadsScannedVarVar = const AppText(
    en: 'Calculating downloads... scanned {scanned}, files {files}',
    zh: '正在计算下载任务... 已扫描 {scanned}，文件 {files}',
  );
  final calculatingDownloadsScannedVarFilesVarRateVarEtaVar = const AppText(
    en: 'Calculating downloads... scanned {scanned}, files {files}, {rate}/s, ETA {eta}',
    zh: '正在计算下载任务... 已扫描 {scanned}，文件 {files}，{rate}/秒，预计 {eta}',
  );
  final cancel = const AppText(en: 'Cancel', zh: '取消');
  final canceled = const AppText(en: 'Canceled', zh: '已取消');
  final chinese = const AppText(en: 'Chinese', zh: '中文');
  final close = const AppText(en: 'Close', zh: '关闭');
  final retry = const AppText(en: 'Retry', zh: '重试');
  final clear = const AppText(en: 'Clear', zh: '清空');
  final confirm = const AppText(en: 'Confirm', zh: '确认');
  final confirmPaste = const AppText(en: 'Confirm paste', zh: '粘贴确认');
  final connect = const AppText(en: 'Connect', zh: '连接');
  final connectionType = const AppText(en: 'Connection:', zh: '连接类型：');
  final connectionSsh = const AppText(en: 'SSH', zh: 'SSH');
  final connectionLocal = const AppText(en: 'Local Session', zh: '本地会话');
  final connectionSerial = const AppText(en: 'Serial', zh: '串口');
  final connected = const AppText(en: 'Connected', zh: '已连接');
  final connectToUseSftp = const AppText(
    en: 'Connect to use SFTP.',
    zh: '请先连接主机后再使用 SFTP。',
  );
  final connecting = const AppText(en: 'Connecting...', zh: '正在连接...');
  final copy = const AppText(en: 'Copy', zh: '复制');
  final create = const AppText(en: 'Create', zh: '创建');
  final createANewSessionOrQuickConnect = const AppText(
    en: 'Create a new session or quick connect.',
    zh: '创建新会话或快速连接。',
  );
  final defaultValue = const AppText(en: 'Default', zh: '默认');
  final delete = const AppText(en: 'Delete', zh: '删除');
  final disconnected = const AppText(en: 'Disconnected', zh: '已断开');
  final done = const AppText(en: 'Done', zh: '完成');
  final openUrl = const AppText(en: 'Open URL', zh: '打开链接');
  final selectionModeLine = const AppText(en: 'Line selection', zh: '行选择');
  final selectionModeBlock = const AppText(en: 'Block selection', zh: '块选择');
  final discard = const AppText(en: 'Discard', zh: '放弃');
  final upload = const AppText(en: 'Upload', zh: '上传');
  final download = const AppText(en: 'Download', zh: '下载');
  final downloads = const AppText(en: 'Downloads', zh: '下载');
  final english = const AppText(en: 'English', zh: '英文');
  final eGDeploySh = const AppText(en: 'e.g. deploy.sh', zh: '例如：deploy.sh');
  final edit = const AppText(en: 'Edit', zh: '编辑');
  final editSession = const AppText(en: 'Edit Session', zh: '编辑会话');
  final enabled = const AppText(en: 'Enabled', zh: '启用');
  final enterPath = const AppText(en: 'Enter path', zh: '输入路径');
  final failed = const AppText(en: 'Failed', zh: '失败');
  final filePreview = const AppText(en: 'File Preview', zh: '文件预览');
  final loadingFilePreview = const AppText(
    en: 'Loading file preview...',
    zh: '正在加载文件预览...',
  );
  final filePreviewEmpty = const AppText(en: 'File is empty.', zh: '文件为空。');
  final filePreviewTruncated = const AppText(
    en: '[Preview truncated at 512 KB]',
    zh: '[预览已截断（最多显示 512 KB）]',
  );
  final fileTooLarge = const AppText(en: 'Large file', zh: '文件过大');
  final fileTooLargeManualDownloadVarVar = const AppText(
    en: 'File exceeds {limit} (current {actual}). Auto-download is disabled. Download manually, then open with a system app.',
    zh: '文件超过 {limit}（当前 {actual}）。已禁用自动下载，请先手动下载到本地后再用系统应用打开。',
  );
  final fileTree = const AppText(en: 'File Tree', zh: '文件树');
  final folderName = const AppText(en: 'Folder name', zh: '文件夹名称');
  final forward = const AppText(en: 'Forward', zh: '前进');
  final group = const AppText(en: 'Group', zh: '分组');
  final groupAll = const AppText(en: 'All groups', zh: '全部分组');
  final host = const AppText(en: 'Host', zh: '主机');
  final key = const AppText(en: 'Key', zh: '密钥');
  final privateKeyPassphrase = const AppText(en: 'Key Passphrase', zh: '私钥口令');
  final sshAgent = const AppText(
    en: 'Use SSH Agent / default keys',
    zh: '使用 SSH Agent / 默认密钥',
  );
  final sshAdvanced = const AppText(en: 'SSH Advanced', zh: 'SSH 高级');
  final proxyNone = const AppText(en: 'No Proxy', zh: '无代理');
  final proxySocks5 = const AppText(en: 'SOCKS5', zh: 'SOCKS5');
  final proxyJump = const AppText(en: 'ProxyJump', zh: '跳板机');
  final proxyJumpHost = const AppText(en: 'Jump Host', zh: '跳板主机');
  final socksProxyHost = const AppText(en: 'SOCKS Host', zh: 'SOCKS 主机');
  final socksProxyPort = const AppText(en: 'SOCKS Port', zh: 'SOCKS 端口');
  final socksProxyUsername = const AppText(en: 'SOCKS User', zh: 'SOCKS 用户名');
  final socksProxyPassword = const AppText(
    en: 'SOCKS Password',
    zh: 'SOCKS 密码',
  );
  final sshKeepAliveSeconds = const AppText(
    en: 'KeepAlive (s)',
    zh: 'KeepAlive（秒）',
  );
  final sshConnectTimeoutSeconds = const AppText(
    en: 'Connect Timeout (s)',
    zh: '连接超时（秒）',
  );
  final language = const AppText(en: 'Language', zh: '语言');
  final languageZh = const AppText(en: 'Chinese', zh: '中文');
  final languageEn = const AppText(en: 'English', zh: 'English');
  final homeLayout = const AppText(en: 'Interface layout', zh: '界面布局');
  final homeLayoutFollowPlatform = const AppText(
    en: 'Follow device',
    zh: '跟随设备',
  );
  final homeLayoutMobile = const AppText(en: 'Small-screen layout', zh: '小屏布局');
  final homeLayoutDesktop = const AppText(
    en: 'Large-screen layout',
    zh: '大屏布局',
  );
  final localTerminal = const AppText(en: 'Local Session', zh: '本地会话');
  final localTerminalHint = const AppText(
    en: 'Starts a local session on this device without SSH.',
    zh: '在当前设备直接启动本地会话，不经过 SSH。',
  );
  final localSessionName = const AppText(en: 'Session Name', zh: '会话名称');
  final localShellType = const AppText(en: 'Local shell', zh: '本地 Shell');
  final localShellSystemDefault = const AppText(
    en: 'System Default',
    zh: '系统默认',
  );
  final localShellSystemDefaultHint = const AppText(
    en: 'Use the platform default shell with the best compatibility.',
    zh: '使用系统默认 Shell，兼容性最好。',
  );
  final localShellPowerShell = const AppText(
    en: 'PowerShell',
    zh: 'PowerShell',
  );
  final localShellPowerShellHint = const AppText(
    en: 'Modern Windows shell, suitable for scripts and automation.',
    zh: '现代 Windows Shell，适合脚本与自动化。',
  );
  final localShellPowerShellAdmin = const AppText(
    en: 'PowerShell (Admin)',
    zh: 'PowerShell（管理员）',
  );
  final localShellPowerShellAdminHint = const AppText(
    en: 'Runs elevated PowerShell; Asmote must be launched as Administrator.',
    zh: '以管理员权限运行 PowerShell；需要管理员身份启动 Asmote。',
  );
  final localShellCommandPrompt = const AppText(
    en: 'Command Prompt',
    zh: '命令提示符',
  );
  final localShellCommandPromptHint = const AppText(
    en: 'Classic cmd environment for batch scripts and legacy commands.',
    zh: '经典 cmd 环境，适合批处理脚本和旧命令。',
  );
  final localShellWsl = const AppText(en: 'WSL', zh: 'WSL');
  final localShellWslHint = const AppText(
    en: 'Start a Linux shell via WSL.',
    zh: '通过 WSL 启动 Linux Shell。',
  );
  final localShellBash = const AppText(en: 'Bash', zh: 'Bash');
  final localShellBashHint = const AppText(
    en: 'Use Bash shell (for example Git Bash or /bin/bash).',
    zh: '使用 Bash（如 Git Bash 或 /bin/bash）。',
  );
  final localTerminalUnsupportedOnPlatform = const AppText(
    en: 'Local session is not supported on this platform.',
    zh: '当前平台不支持本地会话。',
  );
  final localTerminalAdminRequiresElevation = const AppText(
    en: 'Admin PowerShell requires launching Asmote as Administrator.',
    zh: '管理员 PowerShell 需要以管理员身份启动 Asmote。',
  );
  final localTerminalUseSshOnIos = const AppText(
    en: 'iOS does not support local terminal. Please use SSH session.',
    zh: 'iOS 不支持本地会话，请使用 SSH 会话。',
  );
  final localTerminalStartFailedVar = const AppText(
    en: 'Failed to start local session: {error}',
    zh: '启动本地会话失败: {error}',
  );
  final serialTerminal = const AppText(en: 'Serial Session', zh: '串口会话');
  final serialTerminalHint = const AppText(
    en: 'Connect directly to a local serial device (COM/tty).',
    zh: '直接连接到本机串口设备（COM/tty）。',
  );
  final serialUnsupportedOnPlatform = const AppText(
    en: 'Serial session is not supported on this platform.',
    zh: '当前平台不支持串口会话。',
  );
  final serialPortPath = const AppText(en: 'Serial Port', zh: '串口设备');
  final serialPortPathHint = const AppText(
    en: 'Example: COM3 / /dev/ttyUSB0',
    zh: '示例：COM3 / /dev/ttyUSB0',
  );
  final serialBaudRate = const AppText(en: 'Baud Rate', zh: '波特率');
  final serialDataBits = const AppText(en: 'Data Bits', zh: '数据位');
  final serialStopBits = const AppText(en: 'Stop Bits', zh: '停止位');
  final serialParity = const AppText(en: 'Parity', zh: '校验位');
  final serialParityNone = const AppText(en: 'None', zh: '无');
  final serialParityOdd = const AppText(en: 'Odd', zh: '奇校验');
  final serialParityEven = const AppText(en: 'Even', zh: '偶校验');
  final serialPortRequired = const AppText(
    en: 'Serial port path is required.',
    zh: '串口设备不能为空。',
  );
  final serialConnectFailedVar = const AppText(
    en: 'Failed to open serial session: {error}',
    zh: '打开串口会话失败: {error}',
  );
  final loading = const AppText(en: 'Loading...', zh: '加载中...');
  final logs = const AppText(en: 'Logs', zh: '日志');
  final workflows = const AppText(en: 'Workflows', zh: '工作流');
  final searchWorkflowName = const AppText(
    en: 'Search workflow name',
    zh: '搜索工作流名称',
  );
  final noWorkflows = const AppText(
    en: 'No workflows yet',
    zh: '暂无工作流',
  );
  final workflowName = const AppText(en: 'Workflow name', zh: '工作流名称');
  final workflowConnectHost = const AppText(
    en: 'Connect session',
    zh: '连接会话',
  );
  final workflowDelayMs = const AppText(
    en: 'Delay between steps (ms)',
    zh: '步骤间延迟（毫秒）',
  );
  final workflowSelectScripts = const AppText(
    en: 'Select scripts',
    zh: '选择脚本',
  );
  final workflowNoScripts = const AppText(
    en: 'No scripts available',
    zh: '暂无脚本可选',
  );
  final workflowSummaryVarVarVar = const AppText(
    en: 'Scripts {scripts} · Connect {connect} · Delay {delay}',
    zh: '脚本 {scripts} · 连接 {connect} · 延迟 {delay}',
  );
  final workflowRunSuccess = const AppText(
    en: '{name} succeeded',
    zh: '{name} 成功',
  );
  final workflowRunFailed = const AppText(
    en: '{name} failed',
    zh: '{name} 失败',
  );
  final workflowNotFoundVar = const AppText(
    en: 'Workflow not found: {name}',
    zh: '工作流不存在：{name}',
  );
  final workflowHostNotFoundVar = const AppText(
    en: 'Host not found: {name}',
    zh: '主机不存在：{name}',
  );
  final workflowScriptNotFoundVar = const AppText(
    en: 'Script not found: {name}',
    zh: '脚本不存在：{name}',
  );
  final workflowNoTargetsVar = const AppText(
    en: 'Script has no run targets: {name}',
    zh: '脚本未配置运行目标：{name}',
  );
  final none = const AppText(en: 'None', zh: '无');
  final logSearchHint = const AppText(en: 'Search logs', zh: '搜索日志关键词');
  final hideFilters = const AppText(en: 'Hide Filters', zh: '收起筛选');
  final moreFilters = const AppText(en: 'More Filters', zh: '更多筛选');
  final allLevels = const AppText(en: 'All Levels', zh: '全部级别');
  final allCategories = const AppText(en: 'All Categories', zh: '全部模块');
  final logFilterSummaryVarVar = const AppText(
    en: 'Level: {level} | Category: {category}',
    zh: '级别: {level}  |  模块: {category}',
  );
  final logCategoryStartup = const AppText(en: 'STARTUP', zh: '启动');
  final logCategorySession = const AppText(en: 'SESSION', zh: '会话');
  final logCategoryTransfer = const AppText(en: 'TRANSFER', zh: '传输');
  final logCategoryExternalEdit = const AppText(
    en: 'EXTERNAL_EDIT',
    zh: '外部编辑',
  );
  final logCategorySystem = const AppText(en: 'SYSTEM', zh: '系统');
  final logCategoryUi = const AppText(en: 'UI', zh: '界面');
  final logCategoryScript = const AppText(en: 'SCRIPT', zh: '脚本');
  final logLevelInfo = const AppText(en: 'INFO', zh: '信息');
  final logLevelWarn = const AppText(en: 'WARN', zh: '警告');
  final logLevelError = const AppText(en: 'ERROR', zh: '错误');
  final logLevelBegin = const AppText(en: 'BEGIN', zh: '开始');
  final logLevelEnd = const AppText(en: 'END', zh: '结束');
  final logErrorVar = const AppText(en: 'Error: {message}', zh: '错误：{message}');
  final logVerbosityAll = const AppText(en: 'All logs', zh: '全部');
  final logVerbosityImportant = const AppText(en: 'Important only', zh: '重要');
  final logVerbosityErrorsOnly = const AppText(en: 'Errors only', zh: '仅错误');
  final logKeyboardRecoveryTriggered = const AppText(
    en: 'Keyboard recovery triggered',
    zh: '已触发键盘恢复',
  );
  final logKeyboardRecoveryTriggeredReasonVar = const AppText(
    en: 'Keyboard recovery triggered: {reason}',
    zh: '已触发键盘恢复：{reason}',
  );
  final logBannerVarVar = const AppText(
    en: '{title}: {message}',
    zh: '{title}：{message}',
  );
  final startupSessionStartVar = const AppText(
    en: '-------------------- Startup Session START [{runId}] --------------------',
    zh: '-------------------- 启动会话 START [{runId}] --------------------',
  );
  final startupSessionEndVarVar = const AppText(
    en: '-------------------- Startup Session END [{runId}] total={elapsedMs}ms --------------------',
    zh: '-------------------- 启动会话 END [{runId}] 总耗时={elapsedMs}ms --------------------',
  );
  final startupSectionCacheCleanup = const AppText(
    en: 'Cache Cleanup',
    zh: '缓存清理',
  );
  final startupSectionVersionInfo = const AppText(
    en: 'Version Info',
    zh: '版本信息',
  );
  final startupSectionTransferProbe = const AppText(
    en: 'Transfer Probe',
    zh: '传输引擎探测',
  );
  final startupSectionDurationVar = const AppText(
    en: 'duration={elapsedMs}ms',
    zh: '耗时={elapsedMs}ms',
  );
  final startupSectionErrorDurationVarVar = const AppText(
    en: 'error={error} duration={elapsedMs}ms',
    zh: '错误={error} 耗时={elapsedMs}ms',
  );
  final startupCleanupDirMissingVar = const AppText(
    en: 'Skip missing dir: {path}',
    zh: '目录不存在，跳过 {path}',
  );
  final startupCleanupDirResultVarVarVar = const AppText(
    en: '{path} deleted={deleted} failed={failed}',
    zh: '{path} 删除={deleted} 失败={failed}',
  );
  final startupCleanupSummaryVarVarVar = const AppText(
    en: 'Cleanup summary: dirs={dirs}, deleted={deleted}, failed={failed}',
    zh: '清理汇总：目录={dirs}，删除={deleted}，失败={failed}',
  );
  final startupResultSuccess = const AppText(en: 'success', zh: '成功');
  final startupResultFailed = const AppText(en: 'failed', zh: '失败');
  final startupCleanupResultVarVarVarVar = const AppText(
    en: 'Cleanup: {result}, dirs={dirs}, deleted={deleted}, failed={failed}',
    zh: '缓存清理：{result}，目录={dirs}，删除={deleted}，失败={failed}',
  );
  final startupCleanupDeleteFailedVarVar = const AppText(
    en: 'Delete failed: {path}, error={error}',
    zh: '删除失败 {path}，错误={error}',
  );
  final startupCleanupFailedVar = const AppText(
    en: 'Cleanup failed: {error}',
    zh: '清理失败：{error}',
  );
  final startupVersionReadFailedVar = const AppText(
    en: 'App version read failed: {error}',
    zh: '应用版本读取失败：{error}',
  );
  final startupVersionResolvedVar = const AppText(
    en: 'App version: {version}',
    zh: '应用版本: {version}',
  );
  final startupVersionUnknown = const AppText(
    en: 'App version: <unknown>',
    zh: '应用版本: <未读取到>',
  );
  final startupTransferUnavailable = const AppText(
    en: 'Transfer engine: unavailable',
    zh: '传输引擎: 不可用',
  );
  final startupTransferBuildVar = const AppText(
    en: 'Transfer engine: {build}',
    zh: '传输引擎: {build}',
  );
  final scriptLogEventVarVarVar = const AppText(
    en: 'Script[{runId}][{target}] {event}{detail}',
    zh: '脚本[{runId}][{target}] {event}{detail}',
  );
  final scriptEventRunStarted = const AppText(en: 'run-started', zh: '执行开始');
  final scriptEventTargetStarted = const AppText(
    en: 'target-started',
    zh: '目标开始',
  );
  final scriptEventStepStarted = const AppText(en: 'step-started', zh: '步骤开始');
  final scriptEventStdout = const AppText(en: 'stdout', zh: '标准输出');
  final scriptEventStderr = const AppText(en: 'stderr', zh: '标准错误');
  final scriptEventStepSucceeded = const AppText(
    en: 'step-succeeded',
    zh: '步骤成功',
  );
  final scriptEventStepFailed = const AppText(en: 'step-failed', zh: '步骤失败');
  final scriptEventTargetSucceeded = const AppText(
    en: 'target-succeeded',
    zh: '目标成功',
  );
  final scriptEventTargetFailed = const AppText(
    en: 'target-failed',
    zh: '目标失败',
  );
  final scriptEventRunFinished = const AppText(en: 'run-finished', zh: '执行结束');
  final scriptMonitor = const AppText(en: 'Script Monitor', zh: '脚本监控');
  final modified = const AppText(en: 'Modified', zh: '最近修改');
  final all = const AppText(en: 'All', zh: '全部');
  final uploadOnly = const AppText(en: 'Upload only', zh: '仅上传');
  final downloadOnly = const AppText(en: 'Download only', zh: '仅下载');
  final failedOnly = const AppText(en: 'Failed only', zh: '仅失败');
  final scriptTriggerHitLogs = const AppText(en: 'Trigger hits', zh: '触发命中');
  final more = const AppText(en: 'More', zh: '更多');
  final ellipsis = const AppText(en: '...', zh: '...');
  final name = const AppText(en: 'Name', zh: '名称');
  final navigation = const AppText(en: 'Navigation', zh: '导航');
  final newFile = const AppText(en: 'New File', zh: '新建文件');
  final newFolder = const AppText(en: 'New Folder', zh: '新建文件夹');
  final newSession = const AppText(en: 'New Session', zh: '新建会话');
  final noActiveSession = const AppText(en: 'No active session', zh: '暂无活跃会话');
  final noActiveTransfers = const AppText(
    en: 'No active transfers',
    zh: '暂无传输任务',
  );
  final noData = const AppText(en: 'No data', zh: '暂无数据');
  final unknown = const AppText(en: 'unknown', zh: '未知');
  final noKeySelected = const AppText(en: 'No key selected', zh: '未选择密钥');
  final noLogs = const AppText(en: 'No logs', zh: '暂无日志');
  final recentVisitedFiles = const AppText(
    en: 'Recent Visited Files',
    zh: '历史访问文件',
  );
  final noRecentVisitedFiles = const AppText(
    en: 'No recently visited files',
    zh: '暂无历史访问文件',
  );
  final visitedFileOpenFailedVar = const AppText(
    en: 'Failed to open visited file: {error}',
    zh: '打开历史文件失败：{error}',
  );
  final visitedFileHostNotFound = const AppText(
    en: 'Host for this file is not found',
    zh: '该文件对应主机不存在',
  );
  final visitedFileDownloadOrConnectFailed = const AppText(
    en: 'Failed to connect or download preview file',
    zh: '连接或下载预览文件失败',
  );
  final visitedFileLocalSessionMissing = const AppText(
    en: 'No local session available to open this file',
    zh: '没有可用本地会话，无法打开该文件',
  );
  final noMatchingFiles = const AppText(en: 'No matching files', zh: '没有匹配的文件');
  final noMatchingSessions = const AppText(
    en: 'No matching sessions',
    zh: '没有匹配的会话',
  );
  final noSessions = const AppText(en: 'No sessions', zh: '暂无会话');
  final notStartedAutoConnect = const AppText(
    en: 'Not started (auto connect)',
    zh: '未启动（将自动连接）',
  );
  final ok = const AppText(en: 'OK', zh: '确定');
  final panel = const AppText(en: 'Panel', zh: '面板');
  final password = const AppText(en: 'Password', zh: '密码');
  final paste = const AppText(en: 'Paste', zh: '粘贴');
  final pending = const AppText(en: 'Pending', zh: '待执行');
  final pause = const AppText(en: 'Pause', zh: '暂停');
  final paused = const AppText(en: 'Paused', zh: '已暂停');
  final resume = const AppText(en: 'Resume', zh: '恢复');
  final pin = const AppText(en: 'Favorite', zh: '收藏');
  final pinned = const AppText(en: 'Favorites', zh: '收藏');
  final port = const AppText(en: 'Port', zh: '端口');
  final permissions = const AppText(en: 'Permissions', zh: '权限');
  final fileOwner = const AppText(en: 'Owner', zh: '所有者');
  final fileGroup = const AppText(en: 'Group', zh: '所属组');
  final queued = const AppText(en: 'Queued', zh: '排队中');
  final quickConnect = const AppText(en: 'Quick Connect', zh: '快速连接');
  final quickJump = const AppText(en: 'Quick Jump', zh: '快速跳转');
  final reconnect = const AppText(en: 'Reconnect', zh: '重新连接');
  final reconnecting = const AppText(en: 'Reconnecting...', zh: '正在重连...');
  final refresh = const AppText(en: 'Refresh', zh: '刷新');
  final refuseToDeleteUnsafePath = const AppText(
    en: 'Refuse to delete unsafe path',
    zh: '拒绝删除不安全路径',
  );
  final rename = const AppText(en: 'Rename', zh: '重命名');
  final renameTab = const AppText(en: 'Rename Tab', zh: '重命名标签');
  final save = const AppText(en: 'Save', zh: '保存');
  final send = const AppText(en: 'Send', zh: '发送');
  final saveAndConnect = const AppText(en: 'Save & Connect', zh: '保存并连接');
  final scripts = const AppText(en: 'Scripts', zh: '脚本');
  final search = const AppText(en: 'Search', zh: '搜索');
  final sortBy = const AppText(en: 'Sort by', zh: '排序方式');
  final smart = const AppText(en: 'Smart', zh: '智能');
  final recent = const AppText(en: 'Recent', zh: '最近');
  final selectAll = const AppText(en: 'Select All', zh: '全选');
  final selectMultiple = const AppText(en: 'Multi-select', zh: '多选');
  final selectedCountVar = const AppText(
    en: '{count} selected',
    zh: '已选 {count} 项',
  );
  final selectKey = const AppText(en: 'Select Key', zh: '选择密钥');
  final sessionIsOffline = const AppText(
    en: 'Session is offline.',
    zh: '当前会话离线。',
  );
  final sessionNotConnected = const AppText(
    en: 'Session not connected',
    zh: '会话未连接',
  );
  final sessionOffline = const AppText(en: 'Session offline', zh: '会话离线');
  final recentSessions = const AppText(en: 'Recent Sessions', zh: '最近访问');
  final recentWithin7DaysVar = const AppText(
    en: 'Last 7 days ({count})',
    zh: '近7天（{count}）',
  );
  final olderVar = const AppText(en: 'Older ({count})', zh: '更早（{count}）');
  final sessions = const AppText(en: 'Sessions', zh: '会话');
  final settings = const AppText(en: 'Settings', zh: '设置');
  final settingsGeneral = const AppText(en: 'General', zh: '通用');
  final settingsConfigBackup = const AppText(
    en: 'Config & Backup',
    zh: '配置与备份',
  );
  final settingsPortForwarding = const AppText(
    en: 'Port Forwarding',
    zh: '端口转发',
  );
  final settingsTransfer = const AppText(en: 'Transfer', zh: '传输');
  final settingsSnapshots = const AppText(en: 'Snapshots', zh: '快照');
  final transferRuntimeStatusVarVarVarVarVar = const AppText(
    en: 'Running U{upload} D{download} T{total} · Native {busy}/{sessions}',
    zh: '运行中 上传{upload} 下载{download} 总计{total} · Native {busy}/{sessions}',
  );
  final settingsApplied = const AppText(en: 'Settings Applied', zh: '设置已应用');
  final settingsCache = const AppText(en: 'Cache', zh: '缓存');
  final clearFilePreviewCache = const AppText(
    en: 'Clear File Preview Cache',
    zh: '清除文件预览缓存',
  );
  final filePreviewCacheClearedVarVar = const AppText(
    en: 'Deleted={deleted}, failed={failed}',
    zh: '删除={deleted}，失败={failed}',
  );
  final importConfig = const AppText(en: 'Import Config', zh: '导入配置');
  final exportConfig = const AppText(en: 'Export Config', zh: '导出配置');
  final importSelection = const AppText(en: 'Import Selection', zh: '选择导入内容');
  final exportSelection = const AppText(en: 'Export Selection', zh: '选择导出内容');
  final sectionSettings = const AppText(en: 'Settings', zh: '设置');
  final sectionSessions = const AppText(en: 'Sessions', zh: '会话');
  final sectionScripts = const AppText(en: 'Scripts', zh: '脚本');
  final sectionPortForwards = const AppText(en: 'Port Forwards', zh: '端口转发');
  final sectionHistory = const AppText(en: 'History', zh: '历史');
  final sectionFingerprints = const AppText(
    en: 'Host Fingerprints',
    zh: '主机指纹',
  );
  final restoreDefaultSettings = const AppText(
    en: 'Restore Defaults',
    zh: '恢复默认设置',
  );
  final createSnapshot = const AppText(en: 'Create Snapshot', zh: '创建快照');
  final rollbackSnapshot = const AppText(en: 'Rollback Snapshot', zh: '回滚快照');
  final deleteSnapshot = const AppText(en: 'Delete Snapshot', zh: '删除快照');
  final noSnapshotsYet = const AppText(en: 'No snapshots yet', zh: '暂无快照');
  final restoredDefaults = const AppText(
    en: 'Defaults Restored',
    zh: '默认设置已恢复',
  );
  final snapshotCreated = const AppText(en: 'Snapshot Created', zh: '快照已创建');
  final snapshotRolledBack = const AppText(
    en: 'Snapshot Rolled Back',
    zh: '已回滚到快照',
  );
  final restoreSnapshot = const AppText(en: 'Restore', zh: '恢复');
  final snapshotDeleted = const AppText(en: 'Snapshot Deleted', zh: '快照已删除');
  final editSnapshot = const AppText(en: 'Edit', zh: '编辑');
  final snapshotName = const AppText(en: 'Name', zh: '名称');
  final snapshotDescription = const AppText(en: 'Description', zh: '描述');
  final snapshotSave = const AppText(en: 'Save', zh: '保存');
  final snapshotUpdated = const AppText(en: 'Snapshot Updated', zh: '快照已更新');
  final transferAutoRetry = const AppText(
    en: 'Auto retry transfer',
    zh: '传输失败自动重试',
  );
  final transferResume = const AppText(en: 'Resume transfer', zh: '断点续传');
  final transferRetryMaxAttempts = const AppText(
    en: 'Max retry attempts',
    zh: '最大重试次数',
  );
  final transferRetryBaseDelayMs = const AppText(
    en: 'Base retry delay (ms)',
    zh: '重试基础延迟（毫秒）',
  );
  final transferRetryMaxDelayMs = const AppText(
    en: 'Max retry delay (ms)',
    zh: '重试最大延迟（毫秒）',
  );
  final importConfiguration = const AppText(
    en: 'Import Configuration',
    zh: '导入配置',
  );
  final importReplaceCurrentData = const AppText(
    en: 'Replace current sessions and scripts?',
    zh: '是否覆盖当前会话与脚本配置？',
  );
  final merge = const AppText(en: 'Merge', zh: '合并');
  final replace = const AppText(en: 'Replace', zh: '覆盖');
  final imported = const AppText(en: 'Imported', zh: '导入成功');
  final exported = const AppText(en: 'Exported', zh: '导出成功');
  final importFailedVar = const AppText(
    en: 'Import failed: {error}',
    zh: '导入失败: {error}',
  );
  final exportFailedVar = const AppText(
    en: 'Export failed: {error}',
    zh: '导出失败: {error}',
  );
  final includeEncryptedSecrets = const AppText(
    en: 'Include passwords (encrypted)',
    zh: '包含密码（加密）',
  );
  final masterPassword = const AppText(
    en: 'Master password',
    zh: '主密码',
  );
  final confirmMasterPassword = const AppText(
    en: 'Confirm master password',
    zh: '确认主密码',
  );
  final passwordsDoNotMatch = const AppText(
    en: 'Passwords do not match',
    zh: '两次密码不一致',
  );
  final wrongMasterPassword = const AppText(
    en: 'Wrong master password',
    zh: '主密码错误',
  );
  final enterDecryptionPassword = const AppText(
    en: 'Enter decryption password',
    zh: '输入解密密码',
  );
  final decrypt = const AppText(en: 'Decrypt', zh: '解密');
  final fileContainsEncryptedSecrets = const AppText(
    en: 'This config file contains encrypted passwords. Please enter the master password to decrypt.',
    zh: '此配置文件包含加密密码，请输入主密码解密。',
  );
  final portForwardRule = const AppText(en: 'Port Forward Rule', zh: '端口转发规则');
  final portForwardType = const AppText(en: 'Forward Type', zh: '转发类型');
  final portForwardTypeLocal = const AppText(en: 'Local Forward', zh: '本地转发');
  final portForwardTypeReverse = const AppText(
    en: 'Reverse Forward',
    zh: '反向转发',
  );
  final portForwardTypeSocks = const AppText(
    en: 'Dynamic SOCKS',
    zh: '动态 SOCKS',
  );
  final addPortForwardRule = const AppText(
    en: 'Add Port Forward Rule',
    zh: '新增端口转发规则',
  );
  final editPortForwardRule = const AppText(
    en: 'Edit Port Forward Rule',
    zh: '编辑端口转发规则',
  );
  final noPortForwardRules = const AppText(
    en: 'No port forward rules',
    zh: '暂无端口转发规则',
  );
  final noPortForwardRulesHint = const AppText(
    en: 'Add a rule to expose a remote service locally.',
    zh: '新增规则后可将远端服务映射到本地端口。',
  );
  final sshHost = const AppText(en: 'SSH Host', zh: 'SSH 主机');
  final localHost = const AppText(en: 'Local Host', zh: '本地地址');
  final localPort = const AppText(en: 'Local Port', zh: '本地端口');
  final localTargetHost = const AppText(en: 'Local Target Host', zh: '本地目标地址');
  final localTargetPort = const AppText(en: 'Local Target Port', zh: '本地目标端口');
  final remoteHost = const AppText(en: 'Remote Host', zh: '远端地址');
  final remotePort = const AppText(en: 'Remote Port', zh: '远端端口');
  final remoteBindHost = const AppText(en: 'Remote Bind Host', zh: '远端监听地址');
  final remoteBindPort = const AppText(en: 'Remote Bind Port', zh: '远端监听端口');
  final portForwardReverseHint = const AppText(
    en: 'Reverse mode: remote side listens and forwards traffic back to this local target.',
    zh: '反向模式：由远端监听端口，并把流量回连到本地目标地址。',
  );
  final portForwardSocksHint = const AppText(
    en: 'Dynamic SOCKS mode: local port provides a SOCKS5 proxy tunnel through SSH.',
    zh: '动态 SOCKS 模式：本地端口提供 SOCKS5 代理，经 SSH 隧道转发。',
  );
  final portForwardTemplates = const AppText(en: 'Templates', zh: '模板');
  final noPortForwardTemplates = const AppText(
    en: 'No templates yet. Save an existing rule as template first.',
    zh: '暂无模板，请先把现有规则保存为模板。',
  );
  final saveAsTemplate = const AppText(en: 'Save as Template', zh: '保存为模板');
  final useTemplate = const AppText(en: 'Use Template', zh: '应用模板');
  final autoStart = const AppText(en: 'Auto-start', zh: '自动启动');
  final start = const AppText(en: 'Start', zh: '启动');
  final stop = const AppText(en: 'Stop', zh: '停止');
  final startAll = const AppText(en: 'Start All', zh: '全部启动');
  final stopAll = const AppText(en: 'Stop All', zh: '全部停止');
  final restart = const AppText(en: 'Restart', zh: '重启');
  final running = const AppText(en: 'Running', zh: '运行中');
  final stopped = const AppText(en: 'Stopped', zh: '已停止');
  final starting = const AppText(en: 'Starting', zh: '启动中');
  final error = const AppText(en: 'Error: ', zh: '错误：');
  final noSshHostsAvailable = const AppText(
    en: 'No SSH hosts available.',
    zh: '没有可用的 SSH 主机。',
  );
  final portForwardValidationRequiredFields = const AppText(
    en: 'Name / host / address fields are required.',
    zh: '名称、主机和地址不能为空。',
  );
  final portForwardValidationPortRange = const AppText(
    en: 'Port range is invalid.',
    zh: '端口范围无效。',
  );
  final portForwardValidationConflictVar = const AppText(
    en: 'Local bind {bind} conflicts with rule {name}.',
    zh: '本地监听 {bind} 与规则 {name} 冲突。',
  );
  final portForwardErrorSshClosed = const AppText(
    en: 'SSH connection closed',
    zh: 'SSH 连接已断开',
  );
  final portForwardErrorLocalListenerClosed = const AppText(
    en: 'Local listener closed',
    zh: '本地监听已关闭',
  );
  final portForwardErrorRemoteListenerClosed = const AppText(
    en: 'Remote listener closed',
    zh: '远端监听已关闭',
  );
  final portForwardErrorSocksListenerClosed = const AppText(
    en: 'SOCKS listener closed',
    zh: 'SOCKS 监听已关闭',
  );
  final portForwardErrorStartTimeout = const AppText(
    en: 'Port forward start timeout',
    zh: '端口转发启动超时',
  );
  final portForwardTestConnectivity = const AppText(
    en: 'Test Connection',
    zh: '测试连接',
  );
  final portForwardConnectivityTestSuccess = const AppText(
    en: 'Connection test succeeded. The port is accessible via the SSH server\'s address.',
    zh: '连接测试成功。通过 SSH 服务器地址可以访问该端口。',
  );
  final portForwardConnectivityTestFailed = const AppText(
    en: 'Connection test failed. The port appears to be bound to localhost only. '
        'Enable GatewayPorts on the SSH server '
        '(GatewayPorts clientspecified in sshd_config).',
    zh: '连接测试失败。该端口似乎仅绑定到本地地址。'
        '请在 SSH 服务器上启用 GatewayPorts（在 sshd_config 中设置 '
        'GatewayPorts clientspecified）。',
  );
  final portForwardConnectivityTestSkipped = const AppText(
    en: 'Cannot test: could not determine server address.',
    zh: '无法测试：无法确定服务器地址。',
  );
  final portForwardEnableGatewayPorts = const AppText(
    en: 'Enable GatewayPorts',
    zh: '启用 GatewayPorts',
  );
  final portForwardEnablingGatewayPorts = const AppText(
    en: 'Enabling GatewayPorts on SSH server...',
    zh: '正在 SSH 服务器上启用 GatewayPorts...',
  );
  final portForwardGatewayPortsAlreadyEnabled = const AppText(
    en: 'GatewayPorts clientspecified is already enabled on this server.',
    zh: '服务器上已启用 GatewayPorts clientspecified。',
  );
  final portForwardGatewayPortsSuccess = const AppText(
    en: 'GatewayPorts clientspecified has been enabled. The server will reboot in 2 seconds.',
    zh: '已成功启用 GatewayPorts clientspecified，服务器将在 2 秒后重启。',
  );
  final portForwardGatewayPortsFailedSudo = const AppText(
    en: 'Failed to enable GatewayPorts. Try manually:\n'
        '1. SSH into the server\n'
        '2. Edit /etc/ssh/sshd_config and add:\n'
        '   GatewayPorts clientspecified\n'
        '3. Reboot the server: sudo reboot',
    zh: '启用 GatewayPorts 失败。请手动操作：\n'
        '1. SSH 登录服务器\n'
        '2. 编辑 /etc/ssh/sshd_config，添加：\n'
        '   GatewayPorts clientspecified\n'
        '3. 重启服务器：sudo reboot',
  );
  final portForwardGatewayPortsFailedTimeout = const AppText(
    en: 'Operation timed out. You may need to configure sudo for passwordless execution, or enable GatewayPorts manually.',
    zh: '操作超时。请为当前用户配置免密码 sudo，或手动启用 GatewayPorts。',
  );
  final portForwardGatewayPortsChecking = const AppText(
    en: 'Checking current GatewayPorts setting...',
    zh: '正在检查当前 GatewayPorts 配置...',
  );
  final portForwardRuntimeMetricsVarVarVar = const AppText(
    en: 'Port {port} | Local {local} | Tunnel {channels}',
    zh: '端口 {port} | 本地连接 {local} | 隧道通道 {channels}',
  );
  final portForwardLastActivityVar = const AppText(
    en: 'Last activity {time}',
    zh: '最后活动 {time}',
  );
  final portForwardLastActivityNone = const AppText(
    en: 'No activity yet',
    zh: '暂无活动',
  );
  final sftp = const AppText(en: 'Files', zh: '文件');
  final sftpNotReady = const AppText(en: 'SFTP not ready', zh: 'SFTP 未就绪');
  final sftpNotReadyDownloadFailed = const AppText(
    en: 'SFTP not ready, download failed',
    zh: 'SFTP 未就绪，下载失败',
  );
  final sftpNotReadyForDragDownload = const AppText(
    en: 'SFTP not ready for drag download',
    zh: 'SFTP 未就绪，无法拖拽下载',
  );
  final sftpNotReadyUploadFailed = const AppText(
    en: 'SFTP not ready, upload failed',
    zh: 'SFTP 未就绪，上传失败',
  );
  final showHiddenFiles = const AppText(en: 'Show hidden files', zh: '显示隐藏文件');
  final transferring = const AppText(en: 'Transferring', zh: '传输中');
  final dragStream = const AppText(en: 'Drag stream target', zh: '拖拽流目标');
  final transfers = const AppText(en: 'Transfers', zh: '传输');
  final transfersAreRunningClosingWillStopThemContinue = const AppText(
    en: 'Transfers are running. Closing will stop them. Continue?',
    zh: '当前会话有传输任务，关闭会话将终止传输，是否继续？',
  );
  final uploads = const AppText(en: 'Uploads', zh: '上传');
  final username = const AppText(en: 'Username', zh: '用户名');
  final size = const AppText(en: 'Size', zh: '大小');
  final applyAndClose = const AppText(en: 'Apply & Close', zh: '应用并关闭');
  final splitGrid8 = const AppText(en: 'Eight-grid split', zh: '八方格分屏');
  final splitGrid16 = const AppText(
    en: 'Sixteen-grid split',
    zh: '十六方格分屏',
  );
  final secondPane = const AppText(en: 'Second pane', zh: '第二终端');
  final inputBroadcast = const AppText(en: 'Input broadcast', zh: '输入广播');
  final broadcastInputHint = const AppText(en: 'Type here to broadcast to all terminals...', zh: '输入内容将广播到所有终端，Enter键发送内容到终端，Shift+Enter换行，支持基本快捷键...');
  final terminalHorizontalScroll = const AppText(
    en: 'Terminal horizontal scroll',
    zh: '终端横向滚动',
  );
  final mobileSidebarWidth = const AppText(
    en: 'Small-screen sidebar width',
    zh: '小屏侧边栏宽度',
  );
  final widthPxVar = const AppText(en: '{value}px', zh: '{value}px');
  final mobileSidebarWidthRangeVarVar = const AppText(
    en: 'Enter a width between {min} and {max}.',
    zh: '请输入 {min} 到 {max} 之间的宽度。',
  );
  final mobileSidebarWidthInvalidVarVar = const AppText(
    en: 'Invalid width, expected {min}-{max}.',
    zh: '宽度无效，应为 {min}-{max}。',
  );
  final mobileTerminalColumns = const AppText(
    en: 'Mobile terminal columns',
    zh: '移动端终端列数',
  );
  final columnsCountVar = const AppText(en: '{count} columns', zh: '{count} 列');
  final customValue = const AppText(en: 'Custom...', zh: '自定义...');
  final mobileTerminalColumnsRangeVarVar = const AppText(
    en: 'Enter an integer between {min} and {max}.',
    zh: '请输入 {min} 到 {max} 之间的整数。',
  );
  final mobileTerminalColumnsInvalidVarVar = const AppText(
    en: 'Invalid columns value, expected {min}-{max}.',
    zh: '列数无效，应为 {min}-{max}。',
  );
  final terminalAccessibilitySemantics = const AppText(
    en: 'Terminal screen reader semantics',
    zh: '终端屏幕阅读器语义',
  );
  final stopBroadcast = const AppText(en: 'Stop broadcast', zh: '停止广播');
  final commandHistory = const AppText(en: 'Command history', zh: '命令历史');
  final noHistory = const AppText(en: 'No history', zh: '暂无历史');
  final previous = const AppText(en: 'Previous', zh: '上一个');
  final next = const AppText(en: 'Next', zh: '下一个');

  final cpuVarMemVarDiskVarLoadVarNetDVarUVarIoRVarWVar = const AppText(
    en: 'CPU {cpu}  MEM {mem}  DISK {disk}  LOAD {load}  NET D{netDown} U{netUp}  IO R{ioRead} W{ioWrite}',
    zh: 'CPU {cpu}  内存 {mem}  磁盘 {disk}  负载 {load}  网络 D{netDown} U{netUp}  IO R{ioRead} W{ioWrite}',
  );
  final connectedVar = const AppText(en: 'Connected: {host}', zh: '已连接：{host}');
  final connectingToVarVar = const AppText(
    en: 'Connecting to {host}:{port}',
    zh: '正在连接到 {host}:{port}',
  );
  final connectionFailedVar = const AppText(
    en: 'Connection failed: {error}',
    zh: '连接失败: {error}',
  );
  final downloadedVarVar = const AppText(
    en: 'Downloaded {done}/{total}',
    zh: '已下载 {done}/{total}',
  );
  final lessThanOneSecond = const AppText(en: '<1s', zh: '小于1秒');
  final secondsShortVar = const AppText(en: '{seconds}s', zh: '{seconds}秒');
  final minutesSecondsVarVar = const AppText(
    en: '{minutes}m {seconds}s',
    zh: '{minutes}分{seconds}秒',
  );
  final cpuUsageTooltipVarVar = const AppText(
    en: 'CPU usage: {cpu}\nUpdated: {updated}',
    zh: 'CPU 占用: {cpu}\n更新时间: {updated}',
  );
  final memoryUsageTooltipVarVarVar = const AppText(
    en: 'Memory used/total: {memory}\nUsage: {usage}\nUpdated: {updated}',
    zh: '内存 已用/总量: {memory}\n占用: {usage}\n更新时间: {updated}',
  );
  final uploadSpeedTooltipVarVar = const AppText(
    en: 'Upload speed (network TX): {rate}\nUpdated: {updated}',
    zh: '上传速度（网络上行）: {rate}\n更新时间: {updated}',
  );
  final downloadSpeedTooltipVarVar = const AppText(
    en: 'Download speed (network RX): {rate}\nUpdated: {updated}',
    zh: '下载速度（网络下行）: {rate}\n更新时间: {updated}',
  );
  final systemMetricsTooltipVarVarVarVarVar = const AppText(
    en: 'Load average: {load}\nDisk usage: {disk}\nDisk IO: read {read} / write {write}\nUpdated: {updated}',
    zh: '系统负载: {load}\n磁盘占用: {disk}\n磁盘 IO: 读 {read} / 写 {write}\n更新时间: {updated}',
  );
  final deleteVar = const AppText(en: 'Delete {name}?', zh: '删除 {name}？');
  final deleteFailedVar = const AppText(
    en: 'Delete failed: {error}',
    zh: '删除失败: {error}',
  );
  final disconnectedVar = const AppText(
    en: 'Disconnected: {host}',
    zh: '已断开: {host}',
  );
  final externalEditSyncFailedVar = const AppText(
    en: 'External edit sync failed: {error}',
    zh: '外部编辑同步失败: {error}',
  );
  final externalEditSyncingVar = const AppText(
    en: 'Syncing external edit: {path}',
    zh: '同步外部编辑: {path}',
  );
  final failedToCreateFolderVar = const AppText(
    en: 'Failed to create folder: {error}',
    zh: '创建文件夹失败: {error}',
  );
  final failedToInitSftpVar = const AppText(
    en: 'Failed to init SFTP: {error}',
    zh: '初始化 SFTP 失败: {error}',
  );
  final failedToOpenLocalFileVar = const AppText(
    en: 'Failed to open local file: {error}',
    zh: '打开本地文件失败: {error}',
  );
  final failedToReadFileVar = const AppText(
    en: 'Failed to read file: {error}',
    zh: '读取文件失败: {error}',
  );
  final failedToSaveFileVar = const AppText(
    en: 'Failed to save file: {error}',
    zh: '保存文件失败: {error}',
  );
  final failedToReadDirectoryVar = const AppText(
    en: 'Failed to read directory: {error}',
    zh: '读取目录失败: {error}',
  );
  final androidDirectoryRestrictedNoRoot = const AppText(
    en: 'This directory is restricted by Android system (non-root).',
    zh: '该目录受系统限制（非 root）',
  );
  final quickConnectingToVarVar = const AppText(
    en: 'Quick connecting to {host}:{port}',
    zh: '正在快速连接到 {host}:{port}',
  );
  final reconnectingVar = const AppText(
    en: 'Reconnecting {host}',
    zh: '正在重连 {host}',
  );
  final renameFailedVar = const AppText(
    en: 'Rename failed: {error}',
    zh: '重命名失败: {error}',
  );
  final syncedExternalEditVar = const AppText(
    en: 'External edit synced: {path}',
    zh: '外部编辑已同步: {path}',
  );
  final transferFailedVar = const AppText(
    en: 'Transfer failed: {error}',
    zh: '传输失败: {error}',
  );
  final transferCancelled = const AppText(
    en: 'Transfer cancelled',
    zh: '传输已取消',
  );
  final transferCancelReasonUser = const AppText(
    en: 'Cancelled by user',
    zh: '用户取消',
  );
  final transferCancelReasonQueue = const AppText(
    en: 'Queue cancelled',
    zh: '队列取消',
  );
  final transferCancelReasonSessionClosed = const AppText(
    en: 'Session closed',
    zh: '会话关闭',
  );
  final percentVar = const AppText(en: '{value}%', zh: '{value}%');
  final transferQueueStatusVarVar = const AppText(
    en: '{done}/{total} · {status}',
    zh: '{done}/{total} · {status}',
  );
  final transferQueueStatusWithPercentVarVarVarVar = const AppText(
    en: '{done}/{total} · {status} · {percent}',
    zh: '{done}/{total} · {status} · {percent}',
  );
  final transferQueueStatusWithPercentEtaVarVarVarVarVar = const AppText(
    en: '{done}/{total} · {status} · {percent} · {eta}',
    zh: '{done}/{total} · {status} · {percent} · {eta}',
  );
  final transferEtaVar = const AppText(en: 'ETA {eta}', zh: '预计 {eta}');
  final transferStartedVarVarVarVarVar = const AppText(
    en: 'Start [{direction}] {name} @ {host}',
    zh: '开始 [{direction}] {name} @ {host}',
  );
  final transferCompletedVarVarVarVarVar = const AppText(
    en: 'Done [{direction}] {name} @ {host}',
    zh: '完成 [{direction}] {name} @ {host}',
  );
  final transferCancelledVarVarVarVarVarVar = const AppText(
    en: 'Canceled [{direction}] {name} @ {host} | {reason}',
    zh: '已取消 [{direction}] {name} @ {host} | {reason}',
  );
  final transferFailedDetailVarVarVarVarVarVar = const AppText(
    en: 'Failed [{direction}] {name} @ {host} | {reason}',
    zh: '失败 [{direction}] {name} @ {host} | {reason}',
  );
  final transferAdaptiveFallbackAppliedVarVarVarVarVar = const AppText(
    en: 'Adaptive fallback: {profile}, cooldown={cooldownSec}s',
    zh: '自适应降级：{profile}，冷却={cooldownSec}秒',
  );
  final transferAdaptiveProfileChangedVarVarVarVar = const AppText(
    en: 'Adaptive profile: {profile} (Q{queue}/N{native}/C{chunkKb}KB)',
    zh: '自适应档位：{profile}（Q{queue}/N{native}/C{chunkKb}KB）',
  );
  final transferAdaptiveProfileSwitchedVarVarVarVarVar = const AppText(
    en: 'Adaptive switch: {from} -> {to} ({reason})',
    zh: '自适应切换：{from} -> {to}（{reason}）',
  );
  final transferAdaptiveReasonSafetyFallback = const AppText(
    en: 'safety fallback',
    zh: '安全降级',
  );
  final transferAdaptiveReasonFallbackCooldown = const AppText(
    en: 'fallback cooldown',
    zh: '降级冷却',
  );
  final transferAdaptiveReasonProfileHold = const AppText(
    en: 'profile hold',
    zh: '档位保持',
  );
  final transferAdaptiveReasonPressure = const AppText(
    en: 'pressure',
    zh: '负载压力',
  );
  final transferForegroundGuardEnabled = const AppText(
    en: 'Android transfer foreground guard enabled',
    zh: 'Android 传输前台保活已启用',
  );
  final transferForegroundGuardDisabled = const AppText(
    en: 'Android transfer foreground guard disabled',
    zh: 'Android 传输前台保活已关闭',
  );
  final transferForegroundTitle = const AppText(
    en: 'File transfer in progress',
    zh: '文件传输进行中',
  );
  final transferForegroundTitleWithPercentVar = const AppText(
    en: 'Transfers in progress ({percent}%)',
    zh: '文件传输进行中（{percent}%）',
  );
  final transferForegroundGuardFailedVar = const AppText(
    en: 'Android transfer foreground guard failed: {error}',
    zh: 'Android 传输前台保活失败: {error}',
  );
  final sshForegroundGuardEnabled = const AppText(
    en: 'Android SSH foreground guard enabled',
    zh: 'Android SSH 前台保活已启用',
  );
  final sshForegroundGuardDisabled = const AppText(
    en: 'Android SSH foreground guard disabled',
    zh: 'Android SSH 前台保活已关闭',
  );
  final sshForegroundTitle = const AppText(
    en: 'SSH sessions running in background',
    zh: 'SSH 会话在后台运行中',
  );
  final sshForegroundTitleWithCountVar = const AppText(
    en: 'SSH sessions in background ({count})',
    zh: 'SSH 会话后台运行中（{count}）',
  );
  final sshForegroundGuardFailedVar = const AppText(
    en: 'Android SSH foreground guard failed: {error}',
    zh: 'Android SSH 前台保活失败: {error}',
  );
  final sshResumeReconnectCountVar = const AppText(
    en: 'Foreground resume: retry reconnect for {count} SSH session(s)',
    zh: '回到前台：尝试重连 {count} 个 SSH 会话',
  );
  final unsavedChangesPrompt = const AppText(
    en: 'You have unsaved changes. Save before closing?',
    zh: '你有未保存的修改，关闭前是否保存？',
  );
  final unpin = const AppText(en: 'Unfavorite', zh: '取消收藏');
  final uploadedVarVar = const AppText(
    en: 'Uploaded {done}/{total}',
    zh: '已上传 {done}/{total}',
  );
  final rmRfFailed = const AppText(en: 'rm -rf failed', zh: 'rm -rf 执行失败');

  final run = const AppText(en: 'Run', zh: '运行');
  final reset = const AppText(en: 'Reset', zh: '重置');
  final clearAll = const AppText(en: 'Clear All', zh: '取消全选');
  final openInSystem = const AppText(en: 'Open In System', zh: '系统打开');
  final openFolder = const AppText(en: 'Open Folder', zh: '打开文件夹');
  final todayVar = const AppText(en: 'Today ({count})', zh: '今天（{count}）');
  final searchScriptName = const AppText(en: 'Search script name', zh: '搜索脚本名');
  final batchRunScripts = const AppText(en: 'Batch Run Scripts', zh: '批量执行脚本');
  final bindShortcut = const AppText(en: 'Bind Shortcut', zh: '绑定快捷键');
  final removeShortcut = const AppText(en: 'Remove Shortcut', zh: '移除快捷键');
  final shortcut = const AppText(en: 'Shortcut', zh: '快捷键');
  final pressShortcut = const AppText(
    en: 'Press a shortcut (with Ctrl/Alt/Shift/Meta)',
    zh: '按下快捷键（需要 Ctrl/Alt/Shift/Meta）',
  );
  final shortcutAlreadyBoundVar = const AppText(
    en: 'Already bound to: {name}',
    zh: '已绑定到：{name}',
  );
  final probeReachable = const AppText(en: 'Probe: reachable', zh: '探测：可连接');
  final probeUnreachable = const AppText(
    en: 'Probe: unreachable',
    zh: '探测：不可连接',
  );
  final probeProbing = const AppText(en: 'Probe: probing', zh: '探测：进行中');
  final probeUnknown = const AppText(en: 'Probe: unknown', zh: '探测：未知');
  final scriptShortcuts = const AppText(
    en: 'Script Shortcuts',
    zh: '脚本快捷键',
  );
  final noScriptShortcuts = const AppText(
    en: 'No shortcut bindings',
    zh: '暂无快捷键绑定',
  );
  final shortcutsTab = const AppText(en: 'Shortcuts', zh: '快捷键');
  final keyboardShortcuts = const AppText(en: 'Keyboard shortcuts', zh: '键盘快捷键');
  final renameFolder = const AppText(en: 'Rename Folder', zh: '重命名目录');
  final deleteScriptFolderConfirmVar = const AppText(
    en: 'Delete folder "{name}" and subfolders? Scripts move to root.',
    zh: '删除目录“{name}”及其子目录？目录内脚本将移动到根目录。',
  );
  final noMatchingScripts = const AppText(
    en: 'No matching scripts',
    zh: '没有匹配的条目',
  );
  final scriptName = const AppText(en: 'Script Name', zh: '脚本名称');
  final scriptFolderInputLabel = const AppText(
    en: 'Folder (input)',
    zh: '目录（可输入）',
  );
  final scriptFolderInputHint = const AppText(
    en: 'e.g. deploy/prod',
    zh: '例如: deploy/prod',
  );
  final scriptBulkAppendDialogTitle = const AppText(
    en: 'Append from Multi-line',
    zh: '多行命令追加',
  );
  final scriptBulkReplaceDialogTitle = const AppText(
    en: 'Replace from Multi-line',
    zh: '多行命令替换',
  );
  final scriptBulkInputHint = const AppText(
    en: 'One command per line; empty lines are ignored',
    zh: '每行一条命令，空行自动忽略',
  );
  final append = const AppText(en: 'Append', zh: '追加');
  final replaceAction = const AppText(en: 'Replace', zh: '替换');
  final scriptBulkReplace = const AppText(en: 'Bulk Replace', zh: '多行替换');
  final scriptBulkAppend = const AppText(en: 'Bulk Append', zh: '多行追加');
  final scriptCollaborationHint = const AppText(
    en: 'Script collaboration: use @script:script-name (or script-id) on a single line',
    zh: '脚本协作：命令独占一行写 @script:脚本名（或脚本ID）',
  );
  final saveAsNewScript = const AppText(en: 'Save As New', zh: '另存为新脚本');
  final scriptTemplateArgs = const AppText(en: 'Template Args', zh: '模板参数');
  final runSilentExecutionHint = const AppText(
    en: 'Run in background without opening sessions',
    zh: '后台执行，不打开会话',
  );
  final runInteractiveExecutionHint = const AppText(
    en: 'Open sessions and type commands automatically',
    zh: '打开会话并自动输入命令执行',
  );
  final runSilent = const AppText(en: 'Silent', zh: '静默');
  final runVisible = const AppText(en: 'Visible', zh: '可见');
  final cancelExecution = const AppText(en: 'Cancel Execution', zh: '取消执行');
  final cancelExecutionConfirmVar = const AppText(
    en: 'Cancel "{name}"?',
    zh: '确定要取消 "{name}" 吗？',
  );
  final searchScripts = const AppText(en: 'Search scripts', zh: '搜索脚本');
  final scriptCommandsCountVar = const AppText(
    en: '{count} commands',
    zh: '{count} 条命令',
  );
  final selectAtLeastOneScript = const AppText(
    en: 'Select at least one script',
    zh: '请至少选择一个脚本',
  );
  final runBatchSummaryVarVarVar = const AppText(
    en: '{summary}, scripts {scripts}, targets {targets}',
    zh: '{summary}，脚本 {scripts} 个，目标 {targets}',
  );
  final command = const AppText(en: 'Command', zh: '命令');
  final commandsOnePerLine = const AppText(
    en: 'Commands (one command per item)',
    zh: '命令（每个输入项一条）',
  );
  final runScriptVar = const AppText(
    en: 'Run Script: {name}',
    zh: '运行脚本：{name}',
  );
  final runTargetsSavedSessions = const AppText(
    en: 'Saved sessions',
    zh: '保存的会话',
  );
  final runTargetsLocalSessions = const AppText(
    en: 'Local sessions',
    zh: '本地会话',
  );
  final scriptSchedule = const AppText(en: 'Schedule', zh: '计划');
  final scriptScheduleVar = const AppText(
    en: 'Script Schedule: {name}',
    zh: '脚本计划：{name}',
  );
  final scriptScheduleRequiresLastRun = const AppText(
    en: 'Run once and save target options before creating schedule.',
    zh: '请先运行一次脚本并保存目标配置，再创建计划任务。',
  );
  final macroRun = const AppText(en: 'Run as Macro', zh: '作为宏执行');
  final scriptTrigger = const AppText(en: 'Trigger', zh: '触发器');
  final scriptTriggerVar = const AppText(
    en: 'Trigger: {name}',
    zh: '触发器：{name}',
  );
  final scriptTriggerEvent = const AppText(en: 'Trigger Event', zh: '触发事件');
  final scriptTriggerOnConnect = const AppText(
    en: 'On Session Connected',
    zh: '会话连接后',
  );
  final scriptTriggerOnCommand = const AppText(
    en: 'On Command Submitted',
    zh: '命令提交后',
  );
  final scriptTriggerMatchType = const AppText(en: 'Match Rule', zh: '匹配规则');
  final scriptTriggerMatchContains = const AppText(en: 'Contains', zh: '包含');
  final scriptTriggerMatchRegex = const AppText(en: 'Regex', zh: '正则');
  final scriptTriggerPattern = const AppText(
    en: 'Command Pattern',
    zh: '命令匹配表达式',
  );
  final scriptTriggerPatternRequired = const AppText(
    en: 'Pattern is required for command trigger.',
    zh: '命令触发器必须填写匹配表达式。',
  );
  final scriptTriggerCooldownSeconds = const AppText(
    en: 'Cooldown (s)',
    zh: '冷却时间（秒）',
  );
  final scriptMaxConcurrency = const AppText(en: 'Max Concurrency', zh: '最大并发');
  final scriptTriggerOnlyActiveHostVar = const AppText(
    en: 'Only active host ({name})',
    zh: '仅当前活跃主机（{name}）',
  );
  final scriptTriggerExecuteAsMacro = const AppText(
    en: 'Execute as Macro (current session)',
    zh: '以宏方式执行（当前会话）',
  );
  final scriptTriggerSilentExecution = const AppText(
    en: 'Silent execution',
    zh: '静默执行',
  );
  final scriptTriggerHostScope = const AppText(en: 'Host Scope', zh: '主机范围');
  final scriptTriggerHostScopeAll = const AppText(en: 'All hosts', zh: '全部主机');
  final scriptTriggerHostScopeSpecific = const AppText(
    en: 'Specific host',
    zh: '指定主机',
  );
  final scriptTriggerHostSearchHint = const AppText(
    en: 'Type host name / id to filter',
    zh: '输入主机名或ID进行筛选',
  );
  final scriptTriggerHostNoMatch = const AppText(
    en: 'No matching hosts',
    zh: '没有匹配的主机',
  );
  final scriptTriggerHostRequired = const AppText(
    en: 'Please select an existing host',
    zh: '请选择一个已存在的主机',
  );
  final scriptBatchTemplates = const AppText(
    en: 'Batch Templates',
    zh: '批处理模板',
  );
  final noScriptBatchTemplates = const AppText(
    en: 'No batch templates',
    zh: '暂无批处理模板',
  );
  final scriptBatchTemplateSavedVar = const AppText(
    en: 'Batch template saved: {name}',
    zh: '批处理模板已保存：{name}',
  );
  final scriptBatchTemplateAppliedVar = const AppText(
    en: 'Batch template applied: {name}',
    zh: '已套用批处理模板：{name}',
  );
  final scriptScheduleHint = const AppText(
    en: 'Use cron expression: minute hour day month weekday. Example: */5 * * * *',
    zh: '使用 cron 表达式：分 时 日 月 周。示例：*/5 * * * *',
  );
  final scriptScheduleTimezone = const AppText(
    en: 'Schedule Timezone',
    zh: '调度时区',
  );
  final scriptScheduleMissedRunPolicy = const AppText(
    en: 'Missed-run policy',
    zh: '错过任务策略',
  );
  final scriptScheduleMissedRunSkip = const AppText(
    en: 'Skip missed runs',
    zh: '跳过错过任务',
  );
  final scriptScheduleMissedRunCatchUpOnce = const AppText(
    en: 'Catch up once',
    zh: '补跑一次',
  );
  final scriptScheduleMissedRunCatchUpAll = const AppText(
    en: 'Catch up all (bounded)',
    zh: '补跑全部（有上限）',
  );
  final scriptScheduleNextTriggerVar = const AppText(
    en: 'Next trigger: {time}',
    zh: '下一次触发：{time}',
  );
  final cronExpression = const AppText(en: 'Cron Expression', zh: 'Cron 表达式');
  final invalidCronExpression = const AppText(
    en: 'Invalid cron expression',
    zh: 'Cron 表达式不合法',
  );
  final scriptHistory = const AppText(en: 'Run History', zh: '运行历史');
  final scriptHistoryVar = const AppText(
    en: 'Run History: {name}',
    zh: '运行历史：{name}',
  );
  final selectScriptToViewHistory = const AppText(
    en: 'Select a script to view history',
    zh: '请选择脚本以查看历史',
  );
  final scriptMonitorRunningCountVar = const AppText(
    en: '{count} running',
    zh: '{count} 个运行中',
  );
  final scriptMonitorDismissFinished = const AppText(
    en: 'Dismiss finished',
    zh: '清除已完成',
  );
  final scriptMonitorNoRunning = const AppText(
    en: 'No running scripts',
    zh: '暂无运行中的脚本',
  );
  final scriptMonitorBatchHintVar = const AppText(
    en: 'Batch execution: max {max} concurrent scripts',
    zh: '批量执行：每次最多 {max} 个脚本同时运行',
  );
  final runOptionNotify = const AppText(en: 'Show notification', zh: '显示通知');
  final runOptionSilent = const AppText(en: 'Silent execution', zh: '静默执行');
  final runOptionStopOnFailure = const AppText(
    en: 'Stop on first failure',
    zh: '失败后停止',
  );
  final scriptFailurePolicy = const AppText(en: 'Failure policy', zh: '失败策略');
  final scriptFailurePolicyContinue = const AppText(
    en: 'Continue on failure',
    zh: '失败继续',
  );
  final scriptFailurePolicyStop = const AppText(
    en: 'Stop on first failure',
    zh: '首次失败停止',
  );
  final scriptFailurePolicyRetryHost = const AppText(
    en: 'Retry failed host',
    zh: '失败主机重试',
  );
  final scriptRetryPerHost = const AppText(
    en: 'Retry attempts / host',
    zh: '每主机重试次数',
  );
  final runNoTargetSelected = const AppText(
    en: 'Select at least one target',
    zh: '请至少选择一个执行目标',
  );
  final runSummaryVarVar = const AppText(
    en: 'Executed {success}, failed {failed}',
    zh: '执行成功 {success}，失败 {failed}',
  );
  final scriptSystemNotificationCompletedTitleVar = const AppText(
    en: 'Script done: {name}',
    zh: '脚本执行完成：{name}',
  );
  final scriptSystemNotificationFailedTitleVar = const AppText(
    en: 'Script failed: {name}',
    zh: '脚本执行失败：{name}',
  );
  final scriptExecutionFailedVarVar = const AppText(
    en: 'Script "{name}" failed: {detail}',
    zh: '脚本“{name}”执行失败：{detail}',
  );
  final runResetDefaults = const AppText(en: 'Restore defaults', zh: '恢复默认配置');
  final saveRunConfig = const AppText(en: 'Save config', zh: '保存配置');
  final scriptNotFoundVar = const AppText(
    en: 'Script not found: {id}',
    zh: '未找到脚本：{id}',
  );
  final noAvailableSessionSelectedForScriptVar = const AppText(
    en: 'No available session selected for script: {name}',
    zh: '脚本未选择可用会话：{name}',
  );
  final scriptExecutedOnVarSessionCount = const AppText(
    en: 'Script "{name}" executed on {count} session(s)',
    zh: '脚本“{name}”已在 {count} 个会话执行',
  );
  final noConnectedSessionAvailableForScriptRun = const AppText(
    en: 'No connected session available for script run',
    zh: '没有可用于脚本执行的已连接会话',
  );
  final executedOnVarSessions = const AppText(
    en: 'Executed on {count} session(s).',
    zh: '已在 {count} 个会话执行。',
  );
  final deleteVarItems = const AppText(
    en: 'Delete {count} items?',
    zh: '删除 {count} 项？',
  );
  final sessionFolderDeleteDangerVar = const AppText(
    en: 'This deletes all sessions under this folder and subfolders ({count} total). This action cannot be undone.',
    zh: '将删除该分组及子分组下全部会话（共 {count} 个），此操作不可恢复。',
  );
  final bundleUploadVar = const AppText(
    en: 'Bundle Upload ({count})',
    zh: '打包上传（{count}）',
  );
  final bundleDownloadVar = const AppText(
    en: 'Bundle Download ({count})',
    zh: '打包下载（{count}）',
  );
  final urlCopiedVar = const AppText(
    en: 'URL copied: {url}',
    zh: 'URL 已复制：{url}',
  );
  final terminalFontFamily = const AppText(en: 'Font family', zh: '字体');
  final terminalFontSize = const AppText(en: 'Font size', zh: '字号');
  final terminalLineHeight = const AppText(en: 'Line height', zh: '行高');
  final terminalTheme = const AppText(en: 'Terminal theme', zh: '终端主题');
  final terminalThemeDefault = const AppText(en: 'Default (Dark)', zh: '默认（暗色）');
  final terminalThemeLight = const AppText(en: 'Light (White on Black)', zh: '亮色（白底黑字）');
  final terminalThemeCustom = const AppText(en: 'Custom theme', zh: '自定义主题');
  final terminalAppearance = const AppText(en: 'Terminal appearance', zh: '终端外观');
  final maxScrollbackLines = const AppText(en: 'Scrollback lines', zh: '滚动行数');
  final terminalBlockSelect = const AppText(en: 'Block selection (Alt+drag)', zh: '块选择（Alt+拖拽）');
  final commandPalette = const AppText(en: 'Command palette', zh: '命令面板');
  final commandPaletteHint = const AppText(en: 'Type a command...', zh: '输入命令...');
  final searchRegex = const AppText(en: 'Regex', zh: '正则');
  final searchCaseSensitive = const AppText(en: 'Case sensitive', zh: '大小写');
  final keybinding = const AppText(en: 'Keybinding', zh: '快捷键');
  final keybindings = const AppText(en: 'Keybindings', zh: '快捷键设置');
  final addKeybinding = const AppText(en: 'Add keybinding', zh: '添加快捷键');
  final keybindingAction = const AppText(en: 'Action', zh: '操作');
  final keybindingKeys = const AppText(en: 'Keys', zh: '按键');
  final noCustomKeybindings = const AppText(en: 'No custom keybindings', zh: '无自定义快捷键');
  final connectionTelnet = const AppText(en: 'Telnet', zh: 'Telnet');
  final telnetPort = const AppText(en: 'Telnet port', zh: 'Telnet 端口');
  final urlOpenConfirm = const AppText(en: 'Open URL?', zh: '打开链接？');
  final urlOpenMessage = const AppText(en: 'Open {url} in browser?', zh: '是否在浏览器中打开 {url}？');
  final settingsTerminal = const AppText(en: 'Terminal', zh: '终端');
  final terminalBackgroundOpacity = const AppText(en: 'Background opacity', zh: '背景不透明度');
  final terminalBackgroundImage = const AppText(en: 'Background images', zh: '背景图片');
  final addImage = const AppText(en: 'Add image', zh: '添加图片');
  final selectBackground = const AppText(en: 'Select background', zh: '选择背景');
  final reuseSessionForNewPane = const AppText(en: 'Reuse existing session for same host', zh: '重复主机复用已有会话');
  final noBackground = const AppText(en: 'No background', zh: '无背景');
  final noneSelected = const AppText(en: 'None', zh: '无');
  final appearanceProfile = const AppText(en: 'Appearance profile', zh: '外观配置');
  final useGlobalAppearance = const AppText(en: 'Use global appearance', zh: '使用全局外观');
  final searchPrevious = const AppText(en: 'Previous', zh: '上一个');
  final searchNext = const AppText(en: 'Next', zh: '下一个');
  final noMatches = const AppText(en: 'No matches', zh: '无匹配');
  final warning = const AppText(en: 'Warning: ', zh: '警告：');
  final startupBegan = const AppText(en: 'Startup started', zh: '启动开始');
  final startupFinishedVarMs = const AppText(en: 'Startup finished ({ms}ms)', zh: '启动完成（{ms}ms）');
  final versionReadFailedVar = const AppText(en: 'Version info read failed: {error}', zh: '版本信息读取失败：{error}');
  final transferEngineUnavailable = const AppText(en: 'Transfer engine unavailable', zh: '传输引擎不可用');
  final transferEngineReady = const AppText(en: 'Transfer engine ready', zh: '传输引擎就绪');
  final asmoteTerminalReady = const AppText(en: 'Asmote Terminal Ready', zh: 'Asmote 终端就绪');
  final sessionLabel = const AppText(en: 'Session:', zh: '会话：');
  final modeLabel = const AppText(en: 'Mode:', zh: '模式：');
  final timeLabel = const AppText(en: 'Time:', zh: '时间：');
  final contactLabel = const AppText(en: 'Contact:', zh: '联系：');
  final contactEmail = const AppText(en: '2116520372@qq.com', zh: '2116520372@qq.com');
  final thanksForUsing = const AppText(en: 'Thank you for using Asmote.', zh: '感谢使用 Asmote。');
  final contactQuestion = const AppText(
    en: 'If you have any questions, please contact this email.',
    zh: '如有任何问题，请通过此邮箱联系我们。',
  );
  final session = const AppText(en: 'Session', zh: '会话');
  final connectionFailed = const AppText(en: 'Connection failed', zh: '连接失败');
  final connectionTimedOutDesc = const AppText(en: 'Connection timed out. Check network, host address or port.', zh: '连接超时，请检查网络、主机地址或端口');
  final hostLookupFailedDesc = const AppText(en: 'Host name resolution failed. Check the address.', zh: '主机名解析失败，请检查地址是否正确');
  final connectionRefusedDesc = const AppText(en: 'Connection refused by host. Check SSH service and port.', zh: '目标主机拒绝连接，请检查 SSH 服务和端口');
  final networkUnreachableDesc = const AppText(en: 'Network unreachable. Check network connection.', zh: '网络不可达，请检查网络连接');
  final authFailedDesc = const AppText(en: 'Authentication failed. Check username, password or private key.', zh: '认证失败，请检查用户名、密码或私钥');
  final hostKeyFailedDesc = const AppText(en: 'Host key verification failed. Confirm host identity.', zh: '主机指纹校验失败，请确认主机身份');
  final privateKeyInvalidDesc = const AppText(en: 'Private key configuration is invalid. Check key file and passphrase.', zh: '私钥配置无效，请检查密钥文件和口令');
  final proxyInvalidDesc = const AppText(en: 'Proxy or jump-host configuration is invalid.', zh: '代理或跳板机配置无效');
  final unknownErrorSeeLogs = const AppText(en: 'Unknown error, see logs for raw details.', zh: '未知错误，请查看日志中的原始异常');
  final confirmPasteContent = const AppText(en: 'Confirm pasting the content below to terminal?', zh: '确认将以下内容粘贴到终端？');
  final selectSession = const AppText(en: 'Select session', zh: '选择终端');
  final restorePane = const AppText(en: 'Restore pane', zh: '还原窗格');
  final maximizePane = const AppText(en: 'Maximize pane', zh: '最大化窗格');
  final splitRight = const AppText(en: 'Split right', zh: '向右拆分');
  final splitDown = const AppText(en: 'Split down', zh: '向下拆分');
  final removePane = const AppText(en: 'Remove this pane', zh: '移除此窗格');
  final searchOutput = const AppText(en: 'Search output', zh: '查找内容');
  final disconnectPaneTerminal = const AppText(en: 'Disconnect pane terminal', zh: '断开窗格终端');
  final disconnectPaneConfirmTitle = const AppText(en: 'Disconnect terminal in this pane?', zh: '断开此窗格中的终端？');
  final disconnectPaneConfirmBodyVar = const AppText(en: 'Will disconnect "{title}" and clear only this pane. Other panes connected to the same session are unaffected.', zh: '将断开 "{title}" 的连接，并只清空当前窗格。同一会话的其他窗格不受影响。');
  final searchThisPane = const AppText(en: 'Search this pane', zh: '查找此窗格内容');
  final searchHint = const AppText(en: 'Text to find', zh: '输入要查找的文本');
  final emptyPane = const AppText(en: 'Empty pane', zh: '空窗格');
  final broadcast = const AppText(en: 'Broadcast', zh: '广播');
  final showFileTree = const AppText(en: 'Show file tree for this terminal', zh: '显示此终端的文件树');
  final noSessionsAvailableConnect = const AppText(en: 'No sessions available', zh: '暂无可连接会话');
  final connectSessionToPane = const AppText(en: 'Connect a session to this pane', zh: '选择要连接到此窗格的会话');
  final commandPaletteNewSession = const AppText(en: 'New session', zh: '新建会话');
  final commandPaletteSettings = const AppText(en: 'Settings', zh: '设置');
  final commandPaletteSftp = const AppText(en: 'SFTP', zh: '文件传输 (SFTP)');
  final commandPaletteScripts = const AppText(en: 'Scripts', zh: '脚本');
  final commandPaletteSplitRight = const AppText(en: 'Split right', zh: '向右拆分');
  final commandPaletteSplitDown = const AppText(en: 'Split down', zh: '向下拆分');
  final commandPaletteSearch = const AppText(en: 'Search output', zh: '查找输出');
  final activeStatus = const AppText(en: 'Active', zh: '活跃');
  final setActive = const AppText(en: 'Set Active', zh: '设为活跃');
  final newCustomTheme = const AppText(en: '+ New custom theme', zh: '+ 新建自定义主题');
  final newThemeTitle = const AppText(en: 'New Theme', zh: '新建主题');
  final editThemeTitle = const AppText(en: 'Edit Theme', zh: '编辑主题');
  final editKeybinding = const AppText(en: 'Edit Keybinding', zh: '编辑快捷键');
  final addKeybindingTitle = const AppText(en: 'Add Keybinding', zh: '添加快捷键');
  final keybindingKeysHint = const AppText(en: 'Keys (e.g. Ctrl+Shift+F)', zh: '按键（如 Ctrl+Shift+F）');
  final hostKeyChanged = const AppText(en: 'Host Key Changed', zh: '主机指纹变更');
  final firstHostConnection = const AppText(en: 'First Host Connection', zh: '首次连接主机');
  final hostKeyChangedDesc = const AppText(en: 'The host key fingerprint differs from the recorded value. Please confirm whether to continue.', zh: '检测到主机指纹与已记录值不一致，请确认是否继续连接。');
  final hostKeyNewDesc = const AppText(en: 'A new host key fingerprint was detected. Please confirm whether to trust this host.', zh: '检测到新的主机指纹，请确认是否信任此主机。');
  final keyType = const AppText(en: 'Key Type', zh: '密钥类型');
  final currentFingerprint = const AppText(en: 'Fingerprint', zh: '当前指纹');
  final recordedFingerprint = const AppText(en: 'Recorded', zh: '已记录指纹');
  final rememberFingerprint = const AppText(en: 'Remember this fingerprint (recommended)', zh: '记住该指纹（推荐）');
  final reject = const AppText(en: 'Reject', zh: '拒绝');
  final trustAndConnect = const AppText(en: 'Trust and Connect', zh: '信任并连接');
  final colorCursor = const AppText(en: 'cursor', zh: '光标');
  final colorForeground = const AppText(en: 'foreground', zh: '前景');
  final colorBackground = const AppText(en: 'background', zh: '背景');
  final colorBlack = const AppText(en: 'black', zh: '黑');
  final colorRed = const AppText(en: 'red', zh: '红');
  final colorGreen = const AppText(en: 'green', zh: '绿');
  final colorYellow = const AppText(en: 'yellow', zh: '黄');
  final colorBlue = const AppText(en: 'blue', zh: '蓝');
  final colorMagenta = const AppText(en: 'magenta', zh: '品红');
  final colorCyan = const AppText(en: 'cyan', zh: '青');
  final colorWhite = const AppText(en: 'white', zh: '白');
  final colorBrightBlack = const AppText(en: 'bright black', zh: '亮黑');
  final colorBrightRed = const AppText(en: 'bright red', zh: '亮红');
  final colorBrightGreen = const AppText(en: 'bright green', zh: '亮绿');
  final colorBrightYellow = const AppText(en: 'bright yellow', zh: '亮黄');
  final colorBrightBlue = const AppText(en: 'bright blue', zh: '亮蓝');
  final colorBrightMagenta = const AppText(en: 'bright magenta', zh: '亮品红');
  final colorBrightCyan = const AppText(en: 'bright cyan', zh: '亮青');
  final colorBrightWhite = const AppText(en: 'bright white', zh: '亮白');
  final scriptLabel = const AppText(en: 'Script', zh: '脚本');
  final transferLabel = const AppText(en: 'Transfer', zh: '文件传输');
  final completedLabel = const AppText(en: 'completed', zh: '完成');
  final canceledLabel = const AppText(en: 'canceled', zh: '取消');
  final failedLabel = const AppText(en: 'failed', zh: '失败');
  final readDirectory = const AppText(en: 'Read directory', zh: '读取目录');
  final createFolder = const AppText(en: 'Create folder', zh: '创建文件夹');
  final createFile = const AppText(en: 'Create file', zh: '创建文件');
  final renameFile = const AppText(en: 'Rename', zh: '重命名');
  final deleteFile = const AppText(en: 'Delete', zh: '删除');
  final readFile = const AppText(en: 'Read file', zh: '读取文件');
  final saveFile = const AppText(en: 'Save file', zh: '保存文件');
  final confirmPasteDialogTitle = const AppText(en: 'Confirm paste', zh: '确认粘贴');
  final confirmPasteButton = const AppText(en: 'Paste anyway', zh: '仍然粘贴');
  final hostLabel = const AppText(en: 'Host', zh: '主机');
  final nameLabel = const AppText(en: 'Name', zh: '名称');
  final editLabel = const AppText(en: 'Edit', zh: '编辑');
  final badgeConnectionTypeSerial = const AppText(en: 'Serial', zh: '串口');
  final badgeLocalShellCmd = const AppText(en: 'CMD', zh: 'CMD');
  final badgeLocalShellLocal = const AppText(en: 'Local', zh: '本地');
  final editShortcutHint = const AppText(en: 'Click a shortcut to edit, press Esc to cancel', zh: '点击快捷键可修改，按 Esc 取消修改');
  final pressNewShortcut = const AppText(en: 'Press new shortcut... (Enter to confirm, Esc to cancel, Backspace to clear)', zh: '按下新快捷键...（按 Enter 确认，Esc 取消，Backspace 清除）');
  final currentLabel = const AppText(en: 'Current', zh: '当前');
  final editShortcut = const AppText(en: 'Edit shortcut', zh: '修改快捷键');
  final resetToDefault = const AppText(en: 'Reset to default', zh: '重置为默认');
  final shortcutCopy = const AppText(en: 'Copy', zh: '复制');
  final shortcutPaste = const AppText(en: 'Paste', zh: '粘贴');
  final shortcutSelectAll = const AppText(en: 'Select All', zh: '全选');
  final shortcutFind = const AppText(en: 'Find in terminal', zh: '终端内查找');
  final shortcutBlockSelect = const AppText(en: 'Toggle block selection', zh: '切换块选择');
  final shortcutPreset = const AppText(en: 'Shortcut preset', zh: '快捷键预设');
  final shortcutSplitMaximize = const AppText(en: 'Maximize / Restore pane', zh: '最大化 / 还原窗格');
  final shortcutSplitBroadcast = const AppText(en: 'Toggle input broadcast', zh: '切换输入广播');
  final shortcutSplitPrev = const AppText(en: 'Switch to previous pane', zh: '切换到上一个窗格');
  final shortcutSplitNext = const AppText(en: 'Switch to next pane', zh: '切换到下一个窗格');
  final shortcutConflictTitle = const AppText(en: 'Shortcut conflict', zh: '快捷键冲突');
  final shortcutConflictMessage = const AppText(
    en: 'The following shortcuts are in conflict:',
    zh: '以下快捷键存在冲突：',
  );
  final pressAgainToExit = const AppText(
    en: 'Press again to exit',
    zh: '再按一次退出',
  );
  final trayShow = const AppText(en: 'Show', zh: '显示');
  final trayHide = const AppText(en: 'Hide', zh: '隐藏');
  final trayQuit = const AppText(en: 'Quit', zh: '退出');
  final trayMinimizeToTray = const AppText(
    en: 'Minimized to tray',
    zh: '已最小化到系统托盘',
  );
  final trayActiveConnections = const AppText(
    en: 'Active connections',
    zh: '活跃连接',
  );
  final dashboard = const AppText(en: 'Dashboard', zh: '仪表盘');
  final cpuUsage = const AppText(en: 'CPU Usage', zh: 'CPU 使用率');
  final memoryUsage = const AppText(en: 'Memory Usage', zh: '内存使用率');
  final diskUsage = const AppText(en: 'Disk Usage', zh: '磁盘使用率');
  final cpuLoadDistribution = const AppText(en: 'CPU Load Distribution', zh: 'CPU 负载分布');
  final cpuUser = const AppText(en: 'User', zh: '用户');
  final cpuSystem = const AppText(en: 'System', zh: '系统');
  final cpuIdle = const AppText(en: 'Idle', zh: '空闲');
  final offline = const AppText(en: 'Offline', zh: '离线');
  final lastSeen = const AppText(en: 'Last seen', zh: '上次连接');
  final never = const AppText(en: 'Never', zh: '从未');
  final totalServers = const AppText(en: 'Total Servers', zh: '服务器总数');
  final online = const AppText(en: 'Online', zh: '在线');
  final searchServers = const AppText(en: 'Search servers...', zh: '搜索服务器...');
  final shortcutGroupClipboard = const AppText(en: 'Clipboard', zh: '剪贴板');
  final shortcutGroupSearch = const AppText(en: 'Search', zh: '搜索');
  final shortcutGroupPanes = const AppText(en: 'Panes', zh: '窗格');
  final shortcutGroupSelection = const AppText(en: 'Selection', zh: '选择');
  final tunnelConnections = const AppText(en: 'Conn {connections}', zh: '连接 {connections}');
  final tunnelChannels = const AppText(en: 'Tunnel {channels}', zh: '隧道 {channels}');
  final timeAgoSeconds = const AppText(en: '{count}s ago', zh: '{count}秒前');
  final timeAgoMinutes = const AppText(en: '{count}m ago', zh: '{count}分钟前');
  final timeAgoHours = const AppText(en: '{count}h ago', zh: '{count}小时前');
  final timeAgoDays = const AppText(en: '{count}d ago', zh: '{count}天前');
  final fontFamilyHint = const AppText(en: 'monospace', zh: '等宽字体');
  final imageFiles = const AppText(en: 'Images', zh: '图片');

  // Step config
  final stepConfig = const AppText(en: 'Step config', zh: '步骤配置');
  final stepCondition = const AppText(en: 'Condition', zh: '执行条件');
  final stepConditionAlways = const AppText(en: 'Always', zh: '总是执行');
  final stepConditionOnSuccess = const AppText(en: 'On success', zh: '上一步成功时');
  final stepConditionOnFailure = const AppText(en: 'On failure', zh: '上一步失败时');
  final stepFailurePolicy = const AppText(en: 'On failure', zh: '失败处理');
  final stepFailureContinue = const AppText(en: 'Continue', zh: '继续');
  final stepFailureStop = const AppText(en: 'Stop', zh: '停止');
  final stepCaptureOutput = const AppText(en: 'Capture output', zh: '捕获输出');
  final stepCaptureOutputHint = const AppText(en: 'Make step output available as variable', zh: '该步输出可作为变量使用');

  final stepInsertAbove = const AppText(en: 'Insert above', zh: '在上方插入');
  final stepInsertBelow = const AppText(en: 'Insert below', zh: '在下方插入');
  final stepRemove = const AppText(en: 'Remove step', zh: '删除步骤');

  // Workflow
  final workflowTitle = const AppText(en: 'Workflows', zh: '工作流');
  final workflowNew = const AppText(en: 'New workflow', zh: '新建工作流');
  final workflowEdit = const AppText(en: 'Edit workflow', zh: '编辑工作流');
  final workflowDelete = const AppText(en: 'Delete workflow', zh: '删除工作流');
  final workflowDeleteConfirm = const AppText(en: 'Delete workflow "{name}"?', zh: '是否删除工作流 "{name}"？');
  final workflowNameField = const AppText(en: 'Workflow name', zh: '工作流名称');
  final workflowNameHint = const AppText(en: 'Enter workflow name...', zh: '输入工作流名称...');

  final workflowNodeLabel = const AppText(en: 'Node label', zh: '节点名称');
  final workflowNodeLabelHint = const AppText(en: 'Enter node label...', zh: '输入节点名称...');
  final workflowNodeSelectScript = const AppText(en: 'Select script', zh: '选择脚本');
  final workflowNodeAdd = const AppText(en: 'Add node', zh: '添加节点');
  final workflowNodeDelete = const AppText(en: 'Remove node', zh: '移除节点');

  final workflowValidationLabel = const AppText(en: 'Validation', zh: '验证规则');
  final workflowValidationType = const AppText(en: 'Validation type', zh: '验证方式');
  final validationExitCode = const AppText(en: 'Exit code = 0', zh: '退出码为 0');
  final validationOutputContains = const AppText(en: 'Output contains', zh: '输出包含');
  final validationOutputRegex = const AppText(en: 'Output matches regex', zh: '输出匹配正则');
  final validationAlways = const AppText(en: 'Always pass', zh: '始终通过');
  final workflowValidationPattern = const AppText(en: 'Match pattern', zh: '匹配模式');
  final workflowValidationPatternHint = const AppText(en: 'Enter pattern or regex...', zh: '输入模式或正则...');
  final workflowStopOnFailure = const AppText(en: 'Stop on failure', zh: '失败时停止');

  final workflowRun = const AppText(en: 'Run workflow', zh: '运行工作流');
  final workflowCancel = const AppText(en: 'Cancel workflow', zh: '取消工作流');

  final workflowNodeStatusPending = const AppText(en: 'Pending', zh: '等待中');
  final workflowNodeStatusRunning = const AppText(en: 'Running', zh: '运行中');
  final workflowNodeStatusPassed = const AppText(en: 'Passed', zh: '通过');
  final workflowNodeStatusFailed = const AppText(en: 'Failed', zh: '失败');
  final workflowNodeStatusCancelled = const AppText(en: 'Cancelled', zh: '已取消');

  final workflowResultSummary = const AppText(
    en: '{attempted} steps, {succeeded} succeeded, {failed} failed',
    zh: '{attempted} 步，{succeeded} 成功，{failed} 失败',
  );

  // ── Proxy chain ──
  final proxyJumpChain = const AppText(en: 'Jump hosts', zh: '跳板机链');
  final proxyJumpAdd = const AppText(en: 'Add jump host', zh: '添加跳板机');
  final proxyJumpHostLabel = const AppText(en: 'Jump host', zh: '跳板机');
  final proxyJumpRemove = const AppText(en: 'Remove', zh: '移除');
  final proxyJumpPlaceholder = const AppText(en: 'user@host:port', zh: 'user@host:port');

  // ── Command palette actions ──
  final cmdPaletteNewSession = const AppText(en: 'New session...', zh: '新建会话...');
  final cmdPaletteSettings = const AppText(en: 'Settings', zh: '设置');
  final cmdPaletteSftp = const AppText(en: 'SFTP browser', zh: 'SFTP 浏览');
  final cmdPaletteScripts = const AppText(en: 'Scripts', zh: '脚本');
  final cmdPaletteQuickConnect = const AppText(en: 'Quick connect...', zh: '快速连接...');
  final cmdPaletteSessions = const AppText(en: 'Switch session', zh: '切换会话');
  final cmdPaletteToggleMonitor = const AppText(en: 'Toggle monitor', zh: '切换监控');
  final cmdPaletteSelectAll = const AppText(en: 'Select all', zh: '全选');

  // ── Script variables ──
  final scriptVariableTitle = const AppText(en: 'Template variables', zh: '模板变量');
  final scriptVariableAdd = const AppText(en: 'Add variable', zh: '添加变量');
  final scriptVariableName = const AppText(en: 'Name', zh: '变量名');
  final scriptVariableValue = const AppText(en: 'Default value', zh: '默认值');
  final scriptFindReplace = const AppText(en: 'Find && replace', zh: '查找替换');
  final scriptFindText = const AppText(en: 'Find', zh: '查找');
  final scriptReplaceText = const AppText(en: 'Replace with', zh: '替换为');
  final scriptBulkDelimiter = const AppText(en: 'Line delimiter', zh: '行分隔符');
  final scriptBulkDelimiterHint = const AppText(en: 'Leave empty for separate steps', zh: '留空则每行作为独立步骤');

  // ── Script editor hints ──
  final scriptReferenceHint = const AppText(
    en: '@script:name  references another script  |  \${VAR}  template variable',
    zh: '@script:name 引用脚本  |  \${VAR} 模板变量',
  );

  // ── Script panel run status ──
  final scriptNotFoundOnHost = const AppText(
    en: 'Script not found: {id}',
    zh: '脚本不存在：{id}',
  );
  final scriptNoSavedConfigVar = const AppText(
    en: '{name} has no saved run config',
    zh: '{name} 无保存的执行配置',
  );
  final scriptFailureCountVar = const AppText(
    en: '{count} failed',
    zh: '{count} 个失败',
  );
  final scriptCancelledCountVar = const AppText(
    en: '{count} cancelled',
    zh: '{count} 个已取消',
  );
  final scriptExitCodeVar = const AppText(
    en: 'exit {code}',
    zh: '退出码 {code}',
  );
  final scriptCopyOutput = const AppText(
    en: 'Copy output',
    zh: '复制输出',
  );
  final scriptCopied = const AppText(
    en: 'Copied',
    zh: '已复制',
  );

  // ── Script monitor ──
  final scriptModifierCtrl = const AppText(en: 'Ctrl', zh: 'Ctrl');
  final scriptModifierMeta = const AppText(en: 'Meta', zh: 'Meta');
  final scriptModifierAlt = const AppText(en: 'Alt', zh: 'Alt');
  final scriptModifierShift = const AppText(en: 'Shift', zh: 'Shift');

  // ── Command queue ──
  final commandRunningLong = const AppText(
    en: 'This command has been running for a long time',
    zh: '此命令已运行较长时间',
  );
  final commandQueue = const AppText(en: 'Command Queue', zh: '命令队列');
}

class AppStrings {
  static const values = _AppStringValues();
}
