import { useEffect, useState } from "react";
import {
  Archive,
  Download,
  Pause,
  Play,
  Plus,
  RotateCcw,
  Save,
  Trash2,
} from "lucide-react";
import { HourlyChart } from "./HourlyChart";
import {
  native,
  type Activity,
  type AnalyticsSummary,
  type Breakdown,
  type HourTotal,
  type Settings,
  type TimeEntry,
  type TimerState,
  type TodaySummary,
} from "../../lib/native-client/api";
import {
  formatDateTime,
  formatDuration,
  recentRange,
  todayRange,
} from "../../lib/time";

function Notice({ message }: { message: string }) {
  return message ? (
    <p className="notice" role="status">
      {message}
    </p>
  ) : null;
}
function ActionButton({
  children,
  onClick,
  quiet = false,
}: {
  children: React.ReactNode;
  onClick: () => void;
  quiet?: boolean;
}) {
  return (
    <button className={quiet ? "button quiet" : "button"} onClick={onClick}>
      {children}
    </button>
  );
}

export function TodayPage() {
  const [timer, setTimer] = useState<TimerState>();
  const [summary, setSummary] = useState<TodaySummary>();
  const [activities, setActivities] = useState<Activity[]>([]);
  const [entries, setEntries] = useState<TimeEntry[]>([]);
  const [message, setMessage] = useState("");
  const refresh = async () => {
    try {
      const range = todayRange();
      const [a, b, c, d] = await Promise.all([
        native.timer.current(),
        native.timer.today(),
        native.activities.list(),
        native.entries.list(range),
      ]);
      setTimer(a);
      setSummary(b);
      setActivities(c);
      setEntries(d);
    } catch (reason) {
      setMessage(String(reason));
    }
  };
  useEffect(() => {
    void refresh();
  }, []);
  const act = async (operation: () => Promise<unknown>) => {
    try {
      await operation();
      setMessage("");
      await refresh();
    } catch (reason) {
      setMessage(String(reason));
    }
  };
  const editEntry = (entryToEdit: TimeEntry) => {
    const start = window.prompt(
      "开始时间（例如 2026-08-18 09:00）",
      new Date(entryToEdit.startedAtUtc).toLocaleString("sv-SE").slice(0, 16),
    );
    const end = window.prompt(
      "结束时间（例如 2026-08-18 10:00）",
      new Date(entryToEdit.endedAtUtc ?? Date.now())
        .toLocaleString("sv-SE")
        .slice(0, 16),
    );
    if (!start || !end) return;
    void act(() =>
      native.entries.upsert({
        id: entryToEdit.id,
        activityId: entryToEdit.activityId,
        startedAtUtc: new Date(start).getTime(),
        endedAtUtc: new Date(end).getTime(),
        note: entryToEdit.note,
      }),
    );
  };
  const entry = timer?.entry;
  return (
    <section className="page">
      <div className="page-heading">
        <div>
          <p className="eyebrow">今天</p>
          <h1>工作节律</h1>
          <p>记录真实投入的每一段专注时间。</p>
        </div>
        <div className="today-total">
          <strong>{formatDuration(summary?.focusSeconds ?? 0)}</strong>
          <span>今日专注</span>
        </div>
      </div>
      <Notice message={message} />
      <div className="card timer-card">
        <div>
          <p className="muted">{entry?.activityName ?? "尚未开始"}</p>
          <h2>
            {entry
              ? entry.status === "paused"
                ? "已暂停"
                : "正在专注"
              : "选择一个活动开始"}
          </h2>
        </div>
        <div className="actions">
          {entry ? (
            <>
              <ActionButton
                onClick={() =>
                  void act(
                    entry.status === "paused"
                      ? native.timer.resume
                      : native.timer.pause,
                  )
                }
              >
                {entry.status === "paused" ? (
                  <Play size={15} />
                ) : (
                  <Pause size={15} />
                )}
                {entry.status === "paused" ? "继续" : "暂停"}
              </ActionButton>
              <ActionButton
                quiet
                onClick={() => void act(() => native.timer.stop())}
              >
                结束
              </ActionButton>
            </>
          ) : (
            <select
              defaultValue=""
              onChange={(event) =>
                event.target.value &&
                void act(() => native.timer.start(event.target.value))
              }
            >
              <option value="" disabled>
                开始活动…
              </option>
              {activities.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name}
                </option>
              ))}
            </select>
          )}
        </div>
      </div>
      {entry ? (
        <div className="switch-row">
          <span>切换活动</span>
          {activities
            .filter((item) => item.id !== entry.activityId)
            .map((item) => (
              <button
                key={item.id}
                onClick={() =>
                  void act(() => native.timer.switchActivity(item.id))
                }
              >
                {item.name}
              </button>
            ))}
        </div>
      ) : null}
      {Boolean(
        timer?.breakDue ||
        (!timer?.breakEntry &&
          timer?.nextBreakAtUtc &&
          timer.nextBreakAtUtc <= Date.now()),
      ) ? (
        <div className="card break-card">
          <div>
            <strong>该休息一下了</strong>
            <p>已完成一个专注周期。</p>
          </div>
          <div className="actions">
            <ActionButton onClick={() => void act(native.breaks.start)}>
              开始休息
            </ActionButton>
            <ActionButton
              quiet
              onClick={() => void act(() => native.breaks.defer(10))}
            >
              延后 10 分钟
            </ActionButton>
            <ActionButton quiet onClick={() => void act(native.breaks.skip)}>
              跳过
            </ActionButton>
          </div>
        </div>
      ) : null}
      <h2 className="section-title">今天的记录</h2>
      <Timeline
        entries={entries}
        onEdit={editEntry}
        onDelete={(id) => void act(() => native.entries.delete(id))}
      />
    </section>
  );
}

