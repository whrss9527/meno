<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Meno 图标">
  <h1>Meno</h1>
  <p><strong>一个安静的菜单栏，由玻璃打造。</strong></p>
  <p>原生 macOS 菜单栏管理工具，采用液态玻璃（Liquid Glass）风格界面。</p>
  <p>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?logo=apple&logoColor=white">
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white">
    <img alt="Liquid Glass" src="https://img.shields.io/badge/UI-Liquid%20Glass-7C6CFF">
    <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2563EB"></a>
  </p>
  <p><a href="README.md">English</a></p>
</div>

Meno 会把你不常用的菜单栏图标收起来，需要时点按、悬停、轻扫或按下快捷键即可唤回。一切都能用键盘直达，菜单栏还能根据你正在做的事情自动调整。

## 功能

### 隐藏与显示

- **三个分区。** “常显”中的项目始终显示；“隐藏”中的项目按需出现；“暗格”存放几乎用不到的项目——它们从不出现在菜单栏中，只能通过托盘、快速打开或按住 ⌥ 点按来访问。
- **多种展开方式：** 点按 Meno 图标、点按或悬停在菜单栏空白处、在菜单栏上向下滚动或轻扫，或使用全局快捷键。
- **智能重新隐藏：** 延迟一段时间后、切换 App 或点按别处时、指针离开菜单栏时自动收起；项目的菜单打开期间不会收起。
- **按需腾出空间：** 展开时可暂时隐藏前台 App 的菜单，让一长排图标也能放得下。

### 玻璃界面

- **托盘（Shelf）：** 菜单栏下方的液态玻璃浮条，展示隐藏的项目。刘海附近菜单栏空间不够时尤其好用。选择“自动”展开方式时，只有放不下时才会使用托盘。
- **快速打开：** Spotlight 风格的面板，支持模糊搜索、拼音与首字母匹配（如输入 “wx” 找到“微信”），用键盘打开任意菜单栏项目。↩ 打开，⌘↩ 打开辅助菜单，⌥↩ 在菜单栏中展开该项目，⌘1–⌘9 快速选择。
- **布局编辑器：** 在“常显”“隐藏”“暗格”三条通道之间拖移项目，或拖到其他项目旁边调整顺序，Meno 会替你完成 ⌘ 拖移。
- macOS 26 及以上使用液态玻璃；macOS 14 和 15 使用带高光边缘的磨砂玻璃效果。

### 个性化

- **规则：** “当 Keynote 在前台时，开启禅模式。”条件包括前台或正在运行的 App、电池与电源、外接显示器、时间段、离线状态；动作包括展开或隐藏分区、应用场景、开启禅模式、移动指定项目，并可在条件结束后自动撤销。
- **场景：** 存储“工作”“居家”“演示”等布局，可从菜单或规则中一键切换。
- **禅模式：** 一个快捷键清空所有 App 图标，只保留系统状态，适合截图、录屏和演讲。
- **项目快捷键：** 在任何地方打开指定项目（Wi-Fi、VPN、计时器……），即使它处于隐藏状态。
- **标记：** 在菜单栏中添加空白、细线、圆点、SF 符号或简短文字标签，为图标分组。
- **洞察：** 完全本地的使用统计——展开次数、最常用的项目，以及“这个项目本周在隐藏状态下被打开了 12 次，要保持显示吗？”之类的建议。
- **新图标提醒：** App 新增菜单栏图标时，可以询问你、自动隐藏或放入暗格。
- **外观：** 自选 Meno 图标、分隔符样式、托盘玻璃与着色；菜单栏着色支持渐变、边框、阴影和分离式“岛屿”形状（实验性）；可调整系统级图标间距（测试版）。
- 支持简体中文与英文。

## 系统要求

- macOS 14 Sonoma 或更高版本。液态玻璃需要 macOS 26，并使用 Xcode 26 构建。
- 构建需要 Xcode 16 或更高版本（液态玻璃需 Xcode 26）。

## 下载

预编译版本会附在 [Releases](https://github.com/whrss9527/meno/releases) 中（推送 `v0.1.0` 这样的版本标签即可自动发布），每次 CI 运行也会上传 `Meno.zip` 构建产物。这些版本使用临时签名，首次打开时 macOS 会要求确认：右键点按 Meno.app 并选择“打开”，或运行 `xattr -dr com.apple.quarantine /Applications/Meno.app`。

## 构建与运行

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

## 权限

| 权限 | 用途 |
| --- | --- |
| **辅助功能**（必需） | 读取菜单栏项目，通过托盘、快速打开和快捷键打开它们，并用 ⌘ 拖移进行整理。 |
| **屏幕录制**（可选） | 显示隐藏项目的真实图标（macOS 14–26）。未授权时显示 App 图标。只会截取菜单栏项目。 |

Meno 没有联网功能、数据分析或账户。设置与统计数据保存在 `~/Library/Application Support/Meno`。

## 工作原理

Meno 会在菜单栏中添加小小的分隔符：单箭头是“隐藏”分区的起点，双箭头是“暗格”的起点。分隔符左侧的一切都属于对应的分区。按住 ⌘ 把图标拖过分隔符，或使用布局编辑器即可调整。

隐藏某个分区时，它的分隔符会变宽，直到左侧的项目放不下：

- **宽分隔符引擎（macOS 14–26）：** 单个分隔符延伸到屏幕边缘之外。
- **阶梯式引擎（macOS 27）：** macOS 27 的菜单栏会丢弃宽度超过约半个屏幕的项目，而且一次性大幅改变长度不会带动相邻项目。Meno 会让分隔符和几个辅助占位项以 40 pt 为一步逐渐加宽，每个都略低于该上限。被推开的项目会进入系统的溢出菜单。可在“设置 › 通用 › 高级”中选择引擎。

菜单栏项目通过各个 App 的辅助功能树读取，适用于所有支持的 macOS 版本，包括 macOS 27 的单窗口菜单栏。

## 注意事项

- 移动项目是通过模拟 ⌘ 拖移完成的，Meno 会短暂接管指针，结束后放回原处。当前不在屏幕上的项目无法拖移，请先把它展开。时钟和控制中心图标无法移动。
- 图标间距使用 `NSStatusItemSpacing` 与 `NSStatusItemSelectionPadding` 偏好设置，App 只在启动时读取，因此应用时会重新打开带有菜单栏项目的 App。
- 菜单栏着色绘制在菜单栏后方，在 macOS 26 及以上的透明菜单栏上效果最明显。

## 项目结构

```
Sources/MenoCore   与平台无关的逻辑：模型、设置、规则、布局规划、搜索匹配
Sources/Meno       App 本体：状态栏项目、扫描、展开逻辑、玻璃界面、设置
Tests              MenoCore 单元测试（可在 macOS 和 Linux 上运行）
Resources          Info.plist、App 图标、本地化文件
scripts            打包 App、生成图标、检查本地化
```

## 开发

- `swift test` 运行 MenoCore 测试（也可在 Linux 上运行）。
- `scripts/check-localization.py` 列出界面文字并检查 `Resources/*.lproj` 中的翻译是否完整。
- `scripts/generate-icon.py` 生成 `Resources/AppIcon.icns`（需要 Pillow 和 numpy）。

## 许可协议

Meno 以 [MIT 许可协议](LICENSE) 发布。
