# SarvTerminal 优化建议清单

> 整理时间：2026-07-27。基于近几轮改动（hover tooltip 重构、上传覆盖确认、Tab 关闭快捷键、标签栏滚动按钮）及代码走查，按优先级排列。
>
> 实施状态（2026-07-27）：1-8、11 已完成；9 经核实无需实施（见下）；10 swiftlint 按用户要求跳过。

## 一、高优先级（直接影响体验/正确性）

### 1. ✅ 上传冲突逐文件弹窗，批量场景体验差
- **位置**：`SftpSidePanelView.resolveUploadConflict` / `FilePaneView.ConflictDialog`
- **问题**：拖入 20 个同名文件会连续弹 20 次对话框，每次只能处理一个文件
- **建议**：`ConflictDialog` 增加"应用到全部"选项（Replace All / Skip All / Duplicate All），选中后剩余队列一次性按该 resolution 处理。已有 `uploadConflictQueue` 队列结构，改动量小
- **实施**：`ConflictDialog` 增加 `showApplyToAll` checkbox + `onResolve(_, applyToAll)`；`resolveUploadConflict` 增加 applyToAll 分支一次处理整个队列；SFTPView/SFTPWindowView 同步新签名

### 2. ✅ 上传完成后的重复目录刷新
- **位置**：`SftpSidePanelView.performUpload` 第 514 行（每个文件完成后 `remote.reload()`）
- **问题**：批量上传 N 个文件 → N 次全量目录刷新，慢速网络下每刷新一次都是完整 LIST
- **建议**：批量上传时用一个合并刷新（如：每个文件完成时标记 dirty，最后一个完成后 reload 一次，或 debounce 500ms 合并）
- **实施**：`scheduleReload()` 600ms debounce，onDisappear 取消 pending task

### 3. ✅ 标签栏箭头按钮的显示条件不准确
- **位置**：`VaultsTabStrip.swift` 第 78 行（`tabs.terminals.count > 3`）
- **问题**：是否溢出取决于窗口宽度而非标签数量。窗口宽时 5 个标签也不溢出却显示按钮；窗口窄时 2 个标签就可能溢出却不显示
- **建议**：用 `onGeometryChange`/`PreferenceKey` 对比内容宽度与可视宽度，真实溢出才显示按钮
- **实施**：两个 GeometryReader 分别测量 chip 行宽度与 ScrollView 视口宽度，`tabContentWidth > tabViewportWidth + 1` 才显示箭头

### 4. ✅ Debug 构建卡顿风险（防止回归）
- **位置**：构建流程（`zig build` 默认 Debug）
- **问题**：Debug 无编译器优化，cat 大文件明显卡顿（此前已定位并解决）；新代码合入后若用 Debug 验证性能会误判
- **建议**：提供便捷脚本（如 `scripts/build-release.sh` 封装 `zig build -Doptimize=ReleaseFast`），日常使用 ReleaseFast，仅调试时用 Debug
- **实施**：新增 `scripts/build-release.sh`（ReleaseFast + 显式版本号，不签名/不 notarize/不打包 DMG）

## 二、中优先级（代码质量/架构）

### 5. ✅ 上传进度轮询重复实现三份
- **位置**：`SftpSidePanelView.startPoller`（526 行）、`SFTPTransferManager.withProgress`（203 行）、`SFTPView.swift`（314 行附近）
- **问题**：三处都是"800ms 轮询远程 stat 文件大小更新进度"的同一模式，逻辑重复，后续调参（频率/平滑算法）要改三处
- **建议**：提取统一的进度轮询工具（如 `TransferProgressPoller`，接收 backend/path/id/更新闭包），三处复用；同时可把轮询间隔改为按文件大小自适应（大文件 500ms、小文件 1s）
- **实施**：新建 `TransferProgressPoller.swift`（`start(destBackend:destPath:start:interval:onUpdate:)`，闭包返回 false 停止），三处全部改调它

