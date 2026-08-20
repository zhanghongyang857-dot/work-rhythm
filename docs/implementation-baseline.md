# Work Rhythm 开发基准

> 本文是开始开发后的**唯一执行基准**。当其他分析文档与本文不一致时，以本文为准；其他文档作为产品背景、架构细节和轻量化理由保留。

## 0. 一句话定义

一个 macOS 本地优先的个人工作节律应用：常驻桌面悬浮计时器显示“今天已学习多久”和“距离下次休息多久”；后台面板管理长期活动、查看时间记录和做日／月复盘。

## 1. 第一版边界

### 必须交付

1. 一个可拖动、可隐藏、始终置顶的 Mini Timer。
2. Mini Timer 中两个并列的圆环：左边是当天累计专注时长，右边是当前专注周期距提醒的倒计时。
3. 长期活动：创建、编辑、归档、选择后开始计时。
4. 一个且仅一个未结束的计时记录：开始、暂停、继续、结束、切换活动。
5. 可配置的本地休息提醒：默认专注 50 分钟、休息 5 分钟；支持开始休息、延后 10 分钟、跳过。
6. 后台面板：今天、活动、统计、设置四页。
7. 统计：今天、日／周／月活动时长；最近 28 天的小时活跃度；主要活跃时段。
8. SQLite 本地存储、历史编辑／补录、JSON 与 CSV 导出。
9. 重启、睡眠唤醒、跨午夜后数据不丢且时长口径正确。

### 明确不做

- 登录、云同步、服务器、遥测和任何后台网络请求。
- 任务管理、待办事项、项目协作、日历整合。
- 自动读取浏览器／应用使用情况。
- 主题商店、皮肤、可拖拽仪表盘、复杂目标系统。
- 移动端、Web 公共版本、自动更新。

这些内容没有对应数据模型和接口，开发中不得顺手加入。

## 2. 已确定的产品决策

| 决策项 | 结论 |
| --- | --- |
| 支持平台 | 仅 macOS；不为其他平台做兼容抽象 |
| 应用形态 | Tauri 本地桌面应用，而非浏览器网页或 macOS WidgetKit 小组件 |
| 常驻界面 | Mini Timer 独立悬浮窗；主窗口关闭不退出应用 |
| 默认节律 | 专注 50 分钟，休息 5 分钟；用户可在设置中修改或关闭 |
| 计时展示 | 左环为当天累计工作时长，右环为离下一次休息的倒计时 |
| 数据位置 | 本机 SQLite；用户主动导出／备份 |
| 隐私 | 默认零网络、零第三方分析、零内容监控 |
| UI 方向 | 系统字体与灰阶；专注紫蓝、休息绿色；少组件、少动画 |
| 统计起点 | 只在有真实时间记录后展示；不预置虚构数据 |

“今天已学习”是 Mini Timer 的用户可见文案。内部数据概念统一称为“专注时长”，以兼容看论文、写作、编码和其他长期活动。

## 3. 运行时结构

```text
用户操作
  ├─ Mini Timer
  ├─ 后台主窗口
  ├─ 菜单栏
  └─ 系统通知
          │
          ▼
Tauri command（唯一写入入口）
          │
          ▼
Rust domain service（状态机、提醒、统计、恢复）
          │
          ▼
SQLite repository（事务与查询）
          │
          ▼
timer:changed / activity:changed / settings:changed
          │
          ▼
可见 React 窗口刷新查询；各窗口本地展示倒计时
```

### 窗口规则

| 名称 | 何时存在 | 允许做什么 | 禁止做什么 |
| --- | --- | --- | --- |
| `mini-timer` | 应用常驻期间，用户可隐藏 | 显示双圆环、暂停／继续、切换活动 | 加载图表、全量历史、复杂路由 |
| `main` | 首次启动时打开；之后按需创建或显示 | 今天、活动、统计、设置 | 承担后台定时器／提醒权威 |
| 菜单栏 | 应用未退出时常驻 | 显示状态、快速打开／隐藏、退出 | 保存业务状态 |
| 通知 | 到点才触发 | 提醒用户并打开 Mini Timer | 成为唯一可操作入口 |

主窗口的实际策略：开发初期关闭时隐藏；在 M0／M1 测量内存后决定是否改为关闭即销毁。无论选哪种，Mini Timer 必须独立且不受影响。

## 4. 时间、状态与口径（不可违反）

### 4.1 时间规则

