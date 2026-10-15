# Meno 开发指南

[← 回到 README](../README.zh-CN.md) · [English](development.md)

## 开发

构建需要 Xcode 16 或更高版本（液态玻璃需 Xcode 26）。

### 构建与运行

```bash
git clone https://github.com/whrss9527/meno.git
cd meno
make run        # 构建 build/Meno.app 并打开
make install    # 将 Meno.app 拷贝到“应用程序”文件夹
make test       # 运行单元测试
```

`make app` 会在 `build/` 中生成发布版 App 包。设置 `UNIVERSAL=1` 可构建 arm64 + x86_64 通用二进制；设置 `SIGN_IDENTITY="Developer ID Application: …"` 可使用你的证书签名。

默认构建使用临时（ad hoc）签名。macOS 会把隐私权限与签名绑定，因此重新构建后，可能需要在“系统设置 › 隐私与安全性 › 辅助功能”中移除 Meno 再重新添加。使用正式证书签名即可避免。

也可以用 Xcode 打开 `Package.swift` 进行编辑和调试。不过 Meno 未以 App 包形式运行时，macOS 会把权限归到 Xcode 名下，所以测试与权限相关的功能请使用 `make run`。

### 发行渠道与 App Sandbox

Meno 通过 Developer ID 签名及苹果公证发行，不提供 Mac App Store 版：保留当前完整功能与沙盒构建不兼容。苹果[审核指南 §2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)要求 Mac App Store 应用使用沙盒，并通过商店更新；[App Sandbox 文档](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)说明了相关限制。

当前实现依赖：

- `MenuBarScanner.swift` 与 `AX.swift` 读取其他应用的辅助功能树。
- `EventSynthesizer.swift` 向其他进程发送合成点击与拖拽事件。
- `WindowCapture.swift` 通过 `dlsym` 查找 `CGWindowListCreateImage`，捕获屏幕外的窗口。它是已不可用的原公共 API，不是私有符号。
- `PermissionCenter.swift` 运行 `tccutil` 重置辅助功能授权。
- `SpacingController.swift` 写入当前主机的全局偏好，并终止或重新启动其他进程。
- `UpdateInstaller.swift` 替换自身已安装的 App 包。

这里列出的是当前实现依赖，不表示每个 API 在所有沙盒应用中都属于私有或被禁止。商店版需要单独精简的产品和更新路径；给当前目标加一个沙盒权限不会保留 Meno 的完整行为。

### 严格并发

包需要 Swift 6（Xcode 16 或更新版本）。`MenoCore` 使用 Swift 6 语言模式，应用和测试保留 Swift 5 模式。`scripts/check-concurrency.sh` 在新的临时目录中执行完整并发检查，避免增量构建隐藏警告；CI 摘要记录核心与应用的警告数。

核心必须零警告。`scripts/concurrency-baseline.json` 记录应用现有的十条诊断、九个源代码位置，以 Swift 6.3.3 / Xcode 26.6 测得。其他工具链可能报告更少；出现新位置、同一位置增加诊断或总数增加时 CI 失败。修复警告后可以降低基线。移动源代码行时，核对诊断后再调整记录位置，不要为了通过检查提高额度。

### 设置兼容性

`settings.json` 写入 `schemaVersion: 1`，没有版本号的旧文件按同一格式读取。新增键必须提供默认值，保留已有名称和类型，不要改变原有值的含义。破坏兼容的格式变化必须有明确迁移，并在替换前备份。

文件版本较高时，设置窗口会提示。Meno 读取已支持的值、保留较高版本号，写回不认识的键，包括嵌套字段和按身份对应的条目字段。无法解码的条目不生效，但保留原始内容与位置。已知值的编辑优先；删除已识别条目或名称仍会删除它们。已知枚举字段遇到不支持的值时，原有默认回落行为保持不变。导入、导出、备份、延迟保存和退出时写入都使用 `MenoSettings.decode(from:)` / `encoded()`，不要直接编码模型绕过保留机制。

### 项目结构