### 6. ✅ hoverTip 全局扩展的命名歧义
- **位置**：`HoverTooltip.swift`（`hoverTip(() -> String)`）与 `VaultsFocusModeView.swift` 182 行（`hoverTip(String)`）
- **问题**：同名全局扩展重载，参数不同；后续开发者容易误用，且浮窗版与旧版行为完全不同（浮窗即时、String 版是 overlay）
- **建议**：String 版改名为 `hoverTipText`（或浮窗版改名 `floatingTip`），消除歧义
- **实施**：String 版改名 `hoverTipText`，13 个文件 47 处调用点全部更新；闭包版 `hoverTip { }` 保留

### 7. ✅ UploadConflictQueue 的 Stop 语义无反馈
- **位置**：`SftpSidePanelView.resolveUploadConflict`（`.stop` 分支）
- **问题**：选择 Stop 后静默清空队列，用户不知道有多少文件被取消、无任何提示
- **建议**：Stop 后显示一条状态（如短时 toast 或把剩余项标记为 cancelled 状态展示在传输列表）
- **实施**：`UploadProgress.Status` 增加 `.cancelled`，Stop 时 `markCancelled` 把队列与安全文件全部记为 cancelled 显示在传输列表

## 三、低优先级（安全/环境/清理）

### 8. ✅ Release 数据目录残留明文密钥文件
- **位置**：`~/.config/sarvterminal/keystore/data-key-raw`
- **问题**：Dev→Release 迁移时复制过去的密钥文件残留在磁盘（沙箱删除失败）；Release 版已改用 Keychain 不再读取，但明文密钥文件仍是安全遗留物
- **建议**：启动时检测 `keystore/data-key-raw` 存在则尝试删除；删除失败时提示用户手动清理。Debug 版明文密钥文件也应设置 600 权限
- **实施**：Debug 密钥文件 600/目录 700 权限确认已有；Release 首次 key 访问时 `legacyKeystoreCleanup` 删除残留 keystore 目录

### 9. ✅ 无需实施 —— SSH 密码已随数据迁移
- **位置**：Keychain（Dev service `com.sarv.terminal.*.debug` vs Release `com.sarv.terminal.*`）
- **问题**：此前迁移了 hosts/groups 数据，但 SSH 连接密码仍在 Dev 的 Keychain service 下，Release 版需要重新输入
- **建议**：写一次性迁移逻辑（读 Dev service 的密码条目写入 Release service），或提供导入按钮；仅限首次启动检测
- **核实**：SSH 密码并非存于独立 Keychain service，而是存在 `hosts.json` 的 `passwordField` 字段（经 `LocalDataCrypto` AES-256-GCM 加密，密钥随数据迁移成功），Release 版无需重新输入 —— 无需实施

### 10. ⏭️ 跳过（用户要求）swiftlint 未安装
- **位置**：开发环境
- **问题**：AGENTS.md 要求 `swiftlint lint --strict --fix`，但环境中没有 swiftlint，Swift 代码无法自动格式化校验
- **建议**：`brew install swiftlint`；或在 CI 中配置 lint 步骤

### 11. ✅ 仓库残留文件
- **位置**：`macos/build_errors.log`
- **问题**：历史构建失败日志残留在仓库中，易误导排查（且未纳入 gitignore）
- **建议**：删除文件，加入 `.gitignore`
- **实施**：已删除文件，`.gitignore` 增加 `build_errors.log`

## 附：本次改动已确认无问题的点

- `HoverTooltip` 浮窗：无延迟、0.25s 实时刷新、独立窗口不被裁剪、失焦自动隐藏、owner 防串扰 —— 各边界已处理
- 上传冲突：复用 `ConflictDialog`，UI 与 SFTPView/SFTPWindowView 完全一致
- Tab 关闭：Enter 确认 / ESC 取消，与 `SarvAlert` 全局行为一致
- 标签栏箭头：绕过 Mos 滚轮拦截，纯按钮交互无依赖
