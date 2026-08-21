# Work Rhythm 首发与手动更新指南

## 发布范围

首发版本采用 GitHub Releases 分发：客户从固定链接下载 ZIP、手动覆盖 Applications 中的旧 App。应用只会在用户点击“检查更新”时请求 GitHub；不会后台联网、自动下载或自动安装。

首发数据从空白开始。正式版只读取以下目录，不读取或迁移以前的调试数据：

```text
~/Library/Application Support/com.zhanghongyang.workrhythm/state.json
```

其中的 `schemaVersion` 与 App 版本独立。未来改变数据结构时，必须先备份 `state.json`，再按版本逐步迁移；若读取失败，应用必须保留原文件且停止自动保存，不能将其覆盖为空数据。

## 本地生成首发包

在项目根目录执行：

```zsh
macos/scripts/build-release.sh 0.1.0 1
```

生成的文件位于：

```text
artifacts/releases/v0.1.0/
├── Work Rhythm.app
├── Work-Rhythm-macOS.zip
└── Work-Rhythm-macOS.zip.sha256
```

先双击 `Work Rhythm.app` 做一次本机确认。`artifacts/` 与 SwiftPM 的 `.build/` 都是本地生成物，不进入 Git。

## 发布到 GitHub

1. 将发布代码提交并打标签，例如 `v0.1.0`。
2. 在 GitHub 仓库的 **Releases** 页面选择 **Draft a new release**。
3. 选择标签 `v0.1.0`，填写简短更新说明。
4. 上传 `Work-Rhythm-macOS.zip` 和对应的 `.sha256` 文件，然后发布。
5. 将以下最新版本链接发给客户：

```text
https://github.com/zhanghongyang857-dot/work-rhythm/releases/latest
```

若希望客户不需要 GitHub 账号，承载 Release 的仓库必须公开。若源代码不想公开，请建立一个仅用于下载的公开仓库，并把 `UpdateChecker.swift` 中的仓库地址改为该下载仓库。

## 客户安装和更新

首次安装：打开上述链接，下载 `Work-Rhythm-macOS.zip`，解压后将 `Work Rhythm.app` 拖入“应用程序”文件夹。

以后更新：在菜单栏的 Work Rhythm 图标中点击“检查更新”。如有新版，点击“下载 vX.Y.Z”，下载并解压后用新 App 替换“应用程序”中的旧 App。专注数据保存在 Application Support，替换 App 不会删除它。

当前首发包尚未进行 Apple Developer ID 签名和公证。macOS 可能在首次打开时要求用户右键 App 后选择“打开”。后续需要降低安装摩擦时，再补签名和公证；无需迁移到 App Store。

## 每次小版本发布清单

1. 运行两个核心检查：`swift run --package-path macos TimerCoreCheck` 和 `swift run --package-path macos FocusDataCoreCheck`。
2. 递增展示版本和构建号，例如 `0.1.1` 与 `2`。
3. 运行 `macos/scripts/build-release.sh 0.1.1 2`。
4. 本机打开生成的 App，确认版本、计时和手动检查更新入口。
5. 新建 Git tag 和 GitHub Release，上传 ZIP 与校验文件。

发布前应从一个没有安装过该 App 的 macOS 用户账户测试下载、解压和打开流程。