- 数据库存 UTC Unix 毫秒；显示与统计按用户设置的本地时区转换。
- 时间事实由开始、暂停、恢复、结束的系统时间戳组成，不能用“每秒加一”的计数值持久化。
- 当前持续时长 = 当前系统时间 − 开始时间 − 所有已完成及当前暂停段的时长。
- 统计时每一段都先按本地日／小时边界切分，再汇总；跨午夜必须分到两个自然日。
- 应用启动或电脑唤醒后重新用时间戳计算，不回放每秒回调。

### 4.2 计时状态机

```text
idle ── start(activity) ──> running ── pause ──> paused
                              │                      │
                              ├── stop ──────────────┤
                              │                      └── resume ──> running
                              └── switch(activity) ──> stop old + start new
```

全局规则：任何时刻最多一个未结束的 `time_entry`（`running` 或 `paused`）。切换活动必须在同一数据库事务中结束旧记录、建立新记录；不能产生并行记录。

### 4.3 休息状态

休息是独立记录，不改变当前活动的历史归属。到期后用户可执行：

- `start_break`：创建休息记录，右环显示休息倒计时。
- `defer_break(10)`：不创建休息记录，下次提醒变为当前时间后 10 分钟。
- `skip_break`：记录一次跳过，开始新的专注周期。
- `complete_break`：结束休息记录，开始新的专注周期；默认不自动恢复活动计时，用户主动继续或选择活动后再开始。

任何通知动作无法可靠回传时，通知仅负责唤起应用；实际状态变化必须通过应用内 command 完成。

## 5. 数据模型（第一版固定）

| 表 | 最小职责 | 必要字段／约束 |
| --- | --- | --- |
| `activities` | 长期可复用活动 | `id`、`name`、`color`、`icon?`、`category?`、`is_archived`、创建／更新时间 |
| `time_entries` | 一段活动的开始到结束 | `id`、`activity_id?`、`started_at_utc`、`ended_at_utc?`、`status`、`source`、`note?` |
| `entry_pauses` | 一段活动中的暂停区间 | `id`、`time_entry_id`、起止时间；每项最多一个未结束暂停 |
| `break_entries` | 实际休息或休息结果 | `id`、起止时间、`trigger`、`status` |
| `reminder_rules` | 全局或活动级节律规则 | 专注分钟、休息分钟、启用、勿扰时间 |
| `settings` | 应用偏好 | 时区、窗口偏好、默认规则、数据路径等 JSON 值 |
| `schema_migrations` | 可重复数据库升级 | 版本与应用时间 |

所有用户可见时长都能从 `time_entries`、`entry_pauses`、`break_entries` 重新推导。统计缓存若以后加入，只能是可删除的派生数据，绝不作为事实来源。

数据库采用 SQLite，文件放在 macOS 应用数据目录，不放在项目目录。时间列存 UTC Unix 毫秒；应用启动时先执行版本化迁移，迁移失败绝不覆盖旧数据库。至少建立以下索引：`time_entries(started_at_utc)`、`time_entries(activity_id, started_at_utc)`、`break_entries(started_at_utc)`。数据库与 service 双重保证只能存在一个未结束的 `time_entry`。

## 6. 模块边界与依赖

### 原生层（Rust）

```text
commands/       # IPC 的输入校验与返回对象，不含领域计算
services/       # Timer、Reminder、Analytics、Recovery、Window
repositories/   # 唯一可写 SQL 的位置；跨表操作使用事务
domain/         # 状态、DTO、错误码、时间区间算法
db/             # 数据库打开、迁移、备份
events.rs       # 固定的跨窗口事件名和 payload
```

### 前端（React）

```text
windows/mini-timer/    # 单独入口；只含计时与切换活动
windows/main/          # 主窗口入口与四个页面路由
features/              # timer、activities、breaks、timeline、analytics、settings
lib/native-client/     # 唯一允许调用 Tauri invoke 的位置
lib/queries/           # TanStack Query 的查询 key、失效与 hooks
components/ui/         # shadcn/ui 引入的通用交互组件
```

### 允许的第一版依赖

| 用途 | 唯一选择 |
| --- | --- |
| 桌面壳与原生能力 | Tauri 2 + 官方需要的插件 |
| UI 交互 | shadcn/ui + Radix UI |
| 图标 | Lucide React |
| 前端临时状态 | Zustand（仅必要时） |
| 本地查询缓存 | TanStack Query |
| 图表 | ECharts，只在统计路由动态加载 |
| 前端日期显示 | date-fns |
| 输入校验 | Zod |

不引入 Electron、第二套 UI 框架、第二个图表库、第二个状态库、后台 Node 服务或网络 SDK。

## 7. IPC 契约与事件

写操作只通过命令完成。实际命令名可稍作命名调整，但语义不得改变：

