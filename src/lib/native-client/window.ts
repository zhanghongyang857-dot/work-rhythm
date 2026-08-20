import { getCurrentWindow } from "@tauri-apps/api/window";

const currentWindow = getCurrentWindow();

export async function hideCurrentWindow() {
  await currentWindow.hide();
}

export async function minimizeCurrentWindow() {
  await currentWindow.minimize();
}

export async function hideMainWindowOnClose() {
  const label = currentWindow.label;
  if (label !== "main") return;

  await currentWindow.onCloseRequested((event) => {
    event.preventDefault();
    void currentWindow.hide();
  });
}