```
Sources/MenoCore   与平台无关的逻辑：模型、设置、规则、布局规划、搜索匹配
Sources/Meno       App 本体：状态栏项目、扫描、展开逻辑、玻璃界面、设置
Tests              MenoCore 单元测试（可在 macOS 和 Linux 上运行）
Resources          Info.plist、App 图标、本地化文件
scripts            打包 App、生成图标、检查本地化
```

### 测试与脚本

- `scripts/check-image-cache.sh` 将正式图标缓存与可暂停的内存捕获依赖一起编译，验证清理、旧结果失效、重新启用和 30 秒复用/重试边界，不捕获实际窗口，也不修改权限。CI 在 macOS 15 和 26 上运行。
- `scripts/check-command-checks.sh` 编译正式命令观察器并使用隔离的 shell 夹具。十个慢命令验证暂停会终止当前自有进程组，剩余命令不再启动；替换请求和已排队回调验证结果归属。同一 driver 在 macOS 使用 zsh、在 Linux 使用 sh。取消在原有 20ms 等待循环中检查，单命令五秒时限与输出丢弃保持不变。每轮使用五秒单调时钟预算及轮转游标；被整轮剩余预算截断的命令在下一轮取得完整执行机会，不作为普通失败。已完成观测60个连续秒（含睡眠）后过期。未知命令条件不激活新规则，也不单独撤销已有规则；已知条件仍对AND/OR短路，停用仍立即结束，未知时间会重置尚待满足的最短持续时间。旧Core布尔快照兼容原语义。生产driver另验证十命令公平轮转、部分轮次结果准入和有效期边界；Core验证未知状态转移。
- `scripts/check-single-instance.sh` 启动两份临时测试 App，调用正式单实例竞争逻辑；两份都启动后同时放行，3 秒后必须恰好保留进程号较小的一份，重复三次。不启动菜单栏控制器，也不修改用户设置；CI 在两个 macOS 版本上运行。
- `scripts/check-updating.sh` 将测试入口与正式更新器和提示界面一起编译。一次性的 ad hoc 签名 App 和独立的偏好域用于验证 0.0.1 → 0.0.2 安装、下载清理、启动即退出时的回滚和可见提示，不启动菜单栏控制器，也不修改 Meno 设置。CI 在 main 和手动运行时执行。`MENO_UPDATE_URL` 可以指向回环地址的发布 JSON；本地压缩包必须同源，安装器仍会执行全部验证。
- `swift test` 运行 MenoCore 测试。CI 除了两个 macOS runner，也会在 Linux 上用 Swift 6 运行测试和本地化检查。main 推送和所有 PR（含 fork）都以只读权限运行检查，不使用发布凭据。还没有 PR 的分支可通过 `workflow_dispatch` 验证，其他分支推送不会在 PR 之外再启动一套检查。PR、main 推送和手动运行分别使用并发组；新任务只替换同一 PR 或同一事件/引用的旧任务，因此手动验证分支不会取消 PR 的必要检查。库存构建、展开计数和分隔符修复决策是核心模块中的纯逻辑；辅助功能对象、计时器和系统操作仍保留在 App 中。
- `scripts/check-secure-input.sh` 用真实的安全键盘输入检查等待和取消，再用两个临时 helper 项目实测窗口与指针两条移动路径。需要辅助功能权限，以及没有其他安全输入持有进程的测试 Mac；CI 在 macOS 15 和 26 上运行。
- `scripts/check-localization.py` 列出界面文字并检查 `Resources/*.lproj` 中的翻译是否完整。
- `scripts/generate-icon.py` 生成 `Resources/AppIcon.icns`（需要 Pillow 和 numpy）。
- `scripts/measure-footprint.sh` 测量打包好的 App 空闲时的占用（默认设置一次，加上 20 个其他 App 的项目、悬停显示和一条规则再一次），超过上限就失败，`scripts/check-hiding.sh` 用自己添加的菜单栏项目检查隐藏和显示是否正常，并检查放到 Meno 图标右侧的“隐藏”分隔符会被移回左侧，`scripts/check-moving.sh` 检查 Meno 能通过窗口把自己添加的项目移到常显再移回去。每次检查提交时，CI 在 macOS 15 和 26 上都会运行隐藏与移动脚本；空闲占用仅在 main 和手动运行时测量。手动运行时还可以用 *runner* 输入再加一个 runner，比如新的 macOS；它们需要一台没有设置过 Meno 的 Mac，并且运行脚本的 App 有辅助功能权限。环境变量里有 `MENO_DIAG=1` 时，Meno 会把每次扫描和诊断报告输出到标准错误，收到 `SIGUSR1` 时再输出一次报告。

