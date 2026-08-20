import { useEffect, useState } from "react";
import { WindowControls } from "../../components/ui/WindowControls";
import { hideMainWindowOnClose } from "../../lib/native-client/window";
import {
  ActivitiesPage,
  AnalyticsPage,
  SettingsPage,
  TodayPage,
} from "./Pages";

const pages = ["今天", "活动", "统计", "设置"] as const;
type Page = (typeof pages)[number];

export function MainWindow() {
  const [page, setPage] = useState<Page>("今天");

  useEffect(() => {
    void hideMainWindowOnClose();
  }, []);

  const content = {
    今天: <TodayPage />,
    活动: <ActivitiesPage />,
    统计: <AnalyticsPage />,
    设置: <SettingsPage />,
  }[page];

  return (
    <main className="main-window-shell">
      <header className="main-titlebar" data-tauri-drag-region>
        <div data-tauri-drag-region>
          <span className="wordmark">WORK RHYTHM</span>
          <span className="title-separator">/</span>
          <span>{page}</span>
        </div>
        <WindowControls showMinimize />
      </header>
      <div className="main-layout">
        <nav aria-label="主要导航">
          {pages.map((item) => (
            <button
              className={item === page ? "active" : ""}
              key={item}
              onClick={() => setPage(item)}
            >
              {item}
            </button>
          ))}
        </nav>
        <section className="main-content">{content}</section>
      </div>
    </main>
  );
}
