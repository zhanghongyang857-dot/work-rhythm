import { useEffect, useRef } from "react";
import type { ECharts } from "echarts";
import type { HourTotal } from "../../lib/native-client/api";

export function HourlyChart({ values }: { values: HourTotal[] }) {
  const element = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let chart: ECharts | undefined;
    const draw = async () => {
      if (!element.current) return;
      const echarts = await import("echarts");
      chart = echarts.init(element.current);
      chart.setOption({
        animation: false,
        grid: { left: 8, right: 8, top: 8, bottom: 20 },
        xAxis: {
          type: "category",
          data: values.map((item) => `${item.hour}`),
          axisLine: { show: false },
          axisTick: { show: false },
          axisLabel: { color: "#8d8e98", fontSize: 10 },
        },
        yAxis: { type: "value", show: false },
        series: [
          {
            type: "bar",
            data: values.map((item) => item.focusSeconds / 3600),
            itemStyle: { color: "#716de8", borderRadius: [3, 3, 0, 0] },
            barMaxWidth: 14,
          },
        ],
      });
      const observer = new ResizeObserver(() => chart?.resize());
      observer.observe(element.current);
      return () => observer.disconnect();
    };
    let cleanup: (() => void) | undefined;
    void draw().then((dispose) => {
      cleanup = dispose;
    });
    return () => {
      cleanup?.();
      chart?.dispose();
    };
  }, [values]);
  return (
    <div
      className="hourly-chart"
      ref={element}
      aria-label="最近 28 天每小时专注时长图表"
    />
  );
}