function Timeline({
  entries,
  onEdit,
  onDelete,
}: {
  entries: TimeEntry[];
  onEdit: (entry: TimeEntry) => void;
  onDelete: (id: string) => void;
}) {
  return (
    <div className="timeline">
      {entries.length === 0 ? (
        <p className="empty">今天还没有记录。</p>
      ) : (
        entries.map((entry) => (
          <div className="timeline-row" key={entry.id}>
            <i style={{ background: entry.activityColor ?? "#9899a4" }} />
            <div>
              <strong>{entry.activityName ?? "未归类"}</strong>
              <span>
                {formatDateTime(entry.startedAtUtc)} ·{" "}
                {formatDuration(entry.focusSeconds)}
              </span>
              {entry.note ? <small>{entry.note}</small> : null}
            </div>
            {entry.endedAtUtc ? (
              <>
                <button onClick={() => onEdit(entry)}>编辑</button>
                <button
                  aria-label="删除记录"
                  onClick={() => onDelete(entry.id)}
                >
                  <Trash2 size={15} />
                </button>
              </>
            ) : null}
          </div>
        ))
      )}
    </div>
  );
}

const colors = ["#716DE8", "#5DBB91", "#E49361", "#D272A8", "#4C9ACF"];
export function ActivitiesPage() {
  const [activities, setActivities] = useState<Activity[]>([]);
  const [name, setName] = useState("");
  const [color, setColor] = useState(colors[0]);
  const [message, setMessage] = useState("");
  const refresh = async () => {
    try {
      setActivities(await native.activities.list(true));
    } catch (reason) {
      setMessage(String(reason));
    }
  };
  useEffect(() => {
    void refresh();
  }, []);
  const add = async () => {
    try {
      await native.activities.create({ name, color });
      setName("");
      await refresh();
    } catch (reason) {
      setMessage(String(reason));
    }
  };
  return (
    <section className="page">
      <div className="page-heading">
        <div>
          <p className="eyebrow">活动</p>
          <h1>长期活动</h1>
          <p>用活动区分论文、写作、编码或任何长期投入。</p>
        </div>
      </div>
      <Notice message={message} />
      <form
        className="card activity-form"
        onSubmit={(event) => {
          event.preventDefault();
          void add();
        }}
      >
        <input
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder="新活动名称"
          maxLength={80}
          required
        />
        <input
          className="color-input"
          value={color}
          onChange={(event) => setColor(event.target.value)}
          aria-label="活动颜色"
        />
        <ActionButton onClick={() => void add()}>
          <Plus size={15} />
          添加活动
        </ActionButton>
      </form>
      <div className="activity-list">
        {activities.map((activity) => (
          <article className="activity-row" key={activity.id}>
            <i style={{ background: activity.color }} />
            <div>
              <strong>{activity.name}</strong>
              <span>{activity.isArchived ? "已归档" : "可用于开始计时"}</span>
            </div>
            {!activity.isArchived ? (
              <>
                <button
                  onClick={() => {
                    const next = window.prompt("修改活动名称", activity.name);
                    if (next)
                      void native.activities
                        .update(activity.id, {
                          name: next,
                          color: activity.color,
                        })
                        .then(refresh);
                  }}
                >
                  编辑
                </button>
                <button
                  className="icon-button"
                  aria-label="归档活动"
                  onClick={() =>
                    void native.activities.archive(activity.id).then(refresh)
                  }
                >
                  <Archive size={16} />
                </button>
              </>
            ) : null}
          </article>
        ))}
      </div>
    </section>
  );
}