```text
timer.getCurrent()             timer.start(activityId)
timer.pause()                  timer.resume()
timer.stop(note?)              timer.switchActivity(activityId)
timer.getTodaySummary()

activities.list(options)       activities.create(input)
activities.update(id, input)   activities.archive(id)

breaks.start()                 breaks.complete()
breaks.defer(minutes)          breaks.skip()

analytics.getSummary(range)    analytics.getBreakdown(range, filters)
analytics.getHourlyActivity(range)

settings.get()                 settings.update(input)
data.export(format, range?)    data.backup()
```

只允许事件：`timer:changed`、`activity:changed`、`settings:changed`。事件只在事实状态改变时发送；**禁止** `timer:tick`、秒级 IPC、秒级数据库写入和轮询数据库。

## 8. 轻量化硬约束

1. Rust 原生层是提醒与计时状态的唯一权威，隐藏的 WebView 不承担后台调度。
2. Mini Timer 仅在可见时每秒本地更新文字和圆环；一次更新最多影响两个时间文本与两个进度样式。
3. SQLite 只在状态变化、用户查询、迁移、导出时工作；不按秒／分钟写计时。
4. 提醒在状态变化时计算下一时刻并一次性调度；睡眠唤醒后重算且最多补发一次。
5. ECharts、统计查询、历史列表和备份界面必须懒加载，离开统计页后销毁图表实例。
6. 生产版本默认关闭高频日志，不存在遥测、同步、WebSocket 或后台网络请求。

性能目标是“长期开着没有可感知的 CPU、风扇和发热”，而非未测量的固定内存承诺。M0 和 M1 必须分别测量 Mini Timer 常驻、主窗口打开和统计页打开／关闭后的 CPU 与内存变化。

## 9. 实施顺序与完成条件

### M0：运行外壳（当前要做）

- 初始化 Tauri + React + TypeScript。
- 创建 `main`、`mini-timer` 和菜单栏；实现显示／隐藏／退出。
- 实现固定的静态双圆环样式，不接数据库、不接通知。
- 建立目录、格式化、类型检查和最小测试命令。

完成条件：能启动、Mini Timer 可置顶／拖动／隐藏／恢复，主窗口可打开；关闭主窗口不退出应用。

### M1：活动与计时事实

- 建库、迁移、活动 CRUD、当前计时状态机、今日小结。
- 实现开始／暂停／继续／结束／切换、启动恢复、跨午夜计算。
- 写原生层测试：唯一未结束记录、暂停扣除、切换事务、重启恢复。

完成条件：可连续使用一天；重启后不丢记录；任何界面操作结果一致。

### M2：休息与通知

- 接入规则、右环真实倒计时、勿扰时间、通知和休息记录。
- 验证最小化、隐藏、睡眠唤醒后的提醒与校正。

完成条件：计时运行期间可靠地在到点提醒；延后、跳过、开始／结束休息的记录均正确。

### M3：日常管理与统计

- 今天页、活动管理、时间线、手动补录／编辑、异常时段修正。
- 日／周／月统计、活跃时段、小时热力图、JSON／CSV 导出。

完成条件：能回答“时间投入到哪里”和“通常何时最活跃”，并能追溯到原始记录。

### M4：两周真实使用打磨

- 菜单栏快捷操作、窗口偏好、备份、无障碍、深色模式。
- 连续两周使用，记录所有误提醒、异常时段、资源问题并修正。

完成条件：无数据丢失、无持续资源异常，绝大多数日常操作不超过两步。

## 10. 必测场景

每个涉及时间的改动至少覆盖以下一项；发布前全部覆盖：

- 单一计时的开始、暂停、继续、结束和切换活动。
- 应用运行中、窗口隐藏后、主窗口关闭后、应用重启后的行为。
- 跨午夜、修改系统时区、夏令时边界（如适用）。
- 锁屏／睡眠后 30 分钟以上再唤醒。
- 到点提醒、延后、跳过、休息完成、勿扰时段。
- 手动补录、编辑和导出后，统计与原始记录一致。
- 浅色／深色、较小屏幕、仅键盘操作。

## 11. 开始编码前检查清单

- [x] 产品核心、双圆环和默认节律已确定。
- [x] 本地优先、无账号、无同步、无遥测已确定。
- [x] Tauri + React + SQLite 与依赖边界已确定。
- [x] 计时、提醒、统计和轻量化的权威规则已确定。
- [x] 初始化工程并创建 M0 的双窗口与菜单栏。
- [ ] 在目标 Mac 上记录 M0 的空闲 CPU／内存基线。

下一次开发从最后两项开始；无需再讨论架构后才能写第一行代码。
