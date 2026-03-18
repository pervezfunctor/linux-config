#!/usr/bin/env bun

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { createInterface } from "node:readline/promises";

type LogLevel = "all" | "info" | "error" | "warning" | "warn" | "debug" | "trace";

interface LogEntry {
  name: string;
  size: number;
  modified: Date;
}

interface ShowOptions {
  dir?: string;
  timestamp?: string;
  select: boolean;
  pickLog: boolean;
  level: string;
  pattern: string;
}

interface CleanOptions {
  dir?: string;
}

interface ParsedArgs {
  command: "show" | "clean" | "help";
  show: ShowOptions;
  clean: CleanOptions;
}

const DEFAULT_LOG_DIR = path.join(os.homedir(), ".linux-config-logs");
const VALID_LEVELS: readonly LogLevel[] = ["all", "info", "error", "warning", "warn", "debug", "trace"];

class ViewLogsError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ViewLogsError";
  }
}

function expandPath(p: string): string {
  if (p === "~") return os.homedir();
  if (p.startsWith("~/")) return path.join(os.homedir(), p.slice(2));
  return path.resolve(p);
}

function hasCmd(cmd: string): boolean {
  return (spawnSync("which", [cmd], { stdio: "ignore" }).status ?? 1) === 0;
}

function getLogDir(dir?: string): string {
  return dir ?? process.env.LINUX_CONFIG_LOG_DIR ?? DEFAULT_LOG_DIR;
}

function loadLogs(dir: string): LogEntry[] {
  const logDir = expandPath(dir);
  if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
  }

  const logs = fs
    .readdirSync(logDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".log"))
    .map((entry) => {
      const filePath = path.join(logDir, entry.name);
      const stat = fs.statSync(filePath);
      return { name: filePath, size: stat.size, modified: stat.mtime } satisfies LogEntry;
    })
    .sort((a, b) => b.modified.getTime() - a.modified.getTime());

  if (logs.length === 0) {
    console.error(`No log files found in ${logDir}`);
    console.error("Run bootstrap or specify a different directory with --dir or LINUX_CONFIG_LOG_DIR.");
    throw new ViewLogsError("No logs found");
  }

  return logs;
}

function normalizePattern(pattern: string): { source: string; flags: string } {
  if (pattern.startsWith("(?i)")) {
    return { source: pattern.slice(4), flags: "i" };
  }
  return { source: pattern, flags: "" };
}

function compilePattern(pattern: string): RegExp | null {
  if (pattern === "" || pattern === ".*") return null;
  const normalized = normalizePattern(pattern);
  try {
    return new RegExp(normalized.source, normalized.flags);
  } catch {
    throw new ViewLogsError(`Invalid regex pattern: ${pattern}`);
  }
}

function filterLogContent(content: string, level: string, pattern: string): string {
  const levelFiltered = level === "all"
    ? content
    : content
      .split(/\r?\n/)
      .filter((line) => line.toUpperCase().includes(`[${level.toUpperCase()}]`))
      .join("\n");

  const regex = compilePattern(pattern);
  if (!regex) return levelFiltered;
  return levelFiltered
    .split(/\r?\n/)
    .filter((line) => regex.test(line))
    .join("\n");
}

function displayLog(filePath: string, level: string, pattern: string): void {
  const fileName = path.basename(filePath);
  console.log(`==== ${fileName} ====`);

  const content = fs.readFileSync(filePath, "utf8");
  const filtered = filterLogContent(content, level, pattern);

  if (filtered.length === 0) {
    const levelMsg = level === "all" ? "" : ` level='${level}'`;
    const patternMsg = pattern === "" || pattern === ".*" ? "" : ` pattern='${pattern}'`;
    console.log(`No lines found matching filters:${levelMsg}${patternMsg}`);
    console.log("Try: --level all --pattern '.*' to show all lines");
    return;
  }

  if (!hasCmd("less") || !process.stdout.isTTY) {
    console.log(filtered);
    return;
  }

  spawnSync("less", ["-R"], {
    input: filtered,
    encoding: "utf8",
    stdio: ["pipe", "inherit", "inherit"],
  });
}

