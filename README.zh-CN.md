<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Meno 图标">
  <h1>Meno</h1>
  <p><strong>安静的菜单栏，由玻璃打造</strong></p>
  <p>住在 macOS 菜单栏里的菜单栏管家。原生 Swift，玻璃质感，开源免费。</p>
  <p>
    <a href="https://github.com/whrss9527/meno/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/whrss9527/meno?include_prereleases&label=release&color=7C6CFF"></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?logo=apple&logoColor=white">
    <img alt="Liquid Glass" src="https://img.shields.io/badge/UI-Liquid%20Glass-7C6CFF">
    <a href="LICENSE"><img alt="GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-2563EB"></a>
  </p>
  <p>
    <a href="https://github.com/whrss9527/meno/releases/latest"><b>下载</b></a> ·
    <a href="https://github.com/whrss9527/meno/releases">更新日志</a> ·
    <a href="README.md">English</a>
  </p>
</div>

### **Meno** /ˈmeː.no/

意大利语，意思是“少一点”。

乐谱里的 *meno mosso*，意思是“慢一点，别那么急”。

菜单栏也应该少一点：常用的留下，不常用的先收起来；需要的时候，再把它叫出来。

而且 **Meno** 和 **Menu** 只差一个字母——少一点，刚刚好。

## 特性

- **不常用的收起来**：常显、隐藏，再加一个“暗格”，放那些几乎用不到的图标。
- **想怎么叫出来都行**：点一下、悬停、轻扫、按快捷键都行；快速打开还能用键盘直接找到任何一个。
- **从里到外都是玻璃**：菜单栏下方的托盘、Spotlight 风格的快速打开，macOS 26 上是液态玻璃。
- **会看场合的菜单栏**：麦克风开着、接上显示器、拔掉电源时，规则和场景自动帮你调好。
- **一键禅模式**：所有 App 图标一下清空，截图、录屏、演讲都干干净净。
- **不碰你的隐私**：没有数据分析，没有账户，只在检查和下载更新时联网。

## 安装

需要 macOS 14 Sonoma 或更高版本，Apple 芯片和 Intel 都支持。

用 [Homebrew](https://brew.sh) 安装：

```sh
brew install --cask whrss9527/tap/meno
```

或者手动安装：

1. 从[最新版本](https://github.com/whrss9527/meno/releases/latest)下载 `Meno.zip`，解压后把 Meno.app 移到“应用程序”。
2. 打开后，在“系统设置 › 隐私与安全性 › 辅助功能”里允许 Meno。
3. 有新版本时选“安装并重新打开”，Meno 会自己更新。

从 0.10.0 起的版本用 Developer ID 签名并经过苹果公证，双击就能打开。

## 上手

| 操作 | 效果 |
| --- | --- |
| 按住 ⌘，把图标拖过 Meno 的分隔符 | 分到常显、隐藏或暗格 |
| 点 Meno 图标或菜单栏空白处（悬停、向下轻扫可在设置里打开） | 隐藏的图标回来 |
| 在“设置 › 快捷键”里设好快速打开的快捷键，然后按下它 | 用键盘找到并打开任意菜单栏项目 |
| 开启禅模式 | 所有 App 图标一下清空，截图、录屏、演讲都干净 |
| 在设置里加一条规则 | 菜单栏跟着麦克风、显示器、电源或网络自动调整 |

## 文档

- [使用指南](docs/guide.zh-CN.md)：安装与更新、全部功能、`meno://` 链接、工作原理、资源占用、权限与隐私、常见问题
- [开发指南](docs/development.zh-CN.md)：构建运行、项目结构、测试与发布
- [更新日志](https://github.com/whrss9527/meno/releases)

## 支持

Meno 免费开源。觉得好用的话，点个 ⭐ Star 就是很大的鼓励；也可以微信扫一扫请我喝杯咖啡。

<p align="center"><img src="docs/donate-wechat.png" width="240" alt="微信赞赏码：请我喝杯咖啡"></p>

## 许可证

Copyright © 2026 whrss9527

Meno 是自由软件，以 [GNU 通用公共许可证第 3 版（GPL-3.0）](LICENSE) 发布：可以自由使用、研究、修改和分享；分发 Meno 或修改后的版本时，需要以同样的许可证提供源代码。

「Meno」这个名字和 Meno 的图标不在 GPL 授权范围内（GPL-3.0 第 7 条 e 项）。介绍 Meno、分享未经修改的副本时可以使用；分发修改后的版本时，请换用自己的名字和图标。

贡献需接受 [CONTRIBUTING.md](CONTRIBUTING.md) 中的贡献者协议。

Meno 0.1.0 以 MIT 许可协议发布，这个版本仍然适用 MIT 许可协议。

---

<div align="center">
  <p><b>同样住在菜单栏里</b></p>
  <a href="https://github.com/whrss9527/pop"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/pop.svg" width="30%" alt="Pop：长按右键，一划即达"></a>
  <a href="https://github.com/whrss9527/stox"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/stox.svg" width="30%" alt="Stox：一眼看盘，一键隐身"></a>
  <a href="https://github.com/whrss9527/proxi"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/proxi.svg" width="30%" alt="Proxi：一个开关，管好所有代理"></a>
</div>