### 发布新版本

发布新版本时，推送 `v*` 标签，或在 *Release* 工作流中填写版本号手动运行即可。工作流用的是 [Frit](https://github.com/whrss9527/frit) 里共用的发布流程：配好 Developer ID 的 Secrets 后（见 Frit 的 [docs/release.md](https://github.com/whrss9527/frit/blob/main/docs/release.md)），会签名、公证并钉上票据。发布说明取自 `.github/releases/<标签>.md`。

macOS 26 及以前的后台补漏扫描，仅在菜单栏窗口编号、所属进程和位置尺寸均未变化时复用已完成的扫描。主动刷新仍执行扫描，macOS 27 保留原有行为。诊断日志用 `mode=full` 和 `mode=skipped` 区分扫描与跳过；占用摘要包含跳过比例和两次采样均存活进程的 CPU，runner 后台活动会影响这一指标。手动运行 CI 时开启 `compare_scans` 可对比关闭和开启优化；本地基线可设置 `MENO_SCAN_GATE=0`。

CI 要求 `VERSION` 对应的发布说明文件存在且非空。发版工作流在构建前检查输入版本或标签是否与 `VERSION` 一致；版本不符或说明缺失时停止发布。

### 共用发行归档验收

发行workflow与`frit-ref`一起固定Frit0.4.1的`2291523e16c91afae06868d7c4e188efc36cd70b`，继续要求公证。公开前重新解压最终ZIP，核对全架构签名、已校验票据对每个根架构的覆盖，以及启用的Gatekeeper与明确公证Developer ID来源。失败保留原归档，公开发行不覆盖。已有`dry_run`在当前源码构建并验收，不创建标签或发行，也可用于已经公开的版本。纯workflow升级保留Meno版本与Swift包依赖。

## App Intents 元数据探测

给 SwiftPM App 加入快捷指令动作前，先运行 **App Intents metadata probe** 工作流。它用 Xcode 16.4 和最新正式版构建隔离样例，尝试从普通 SwiftPM 可执行文件提取元数据，再用相同源码的原生 Xcode App 构建作对照。另取当前 SDK 实际生成的编译器协议清单，验证显式导出常量值的 SwiftPM 路径，保留清单与独立结果。样例不初始化 Meno，不读取其设置或调用辅助功能接口。

artifact 保留命令退出码、完整日志、工具链与实际元数据。`report.json` 分别记录 `swiftpm_metadata`、`swiftpm_explicit_constants_metadata` 与 `native_metadata`；工作流成功要求原生对照和显式常量导出的 SwiftPM 路径都确实包含 Intent 和 AppShortcut，不表示 SwiftPM 路径已成功、不证明所有 SwiftPM 配置都不可行，也不等于真实快捷指令或 Spotlight 索引已验收。在实际接入通过完整 App 与签名发行门禁前，保持生产打包路径。

Xcode 16.4 与 26.3 的实测结果：普通 SwiftPM 编译和提取命令都返回成功，但没有常量值文件，也没有 Intent 元数据；原生对照及显式导出常量值的 SwiftPM 构建都生成了有效元数据。后续保留 SwiftPM，启用常量值导出并用匹配且已验证的编译器协议配置提取元数据。样例通过不等于生产接入完成：禅模式和场景动作发布前，仍需验证真实 Meno App、通用版打包、本地化、签名与运行行为。
