type ProgressRingProps = {
  accent: "focus" | "break";
  label: string;
  value: string;
  progress: number;
  detail: string;
};

const RADIUS = 74;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

export function ProgressRing({
  accent,
  label,
  value,
  progress,
  detail,
}: ProgressRingProps) {
  const dashOffset = CIRCUMFERENCE * (1 - progress);

  return (
    <section
      className={`progress-ring ${accent}`}
      aria-label={`${label} ${value}`}
    >
      <svg aria-hidden="true" viewBox="0 0 180 180">
        <circle className="ring-track" cx="90" cy="90" r={RADIUS} />
        <circle
          className="ring-value"
          cx="90"
          cy="90"
          r={RADIUS}
          strokeDasharray={CIRCUMFERENCE}
          strokeDashoffset={dashOffset}
        />
      </svg>
      <div className="ring-content">
        <span className="ring-label">{label}</span>
        <strong>{value}</strong>
        <span className="ring-detail">{detail}</span>
      </div>
    </section>
  );
}
