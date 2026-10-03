# 工作约定

## 待办

- 开发任务是本仓库标了 `agent` 的 issue。找任务、认领（加 `doing` 标签并评论）、卡住时怎么办，见 whrss9527/plan 的 AGENTS.md 里「用 issue 管任务的项目」一节；plan 是私有仓库，需要时先把它加进会话。
- 一个 issue 一个分支、一个 PR，PR 描述写 `Closes #编号`。不要自己关 issue；本人没在会话里直接要求时，不合并 PR，也不发版。

## 构建和测试

见 [docs/development.md](docs/development.md)：构建、运行、测试、端到端脚本和发版都在那里。提交前至少跑 `swift test` 和 `python3 scripts/check-localization.py`。不在 Mac 上时以 CI 为准：每次推送（任何分支）都会在 macOS 15 和 26 上编译、跑单元测试和端到端脚本。

## 本仓库的约定

- **写法**：代码注释、提交信息、README.md 和 docs/ 里的英文文档用英文，风格照 git log。README.zh-CN.md 和 docs/*.zh-CN.md 是中文版，改了英文版要一起改。
- **界面文字**：代码里写英文原文（`Text("…")`、`String(localized: "…")` 等），英文原文就是翻译表的 key。加了或改了一条，`Resources/zh-Hans.lproj/Localizable.strings` 和 `Resources/zh-Hant.lproj/Localizable.strings` 都要有翻译：
  - 繁体中文用台湾 macOS 的用词，比如「選單列」「設定」「快速鍵」「還原」「瀏海」「結束」。
  - 改完跑 `python3 scripts/check-localization.py`，要 0 missing、0 unused。
- **发布说明**：
  - 每个版本写在 `.github/releases/v<版本>.md`：先英文，后中文，中间用单独一行 `---` 隔开。
  - 英文的 Install or update、Known limitations 和中文的「安装与更新」「已知限制」照着上一版保留、按需更新。
  - 每条一两句话，写用户能感觉到的变化。
  - 版本号在 `VERSION` 文件里。App「关于」页的更新说明读的就是这些文件，所以每个版本都要有。
- **端到端脚本**：`scripts/check-hiding.sh`、`scripts/check-moving.sh` 和 `scripts/measure-footprint.sh`，参数是 `make zip` 打包出来的 `build/Meno.app`。
  - 它们要在一台没有设置过 Meno 的 Mac 上跑，运行脚本的 App（比如终端）要有辅助功能权限。
  - 环境变量 `MENO_DIAG=1` 让 Meno 把扫描、移动和诊断报告输出到标准错误，收到 `SIGUSR1` 时再输出一次报告；脚本就靠这些来判断结果。
  - CI 每次都跑前两个；测空闲占用只在 main 上和手动运行时跑。check-moving 在 macOS 27 上会跳过。