function findLogByTimestamp(logs: readonly LogEntry[], timestamp: string): LogEntry | null {
  const matched = logs.find((entry) => path.basename(entry.name).includes(timestamp));
  if (!matched) {
    console.error(`No log found matching timestamp: ${timestamp}`);
    return null;
  }
  return matched;
}

async function selectInteractively(logs: readonly LogEntry[]): Promise<LogEntry | null> {
  console.log("Available log files:");
  for (const [index, entry] of logs.entries()) {
    const label = String(index + 1).padEnd(2, " ");
    console.log(`  ${label}) ${path.basename(entry.name)}`);
  }

  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    const choice = (await rl.question("Select log by number or timestamp (default=1): ")).trim();
    if (choice.length === 0) return logs[0] ?? null;
    if (/^[0-9]+$/.test(choice)) {
      const selection = Number(choice) - 1;
      if (selection < 0 || selection >= logs.length) {
        console.error(`Invalid selection: ${choice}`);
        return null;
      }
      return logs[selection] ?? null;
    }
    return findLogByTimestamp(logs, choice);
  } finally {
    rl.close();
  }
}

function formatDate(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

async function pickLogWithGum(logs: readonly LogEntry[]): Promise<LogEntry | null> {
  if (!hasCmd("gum")) {
    console.error("gum is not installed. Falling back to --select behavior.");
    return selectInteractively(logs);
  }

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "view-logs-gum-"));
  const choicesFile = path.join(tempDir, "choices.txt");
  const outputFile = path.join(tempDir, "selection.txt");
  try {
    const choices = logs.map((log) => `${path.basename(log.name)}\t${formatDate(log.modified)}\t${String(log.size)}`);
    fs.writeFileSync(choicesFile, `${choices.join("\n")}\n`, "utf8");

    const shellCmd = `gum choose --header 'Select a log file:' < '${choicesFile}' > '${outputFile}'`;
    const result = spawnSync("sh", ["-c", shellCmd], { stdio: ["inherit", "inherit", "inherit"] });
    if ((result.status ?? 1) !== 0) return null;

    const selected = fs.existsSync(outputFile) ? fs.readFileSync(outputFile, "utf8").trim() : "";
    if (selected.length === 0) return null;

    const selectedName = selected.split("\t")[0] ?? "";
    return logs.find((entry) => path.basename(entry.name) === selectedName) ?? null;
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function cleanLogs(dir?: string): void {
  const logDir = getLogDir(dir);
  let logs: LogEntry[];
  try {
    logs = loadLogs(logDir);
  } catch (error) {
    if (error instanceof ViewLogsError) return;
    throw error;
  }

  const keepFile = logs[0];
  if (!keepFile) return;
  if (logs.length <= 1) {
    console.log(`Only one log present (${path.basename(keepFile.name)}); nothing to clean.`);
    return;
  }

  const toRemove = logs.slice(1);
  for (const log of toRemove) {
    fs.rmSync(log.name, { force: true });
  }
  console.log(`Kept ${path.basename(keepFile.name)}; removed ${toRemove.length} older log(s).`);
}

async function showLogs(opts: ShowOptions): Promise<void> {
  const level = opts.level.toLowerCase();
  if (!VALID_LEVELS.includes(level as LogLevel)) {
    console.error(`Invalid level: ${opts.level}. Valid levels are: ${VALID_LEVELS.join(", ")}`);
    return;
  }

  const logDir = getLogDir(opts.dir);
  let logs: LogEntry[];
  try {
    logs = loadLogs(logDir);
  } catch (error) {
    if (error instanceof ViewLogsError) return;
    throw error;
  }

  const target = opts.pickLog
    ? await pickLogWithGum(logs)
    : opts.select
      ? await selectInteractively(logs)
      : opts.timestamp
        ? findLogByTimestamp(logs, opts.timestamp)
        : logs[0] ?? null;

  if (target) displayLog(target.name, level, opts.pattern);
}

function printShowHelp(): void {
  console.log("Show options:");
  console.log("  -t, --timestamp <stamp>  Display the log matching the timestamp (MM-DD-HHMMSS, e.g. 03-03-012721).");
  console.log("  -s, --select             Interactively choose a log by timestamp or index (text-based).");
  console.log("  -g, --pick-log           Interactively pick a log using gum (requires gum installed).");
  console.log("  -l, --level <level>      Filter by log level: all, info, error, warning, warn, debug, trace. (default: all)");
  console.log("  -p, --pattern <regex>    Filter lines by regex pattern. (default: .*)");
}

function printHelp(): void {
  console.log("linux-config-logs - Inspect bootstrap logs");
  console.log("");
  console.log("Usage:");
  console.log("  linux-config-logs show [--dir <path>] [options]");
  console.log("  linux-config-logs clean [--dir <path>]");
  console.log("  linux-config-logs help");
  console.log("");
  console.log("Commands:");
  console.log("  clean             Remove all log files except the most recent one.");
  console.log("  show [options]    Display log contents. Defaults to the most recent log.");
  console.log("");
  printShowHelp();
  console.log("");
  console.log(`By default logs are read from ${getLogDir()}.`);
  console.log("Override with the LINUX_CONFIG_LOG_DIR environment variable or the --dir flag.");
}

function requireValue(args: string[], index: number, flag: string): string {
  const value = args[index + 1];
  if (!value || value.startsWith("-")) {
    throw new ViewLogsError(`Missing value for ${flag}`);
  }
  return value;
}

function parseArgs(argv: string[]): ParsedArgs {
  const commandArg = argv[0];
  const command = !commandArg || commandArg === "help" || commandArg === "--help" || commandArg === "-h"
    ? "help"
    : commandArg === "show" || commandArg === "clean"
      ? commandArg
      : (() => { throw new ViewLogsError(`Unknown command: ${commandArg}`); })();

  const parsed: ParsedArgs = {
    command,
    show: { dir: undefined, timestamp: undefined, select: false, pickLog: false, level: "all", pattern: ".*" },
    clean: { dir: undefined },
  };

  const args = argv.slice(command === "help" ? 0 : 1);
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    switch (arg) {
      case "help":
      case "--help":
      case "-h":
        parsed.command = "help";
        break;
      case "--dir": {
        const value = requireValue(args, i, arg);
        parsed.show.dir = value;
        parsed.clean.dir = value;
        i++;
        break;
      }
      case "--timestamp":
      case "-t":
        parsed.show.timestamp = requireValue(args, i, arg);
        i++;
        break;
      case "--select":
      case "-s":
        parsed.show.select = true;
        break;
      case "--pick-log":
      case "-g":
        parsed.show.pickLog = true;
        break;
      case "--level":
      case "-l":
        parsed.show.level = requireValue(args, i, arg);
        i++;
        break;
      case "--pattern":
      case "-p":
        parsed.show.pattern = requireValue(args, i, arg);
        i++;
        break;
      default:
        throw new ViewLogsError(`Unknown argument: ${arg}`);
    }
  }

  return parsed;
}

async function main(): Promise<number> {
  try {
    const parsed = parseArgs(process.argv.slice(2));
    switch (parsed.command) {
      case "show":
        await showLogs(parsed.show);
        return 0;
      case "clean":
        cleanLogs(parsed.clean.dir);
        return 0;
      case "help":
        printHelp();
        return 0;
    }
  } catch (error) {
    console.error((error as Error).message);
    printHelp();
    return 1;
  }
}

export {
  DEFAULT_LOG_DIR,
  VALID_LEVELS,
  ViewLogsError,
  expandPath,
  getLogDir,
  loadLogs,
  normalizePattern,
  filterLogContent,
  findLogByTimestamp,
  cleanLogs,
  parseArgs,
  showLogs,
  main,
};
export type { LogEntry, LogLevel, ShowOptions, CleanOptions, ParsedArgs };

if (import.meta.main) {
  main().then((code) => process.exit(code));
}
