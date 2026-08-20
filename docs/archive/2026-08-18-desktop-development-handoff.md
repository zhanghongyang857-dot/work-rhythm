# Work Rhythm 开发交接记录（2026-08-18）

## 当前状态

M0、M1、M2、M3 已完成；M4 尚未开始。

项目是仅 macOS 的 Tauri 2 + React + TypeScript 本地应用。数据保存在 macOS 应用数据目录中的 SQLite，不存在账号、同步、遥测或后台网络请求。

## 本次完成内容

### M0：应用外壳

- 主窗口、独立 `mini-timer` 悬浮窗、菜单栏入口。
- Mini Timer 可拖动、置顶、隐藏；关闭主窗口只隐藏应用，不退出。
- 双圆环与本地秒级显示更新。

### M1：活动与计时

- SQLite 版本化迁移，包含 `activities`、`time_entries`、`entry_pauses`、`break_entries`、`reminder_rules`、`settings` 等表和必要索引。
- 活动创建、编辑、归档、选择后开始。
- 开始、暂停、继续、结束、切换活动。
- 数据库局部唯一索引和 service 双重确保同一时刻只有一条未结束的计时记录。
- 暂停时段从专注时长中扣除；切换活动在同一事务中结束旧记录并创建新记录。
- 当前计时由时间戳推导，重启后可恢复；统计对片段按当地日边界切分。

### M2：休息与提醒

- 全局专注/休息分钟数、启用开关、勿扰时间段、IANA 时区设置。
- 默认专注 50 分钟、休息 5 分钟。
- 原生后台线程按下一次到期时间单次等待；到期后发送 macOS 本地通知并刷新窗口。
- 开始休息、结束休息、延后指定分钟数、跳过休息均会记录或重算下一周期。

### M3：管理与统计

- “今天、活动、统计、设置”四个可用页面。
- 今日记录时间线、删除、编辑已结束记录、手动补录。
- 最近 28 天专注/休息时长、活动归属、小时活跃图与主要活跃时段。
- ECharts 只在统计页动态导入；离开统计页会销毁图表实例。
- JSON/CSV 导出与完整 SQLite 文件备份，输出路径会显示在设置页。

## 关键文件

| 位置 | 职责 |
| --- | --- |
| `src-tauri/src/db.rs` | 应用数据目录、SQLite 打开与迁移、原生提醒调度线程。 |
| `src-tauri/src/services.rs` | 状态机、数据库业务、提醒状态、统计、导出与备份；原生测试也在此。 |
| `src-tauri/src/commands.rs` | 所有 Tauri IPC 写入入口与跨窗口事件发送。 |
| `src-tauri/src/domain.rs` | IPC DTO 和输入模型。 |
| `src-tauri/src/lib.rs` | Tauri 初始化、菜单栏、窗口创建、插件和命令注册。 |
| `src/lib/native-client/api.ts` | 前端唯一的 Tauri `invoke` 调用点。 |
| `src/windows/mini-timer/MiniTimer.tsx` | 独立悬浮计时器、活动开始、暂停/继续、休息操作。 |
| `src/windows/main/Pages.tsx` | 今天、活动、统计、设置、补录与历史编辑界面。 |
| `src/windows/main/HourlyChart.tsx` | 统计页动态加载 ECharts。 |

## IPC 与事件

当前命令使用下划线命名，例如 `timer_start`、`activities_create`、`analytics_get_summary`；前端应始终经 `src/lib/native-client/api.ts` 调用，不能在页面中直接 `invoke`。

跨窗口事件只使用：

- `timer:changed`
- `activity:changed`
- `settings:changed`

不要新增秒级 IPC、秒级数据库写入或数据库轮询。Mini Timer 可每秒用已有状态和本地系统时间更新显示。

## 验证结果

已通过：

```bash
npm run check
npm run test
npm run format:check
npm run build
cargo fmt --manifest-path src-tauri/Cargo.toml --check
cargo check --manifest-path src-tauri/Cargo.toml
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri -- build --debug
```

原生测试覆盖：

- 不能同时存在两条未结束计时记录。
- 切换活动后只有新记录保持未结束。
- 暂停时段不计入专注时长。

调试 DMG：`src-tauri/target/debug/bundle/dmg/Work Rhythm_0.1.0_aarch64.dmg`。

## 已知限制与下次优先事项

1. 尚未在真实连续使用中覆盖睡眠/锁屏唤醒、跨时区、夏令时、跨午夜、通知权限拒绝等场景；这是 M4 的首要验证项。
2. 应用尚未做 M0/M4 所要求的 M0/M1 机器资源基线与长期 CPU/内存观测。
3. 统计图的 ECharts 动态 chunk 较大，但仅在进入统计页时加载；可在 M4 测量后考虑进一步按需引入 ECharts 模块。
4. 当前历史列表仅展示“今天”的记录；补录和编辑可用，但如果需要按日期浏览完整历史，应在 M4 添加日期范围选择与分页，不应改变现有时间事实模型。
5. 导出和备份当前写入应用数据目录下的 `exports/` 与 `backups/`；若改为让用户选目录，应通过 Tauri dialog 插件实现，仍由原生 command 写文件。
6. M4 尚缺：菜单栏快捷开始/暂停、窗口偏好持久化、无障碍审查、深色模式实机检查、两周真实使用的异常修复。

## 下次开发建议顺序

1. 安装并运行调试版，建立 M0/M1 基线：Mini Timer 常驻、主窗口打开、统计页打开/关闭后的 CPU 与内存。
2. 手工执行基准文档第 10 节中与睡眠、跨午夜、时区和通知相关的场景，记录问题。
3. 先修正任何时间事实或提醒遗漏，再补 M4 的快捷操作、窗口偏好与无障碍。
4. 功能改动后同时运行前端和 Rust 校验命令；涉及计时状态机或统计的变更必须增加 Rust 测试。

## 不要回退的约束

- 事实时间必须来自 UTC 毫秒时间戳，不能持久化每秒累加值。
- SQLite 是唯一事实来源；统计缓存若以后加入只能是可删除的派生数据。
- 所有写入都经 Tauri command 和 Rust service；不要由 React 直接写数据库或维护权威计时状态。
- 一次只允许一条未结束的 `time_entry`。
- 不加入登录、云同步、遥测、浏览器/应用内容监控、待办、日历整合或网络 SDK。