export function AnalyticsPage() {
  const [summary, setSummary] = useState<AnalyticsSummary>();
  const [breakdown, setBreakdown] = useState<Breakdown[]>([]);
  const [hourly, setHourly] = useState<HourTotal[]>([]);
  const [message, setMessage] = useState("");
  useEffect(() => {
    const range = recentRange();
    Promise.all([
      native.analytics.summary(range),
      native.analytics.breakdown(range),
      native.analytics.hourly(range),
    ])
      .then(([a, b, c]) => {
        setSummary(a);
        setBreakdown(b);
        setHourly(c);
      })
      .catch((reason) => setMessage(String(reason)));
  }, []);
  return (
    <section className="page">
      <div className="page-heading">
        <div>
          <p className="eyebrow">统计</p>
          <h1>最近 28 天</h1>
          <p>从真实时间记录中汇总，无预置数据。</p>
        </div>
      </div>
      <Notice message={message} />
      <div className="stat-grid">
        <div className="card stat">
          <span>专注时长</span>
          <strong>{formatDuration(summary?.totalFocusSeconds ?? 0)}</strong>
        </div>
        <div className="card stat">
          <span>休息时长</span>
          <strong>{formatDuration(summary?.totalBreakSeconds ?? 0)}</strong>
        </div>
        <div className="card stat">
          <span>主要活跃时段</span>
          <strong>
            {summary?.primaryActiveHour === undefined
              ? "—"
              : `${summary.primaryActiveHour}:00`}
          </strong>
        </div>
      </div>
      <div className="analytics-grid">
        <div className="card">
          <h2>小时活跃度</h2>
          <HourlyChart values={hourly} />
        </div>
        <div className="card">
          <h2>投入到哪里</h2>
          {breakdown.length ? (
            <div className="breakdown">
              {breakdown.map((item) => (
                <div key={item.activityId ?? item.name}>
                  <span>
                    <i style={{ background: item.color }} />
                    {item.name}
                  </span>
                  <strong>{formatDuration(item.focusSeconds)}</strong>
                </div>
              ))}
            </div>
          ) : (
            <p className="empty">有记录后将在这里展示。</p>
          )}
        </div>
      </div>
    </section>
  );
}

