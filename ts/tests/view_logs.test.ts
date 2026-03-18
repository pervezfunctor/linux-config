#!/usr/bin/env bun

import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  ViewLogsError,
  cleanLogs,
  filterLogContent,
  findLogByTimestamp,
  loadLogs,
  parseArgs,
} from "../src/view_logs.ts";

const TEST_BASE = fs.mkdtempSync(path.join(os.tmpdir(), "view-logs-test-"));

function writeLog(dir: string, name: string, content: string, modifiedMs: number): string {
  const filePath = path.join(dir, name);
  fs.writeFileSync(filePath, content, "utf8");
  const when = new Date(modifiedMs);
  fs.utimesSync(filePath, when, when);
  return filePath;
}

beforeAll(() => {
  fs.mkdirSync(TEST_BASE, { recursive: true });
});

afterAll(() => {
  fs.rmSync(TEST_BASE, { recursive: true, force: true });
});

describe("loadLogs", () => {
  it("sorts log files by modified time descending", () => {
    const dir = path.join(TEST_BASE, "load-sorts");
    fs.mkdirSync(dir, { recursive: true });
    writeLog(dir, "bootstrap-03-03-000001.log", "old", 1_700_000_000_000);
    writeLog(dir, "bootstrap-03-03-000002.log", "new", 1_700_000_100_000);

    const logs = loadLogs(dir);
    expect(path.basename(logs[0]?.name ?? "")).toBe("bootstrap-03-03-000002.log");
    expect(path.basename(logs[1]?.name ?? "")).toBe("bootstrap-03-03-000001.log");
  });

  it("throws when no logs are present", () => {
    const dir = path.join(TEST_BASE, "load-empty");
    fs.mkdirSync(dir, { recursive: true });
    expect(() => loadLogs(dir)).toThrow(ViewLogsError);
  });
});

describe("filterLogContent", () => {
  const content = [
    "03-03 10:00:00 [INFO] install package",
    "03-03 10:00:01 [ERROR] failed badly",
    "03-03 10:00:02 [WARN] recoverable issue",
  ].join("\n");

  it("filters by level", () => {
    expect(filterLogContent(content, "error", ".*")).toBe("03-03 10:00:01 [ERROR] failed badly");
  });

  it("supports nushell-style leading (?i) regex", () => {
    expect(filterLogContent(content, "all", "(?i)FAILED|ISSUE")).toContain("[ERROR] failed badly");
    expect(filterLogContent(content, "all", "(?i)FAILED|ISSUE")).toContain("[WARN] recoverable issue");
  });
});

describe("findLogByTimestamp", () => {
  it("matches a basename substring", () => {
    const logs = [
      { name: "/tmp/bootstrap-03-03-012721.log", size: 1, modified: new Date(1) },
      { name: "/tmp/bootstrap-03-04-012721.log", size: 1, modified: new Date(2) },
    ];
    expect(path.basename(findLogByTimestamp(logs, "03-03-012721")?.name ?? "")).toBe("bootstrap-03-03-012721.log");
  });
});

describe("cleanLogs", () => {
  it("keeps only the newest log", () => {
    const dir = path.join(TEST_BASE, "clean");
    fs.mkdirSync(dir, { recursive: true });
    writeLog(dir, "bootstrap-03-03-000001.log", "old", 1_700_000_000_000);
    writeLog(dir, "bootstrap-03-03-000002.log", "new", 1_700_000_100_000);
    writeLog(dir, "bootstrap-03-03-000003.log", "newest", 1_700_000_200_000);

    cleanLogs(dir);

    const remaining = fs.readdirSync(dir).sort();
    expect(remaining).toEqual(["bootstrap-03-03-000003.log"]);
  });
});

describe("parseArgs", () => {
  it("parses show flags including short aliases", () => {
    const parsed = parseArgs(["show", "--dir", "/tmp/logs", "-t", "03-03", "-s", "-l", "info", "-p", "install"]);
    expect(parsed.command).toBe("show");
    expect(parsed.show.dir).toBe("/tmp/logs");
    expect(parsed.show.timestamp).toBe("03-03");
    expect(parsed.show.select).toBe(true);
    expect(parsed.show.level).toBe("info");
    expect(parsed.show.pattern).toBe("install");
  });

  it("parses clean with dir", () => {
    const parsed = parseArgs(["clean", "--dir", "/tmp/logs"]);
    expect(parsed.command).toBe("clean");
    expect(parsed.clean.dir).toBe("/tmp/logs");
  });
});