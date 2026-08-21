# Work Rhythm

Work Rhythm 是一个本地优先的 macOS 工作节律工具。MVP 的核心计时、活动、休息与本地保存已完成，当前进入浮窗体验与可信复盘的整合改进。

## 当前状态

旧 Tauri 原型已从工作目录删除，不再参与开发；完整历史仍可从 Git 初始提交恢复。

当前继续以原生 macOS 调试样机验证，不要求打包、安装或部署；不再回到浏览器原型或旧桌面技术栈。

当前唯一有效的产品与开发执行基准是 [`docs/development-plan-v3.md`](docs/development-plan-v3.md)。原生重启背景见 [`docs/project-status-2026-08-20.md`](docs/project-status-2026-08-20.md)。

首发版本采用 GitHub Releases 下载与应用内手动检查更新。生成发布包、上传 Release 和客户安装说明见 [`docs/first-release-guide.md`](docs/first-release-guide.md)。

## 文档归档

- [`docs/archive/`](docs/archive/)：2026-08-18 的桌面端执行基准与开发交接记录，仅供历史参考，已不再生效。

## 仓库结构

- `macos/`：Swift / SwiftUI 原生实现。
- `docs/`：当前基准、验收记录与历史归档。
