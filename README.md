# Work Rhythm

一个完全本地运行的个人工作节律助手：计时、休息提醒、长期活动记录，以及每日／每月的工作节律统计。

开发以 [`docs/implementation-baseline.md`](docs/implementation-baseline.md) 为唯一执行基准。其中包含范围、交互规则、技术架构、数据模型、轻量化约束、开发顺序与验收条件。

本次实现的交接说明见 [`docs/development-handoff-2026-08-18.md`](docs/development-handoff-2026-08-18.md)，包括已完成范围、验证结果、已知限制和下次开发顺序。

## 当前状态

已完成 M0–M3：Tauri + React + TypeScript 双窗口、菜单栏、SQLite 迁移、活动管理、计时状态机、休息提醒、本地通知、今天页、历史补录、统计，以及 JSON／CSV 导出和 SQLite 备份。

所有事实数据均写入 macOS 应用数据目录下的 SQLite 数据库。Mini Timer 仅在可见时本地更新显示；不会进行秒级 IPC 或数据库写入。

## 本地运行

需先安装 Node.js 以及 [Rust 工具链](https://www.rust-lang.org/tools/install)，然后在本目录执行：

```bash
npm install
npm run tauri dev
```

常用校验：

```bash
npm run check
npm run test
npm run format:check
cargo check --manifest-path src-tauri/Cargo.toml
```
