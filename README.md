# Work Rhythm

Work Rhythm 是一个本地优先的 macOS 工作节律工具。当前从 V0 桌面浮窗样机重新开始开发。

## 当前状态

旧 Tauri 原型已从工作目录删除，不再参与开发；完整历史仍可从 Git 初始提交恢复。

下一阶段回到产品问题与核心使用闭环，先以本地浏览器原型快速验证，不要求打包、安装或部署 macOS App。

当前唯一有效的产品与开发执行基准是 [`docs/development-baseline-v2.md`](docs/development-baseline-v2.md)。项目冻结原因与重启背景见 [`docs/project-status-2026-08-20.md`](docs/project-status-2026-08-20.md)。

## 文档归档

- [`docs/archive/`](docs/archive/)：2026-08-18 的桌面端执行基准与开发交接记录，仅供历史参考，已不再生效。

## 仓库结构

- `macos/`：新的 Swift / SwiftUI 原生实现；下一步仅在此创建 V0 浮窗样机。
- `docs/`：当前基准、验收记录与历史归档。
