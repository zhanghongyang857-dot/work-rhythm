import {
  hideCurrentWindow,
  minimizeCurrentWindow,
} from "../../lib/native-client/window";

type WindowControlsProps = {
  showMinimize?: boolean;
};

export function WindowControls({ showMinimize = false }: WindowControlsProps) {
  return (
    <div className="window-controls" aria-label="窗口控制">
      {showMinimize ? (
        <button
          aria-label="最小化"
          className="window-control minimize"
          onClick={() => void minimizeCurrentWindow()}
        />
      ) : null}
      <button
        aria-label="隐藏窗口"
        className="window-control close"
        onClick={() => void hideCurrentWindow()}
      />
    </div>
  );
}
