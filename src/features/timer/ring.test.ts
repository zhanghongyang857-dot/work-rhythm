import { describe, expect, it } from "vitest";
import { formatDuration, ringProgress } from "./ring";

describe("ringProgress", () => {
  it("bounds progress to a complete ring", () => {
    expect(ringProgress(3600, 1800)).toBe(0);
    expect(ringProgress(-1, 1800)).toBe(1);
  });

  it("calculates progress from remaining time", () => {
    expect(ringProgress(900, 1800)).toBe(0.5);
  });
});

describe("formatDuration", () => {
  it("uses an hour format only when needed", () => {
    expect(formatDuration(65)).toBe("1:05");
    expect(formatDuration(3661)).toBe("1:01:01");
  });
});
