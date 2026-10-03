# Meno 开发指南

[← 回到 README](../README.zh-CN.md) · [English](guide.md)

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

### 项目结构

```
Sources/MenoCore   与平台无关的逻辑：模型、设置、规则、布局规划、搜索匹配
Sources/Meno       App 本体：状态栏项目、扫描、展开逻辑、玻璃界面、设置
Tests              MenoCore 单元测试（可在 macOS 和 Linux 上运行）
Resources          Info.plist、App 图标、本地化文件
scripts            打包 App、生成图标、检查本地化
```

### 测试与脚本

- `swift test` 运行 MenoCore 测试（也可在 Linux 上运行）。
- `scripts/check-localization.py` 列出界面文字并检查 `Resources/*.lproj` 中的翻译是否完整。
- `scripts/generate-icon.py` 生成 `Resources/AppIcon.icns`（需要 Pillow 和 numpy）。
- `scripts/measure-footprint.sh` 测量打包好的 App 空闲时的占用，`scripts/check-hiding.sh` 用自己添加的菜单栏项目检查隐藏和显示是否正常，`scripts/check-moving.sh` 检查指针够不到的项目也能移动。CI 在 macOS 15 和 26 上都会运行这三个脚本；它们需要一台没有设置过 Meno 的 Mac，并且运行脚本的 App 有辅助功能权限。环境变量里有 `MENO_DIAG=1` 时，Meno 会把每次扫描和诊断报告输出到标准错误，收到 `SIGUSR1` 时再输出一次报告。环境变量里有 `MENO_MOVE_BY_WINDOW=1` 时，Meno 会通过窗口移动所有项目（平时只对指针够不到的项目这样做）。

### 发布新版本

发布新版本时，推送 `v*` 标签，或在 *Release* 工作流中填写版本号手动运行即可。工作流用的是 [Frit](https://github.com/whrss9527/frit) 里共用的发布流程：配好 Developer ID 的 Secrets 后（见 Frit 的 [docs/release.md](https://github.com/whrss9527/frit/blob/main/docs/release.md)），会签名、公证并钉上票据。发布说明取自 `.github/releases/<标签>.md`。