export function SettingsPage() {
  const [settings, setSettings] = useState<Settings>();
  const [message, setMessage] = useState("");
  const range = recentRange();
  useEffect(() => {
    native.settings
      .get()
      .then(setSettings)
      .catch((reason) => setMessage(String(reason)));
  }, []);
  const save = async () => {
    if (!settings) return;
    try {
      setSettings(await native.settings.update(settings));
      setMessage("设置已保存");
    } catch (reason) {
      setMessage(String(reason));
    }
  };
  const exportFile = async (format: "json" | "csv") => {
    try {
      const result = await native.data.export(format, range);
      setMessage(`已导出至 ${result.path}`);
    } catch (reason) {
      setMessage(String(reason));
    }
  };
  return (
    <section className="page">
      <div className="page-heading">
        <div>
          <p className="eyebrow">设置</p>
          <h1>本地偏好</h1>
          <p>所有数据只保存在这台 Mac 上。</p>
        </div>
      </div>
      <Notice message={message} />
      {settings ? (
        <div className="settings-form card">
          <label>
            时区
            <input
              value={settings.timezone}
              onChange={(event) =>
                setSettings({ ...settings, timezone: event.target.value })
              }
            />
          </label>
          <div className="two-fields">
            <label>
              专注分钟
              <input
                type="number"
                min="1"
                max="240"
                value={settings.focusMinutes}
                onChange={(event) =>
                  setSettings({
                    ...settings,
                    focusMinutes: Number(event.target.value),
                  })
                }
              />
            </label>
            <label>
              休息分钟
              <input
                type="number"
                min="1"
                max="120"
                value={settings.breakMinutes}
                onChange={(event) =>
                  setSettings({
                    ...settings,
                    breakMinutes: Number(event.target.value),
                  })
                }
              />
            </label>
          </div>
          <label className="check">
            <input
              type="checkbox"
              checked={settings.remindersEnabled}
              onChange={(event) =>
                setSettings({
                  ...settings,
                  remindersEnabled: event.target.checked,
                })
              }
            />
            启用休息提醒
          </label>
          <div className="two-fields">
            <label>
              勿扰开始
              <input
                type="time"
                value={settings.doNotDisturbStart ?? ""}
                onChange={(event) =>
                  setSettings({
                    ...settings,
                    doNotDisturbStart: event.target.value || undefined,
                  })
                }
              />
            </label>
            <label>
              勿扰结束
              <input
                type="time"
                value={settings.doNotDisturbEnd ?? ""}
                onChange={(event) =>
                  setSettings({
                    ...settings,
                    doNotDisturbEnd: event.target.value || undefined,
                  })
                }
              />
            </label>
          </div>
          <ActionButton onClick={() => void save()}>
            <Save size={15} />
            保存设置
          </ActionButton>
        </div>
      ) : null}
      <div className="card data-actions">
        <div>
          <h2>数据导出与备份</h2>
          <p>导出最近 28 天的原始时间记录，或制作完整 SQLite 备份。</p>
        </div>
        <div className="actions">
          <ActionButton quiet onClick={() => void exportFile("csv")}>
            <Download size={15} />
            CSV
          </ActionButton>
          <ActionButton quiet onClick={() => void exportFile("json")}>
            <Download size={15} />
            JSON
          </ActionButton>
          <ActionButton
            quiet
            onClick={() =>
              void native.data
                .backup()
                .then((result) => setMessage(`备份已保存至 ${result.path}`))
            }
          >
            <RotateCcw size={15} />
            备份
          </ActionButton>
        </div>
      </div>
      <ManualEntry onSaved={() => setMessage("补录已保存；统计将自动重算。")} />
    </section>
  );
}

function ManualEntry({ onSaved }: { onSaved: () => void }) {
  const [activities, setActivities] = useState<Activity[]>([]);
  const [activityId, setActivityId] = useState("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [message, setMessage] = useState("");
  useEffect(() => {
    native.activities.list().then(setActivities);
  }, []);
  const save = async () => {
    try {
      await native.entries.upsert({
        activityId: activityId || undefined,
        startedAtUtc: new Date(start).getTime(),
        endedAtUtc: new Date(end).getTime(),
      });
      onSaved();
      setMessage("已补录");
    } catch (reason) {
      setMessage(String(reason));
    }
  };
  return (
    <div className="card manual-entry">
      <h2>手动补录</h2>
      <p>补录会直接进入统计与导出数据。</p>
      <div className="two-fields">
        <select
          value={activityId}
          onChange={(event) => setActivityId(event.target.value)}
        >
          <option value="">未归类</option>
          {activities.map((item) => (
            <option key={item.id} value={item.id}>
              {item.name}
            </option>
          ))}
        </select>
        <input
          type="datetime-local"
          value={start}
          onChange={(event) => setStart(event.target.value)}
        />
        <input
          type="datetime-local"
          value={end}
          onChange={(event) => setEnd(event.target.value)}
        />
      </div>
      <ActionButton onClick={() => void save()}>保存补录</ActionButton>
      <Notice message={message} />
    </div>
  );
}
