#!/usr/bin/env bun

/**
 * stow.ts — Dotfiles manager (Bun/TypeScript port of nu/stow.nu)
 *
 * Usage:
 *   stow.ts add    <package> <path>    [--target <dir>] [--source-dir <dir>]
 *   stow.ts apply  <package>           [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
 *   stow.ts remove <package>           [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
 *   stow.ts status <package>           [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
 *   stow.ts doctor <package>           [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
 *   stow.ts restore <package>          [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

const color = (code: number) => (s: string) => `\x1b[${code}m${s}\x1b[0m`;
const c = {
  green: color(32),
  yellow: color(33),
  red: color(31),
  cyan: color(36),
};

const log = {
  info: (msg: string) => console.log(c.green("[INFO]") + " " + msg),
  warn: (msg: string) => console.warn(c.yellow("[WARN]") + " " + msg),
  error: (msg: string) => console.error(c.red("[ERROR]") + " " + msg),
};

/** Thrown by command functions for expected failures (bad args, missing pkg, etc). */
class StowError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = "StowError";
  }
}

function fail(msg: string): never {
  throw new StowError(msg);
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Dirs {
  target: string;
  source: string;
  backup: string;
}

type PathType = "file" | "dir" | "symlink" | "none";

type TargetState = "managed" | "missing" | "file" | "directory" | "foreign-symlink";
type BackupStatus = "found" | "missing" | "invalid";

interface StowFile {
  stow: string;
  target: string;
}

interface BackupCandidate {
  path: string;
  timestamp: string;
  sequence: number;
}

interface BackupLookupResult {
  status: BackupStatus;
  path: string | null;
}

interface StatusRecord {
  target: string;
  stow: string;
  state: TargetState;
  link_target: string;
  backup_status: BackupStatus;
  backup_path: string;
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

const HOME = os.homedir();
const DEFAULT_SOURCE = path.join(HOME, ".local", "share", "linux-config");
const DEFAULT_BACKUP = path.join(HOME, ".stow-backups");

function resolveDirs(
  target: string | undefined,
  sourceDir: string | undefined,
  backupDir: string | undefined,
): Dirs {
  return {
    target: target || HOME,
    source: sourceDir || DEFAULT_SOURCE,
    backup: backupDir || DEFAULT_BACKUP,
  };
}

/** Convert a leading-dot segment to `dot-` prefix. */
function toStowName(name: string): string {
  return name.startsWith(".") ? `dot-${name.slice(1)}` : name;
}

/** Convert a `dot-` prefixed segment back to a leading-dot name. */
function fromStowName(name: string): string {
  return name.startsWith("dot-") ? `.${name.slice(4)}` : name;
}

/** Resolve and expand a path (handles relative paths by resolving from cwd). */
function expand(p: string): string {
  return path.resolve(p);
}

/** Return the filesystem type of a path without throwing. */
function pathType(p: string): PathType {
  try {
    const stat = fs.lstatSync(p);
    if (stat.isSymbolicLink()) return "symlink";
    if (stat.isDirectory()) return "dir";
    if (stat.isFile()) return "file";
    return "none";
  } catch {
    return "none";
  }
}

/** Read the symlink target without throwing; returns "" on failure. */
function readlinkTarget(p: string): string {
  try {
    return fs.readlinkSync(p);
  } catch {
    return "";
  }
}

/** Ensure a directory exists for the parent of `p`. */
function ensureParentDir(p: string): void {
  const parent = path.dirname(p);
  fs.mkdirSync(parent, { recursive: true });
}

// ---------------------------------------------------------------------------
// Stow path computation
// ---------------------------------------------------------------------------

/**
 * Compute the staged destination inside the stow package for a given real file.
 * Transforms `.` segments to `dot-` so they can be globbed safely.
 */
function computeStowPath(
  filePath: string,
  target: string,
  sourceDir: string,
  pkg: string,
): string {
  const relPath = path.relative(target, filePath);
  if (relPath.startsWith("..")) {
    throw new Error(`Path ${filePath} is outside the target directory ${target}`);
  }
  const segments = relPath.split(path.sep).map(toStowName);
  return path.join(sourceDir, pkg, ...segments);
}

/**
 * Compute the final symlink destination for a given stow-package file in the
 * target directory, translating `dot-` segments back to `.`.
 */
function computeTargetLink(
  absTarget: string,
  absStowPkg: string,
  stowFile: string,
): string {
  const relPath = path.relative(absStowPkg, stowFile);
  const segments = relPath.split(path.sep).map(fromStowName);
  return path.join(absTarget, ...segments);
}

// ---------------------------------------------------------------------------
// File collection
// ---------------------------------------------------------------------------

/** Recursively collect all non-directory files under `dir`. */
function findFiles(dir: string): string[] {
  const results: string[] = [];
  function walk(current: string): void {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else {
        results.push(full);
      }
    }
  }
  walk(dir);
  return results;
}

/**
 * Crawl a stow package directory and return `{ stow, target }` pairs for
 * every staged file, translating `dot-` names back to `.` in the target path.
 */
function collectStowFiles(absStowPkg: string, absTarget: string): StowFile[] {
  return findFiles(absStowPkg).map((stow) => ({
    stow,
    target: computeTargetLink(absTarget, absStowPkg, stow),
  }));
}

// ---------------------------------------------------------------------------
// Backup directory computation
// ---------------------------------------------------------------------------

/**
 * Derive the package-specific backup scope directory from the absolute target
 * root. Uses `_root_` for the filesystem root so the same package name can be
 * used across target directories.
 */
function backupScopeDir(backupDir: string, pkg: string, absTarget: string): string {
  const expanded = expand(absTarget);
  const segments = expanded.split(path.sep).map((seg) => {
    if (seg === "" || seg === "/") return "_root_";
    return toStowName(seg);
  });
  // On POSIX the first element after split("/abs/path") is "" → _root_
  return path.join(backupDir, pkg, ...segments);
}

/** Find a collision-free backup path, appending `-N` as needed. */
function uniqueBackupPath(pkgBackupDir: string, relPath: string, timestamp: string): string {
  const base = path.join(pkgBackupDir, `${relPath}-${timestamp}`);
  if (!fs.existsSync(base)) return base;

  let seq = 1;
  while (true) {
    const candidate = path.join(pkgBackupDir, `${relPath}-${timestamp}-${seq}`);
    if (!fs.existsSync(candidate)) return candidate;
    seq++;
  }
}

// ---------------------------------------------------------------------------
// Backup — write
// ---------------------------------------------------------------------------

/**
 * Handle file collision before placing a symlink:
 * - symlink  → remove silently
 * - file     → backup, then remove
 * - dir      → throw (cannot replace directory with symlink)
 * - none     → no-op
 */
function backupFile(
  file: string,
  absTarget: string,
  backupDir: string,
  pkg: string,
): boolean {
  const type = pathType(file);
  const pkgBackupDir = backupScopeDir(backupDir, pkg, absTarget);

  if (type === "symlink") {
    fs.rmSync(file, { force: true });
    return true;
  }

  if (type === "file") {
    fs.mkdirSync(pkgBackupDir, { recursive: true });
    const now = new Date();
    const timestamp = formatTimestamp(now);
    const relPath = path.relative(expand(absTarget), expand(file));
    const backupPath = uniqueBackupPath(pkgBackupDir, relPath, timestamp);
    ensureParentDir(backupPath);
    fs.cpSync(file, backupPath, { preserveTimestamps: true });
    fs.rmSync(file, { force: true });
    return true;
  }

  if (type === "dir") {
    throw new Error(`Destination is a directory, cannot replace with symlink: ${file}`);
  }

  // type === "none"
  return true;
}

// ---------------------------------------------------------------------------
// Backup — lookup / parse
// ---------------------------------------------------------------------------

/** List backup file candidates in a directory whose basename starts with `prefix`. */
function listBackupCandidates(backupParent: string, prefix: string): string[] {
  try {
    return fs
      .readdirSync(backupParent)
      .map((n) => path.join(backupParent, n))
      .filter((p) => pathType(p) === "file" && path.basename(p).startsWith(prefix));
  } catch {
    return [];
  }
}

const TIMESTAMP_RE = /^\d{8}_\d{6}$/;
const DIGIT_RE = /^\d+$/;

/** Parse a backup filepath into `{ path, timestamp, sequence }`. */
function parseBackupCandidate(backupPath: string, prefix: string): BackupCandidate {
  const basename = path.basename(backupPath);
  const suffix = basename.slice(prefix.length);
  const parts = suffix.split("-");

  if (parts.length === 1) {
    const [ts] = parts;
    return {
      path: backupPath,
      timestamp: TIMESTAMP_RE.test(ts) ? ts : "",
      sequence: 0,
    };
  }

  if (parts.length === 2) {
    const [ts, seq] = parts;
    if (TIMESTAMP_RE.test(ts) && DIGIT_RE.test(seq)) {
      return { path: backupPath, timestamp: ts, sequence: parseInt(seq, 10) };
    }
    return { path: backupPath, timestamp: "", sequence: 0 };
  }

  return { path: backupPath, timestamp: "", sequence: 0 };
}

/** Find the newest valid backup from a list of candidate paths. */
function latestValidBackup(
  backups: string[],
  prefix: string,
): BackupCandidate | null {
  const candidates = backups
    .map((b) => parseBackupCandidate(b, prefix))
    .filter((x) => x.timestamp !== "")
    .sort((a, b) => {
      if (a.timestamp < b.timestamp) return -1;
      if (a.timestamp > b.timestamp) return 1;
      return a.sequence - b.sequence;
    });

  if (candidates.length === 0) return null;
  return candidates[candidates.length - 1];
}

function backupSearchContext(
  targetPath: string,
  absTarget: string,
  absBackup: string,
  pkg: string,
): { relTarget: string; backupParent: string; prefix: string } {
  const relTarget = path.relative(absTarget, targetPath);
  const pkgBackupDir = backupScopeDir(absBackup, pkg, absTarget);
  return {
    relTarget,
    backupParent: path.join(pkgBackupDir, path.dirname(relTarget)),
    prefix: `${path.basename(relTarget)}-`,
  };
}

function backupLookup(
  targetPath: string,
  absTarget: string,
  absBackup: string,
  pkg: string,
): BackupLookupResult {
  const ctx = backupSearchContext(targetPath, absTarget, absBackup, pkg);
  const backups = listBackupCandidates(ctx.backupParent, ctx.prefix);

  if (backups.length === 0) return { status: "missing", path: null };

  const latest = latestValidBackup(backups, ctx.prefix);
  if (!latest) return { status: "invalid", path: null };

  return { status: "found", path: latest.path };
}

// ---------------------------------------------------------------------------
// Target state inspection
// ---------------------------------------------------------------------------

function currentTargetStatus(
  targetPath: string,
  stowPath: string,
): { state: TargetState; link_target: string } {
  const type = pathType(targetPath);

  if (type === "none") return { state: "missing", link_target: "" };
  if (type === "dir") return { state: "directory", link_target: "" };
  if (type === "file") return { state: "file", link_target: "" };

  // symlink
  const linkTarget = readlinkTarget(targetPath);
  if (linkTarget === stowPath) return { state: "managed", link_target: linkTarget };
  return { state: "foreign-symlink", link_target: linkTarget };
}

function removableTargetState(targetPath: string, stowPath: string): "missing" | "managed" {
  const type = pathType(targetPath);

  if (type === "none") return "missing";

  if (type === "dir") {
    throw new Error(
      `Destination is a directory, cannot remove package target: ${targetPath}`,
    );
  }

  if (type !== "symlink") {
    throw new Error(`Target is not the managed symlink for package: ${targetPath}`);
  }

  if (readlinkTarget(targetPath) !== stowPath) {
    throw new Error(`Target is not the managed symlink for package: ${targetPath}`);
  }

  return "managed";
}

// ---------------------------------------------------------------------------
// Status records
// ---------------------------------------------------------------------------

function packageStatusRecords(
  stowPkgDir: string,
  absTarget: string,
  absBackup: string,
  pkg: string,
): StatusRecord[] {
  return collectStowFiles(expand(stowPkgDir), absTarget).map((item) => {
    const ts = currentTargetStatus(item.target, item.stow);
    const backup = backupLookup(item.target, absTarget, absBackup, pkg);
    return {
      target: item.target,
      stow: item.stow,
      state: ts.state,
      link_target: ts.link_target,
      backup_status: backup.status,
      backup_path: backup.path ?? "",
    };
  });
}

// ---------------------------------------------------------------------------
// Restore
// ---------------------------------------------------------------------------

function restoreFile(targetPath: string, backupPath: string): boolean {
  const type = pathType(targetPath);
  if (type === "symlink" || type === "file") {
    fs.rmSync(targetPath, { force: true });
  } else if (type === "dir") {
    throw new Error(`Destination is a directory, cannot restore file: ${targetPath}`);
  }
  ensureParentDir(targetPath);
  fs.cpSync(backupPath, targetPath, { preserveTimestamps: true });
  log.info(`Restored: ${targetPath} <- ${backupPath}`);
  return true;
}

function findLatestBackup(
  targetPath: string,
  absTarget: string,
  absBackup: string,
  pkg: string,
): string | null {
  const lookup = backupLookup(targetPath, absTarget, absBackup, pkg);

  if (lookup.status === "missing") {
    if (pathType(targetPath) === "file") {
      throw new Error(
        `Cannot restore package: Target is a file but no backup found for ${targetPath}`,
      );
    }
    log.warn(`Warning: No backup found for ${targetPath}`);
    return null;
  }

  if (lookup.status === "invalid") {
    if (pathType(targetPath) === "file") {
      throw new Error(
        `Cannot restore package: Target is a file but no valid timestamp backup found for ${targetPath}`,
      );
    }
    log.warn(`Warning: No valid timestamp backup found for ${targetPath}`);
    return null;
  }

  return lookup.path!;
}

// ---------------------------------------------------------------------------
// Symlink deployment
// ---------------------------------------------------------------------------

function linkFiles(items: StowFile[]): void {
  for (const item of items) {
    ensureParentDir(item.target);
    // Force-create symlink (remove first if exists)
    try { fs.rmSync(item.target, { force: true }); } catch { /* ok */ }
    fs.symlinkSync(item.stow, item.target);
  }
}

// ---------------------------------------------------------------------------
// Timestamp formatting
// ---------------------------------------------------------------------------

function formatTimestamp(date: Date): string {
  const pad = (n: number, w = 2) => String(n).padStart(w, "0");
  return (
    `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}` +
    `_${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`
  );
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

function cmdAdd(
  pkg: string,
  filePath: string,
  opts: { target?: string; sourceDir?: string },
): void {
  if (!pkg) fail("package is required");

  const dirs = resolveDirs(opts.target, opts.sourceDir, undefined);
  const expandedSource = expand(dirs.source);
  const expandedPath = expand(filePath);
  const expandedTarget = expand(dirs.target);

  const type = pathType(expandedPath);
  if (type !== "file") {
    fail(`Not a file: ${filePath}`);
  }

  const stowFile = computeStowPath(expandedPath, expandedTarget, expandedSource, pkg);
  ensureParentDir(stowFile);
  try { fs.rmSync(stowFile, { force: true }); } catch { /* ok */ }
  fs.cpSync(expandedPath, stowFile, { preserveTimestamps: true });

  const relForLink = path.relative(expandedTarget, expandedPath);
  if (relForLink.startsWith("..")) {
    fail(`Path ${filePath} is outside the target directory ${expandedTarget}`);
  }
  const targetLink = path.join(expandedTarget, relForLink);
  ensureParentDir(targetLink);
  try { fs.rmSync(targetLink, { force: true }); } catch { /* ok */ }
  fs.symlinkSync(stowFile, targetLink);

  log.info(`Added: ${filePath} -> ${pkg}`);
}

function cmdApply(
  pkg: string,
  opts: { target?: string; sourceDir?: string; backupDir?: string },
): void {
  if (!pkg) fail("package is required");

  const dirs = resolveDirs(opts.target, opts.sourceDir, opts.backupDir);
  const stowPkgDir = path.join(dirs.source, pkg);
  if (!fs.existsSync(stowPkgDir)) fail(`Package does not exist: ${pkg}`);

  const absStowPkg = expand(stowPkgDir);
  const absTarget = expand(dirs.target);
  const absBackup = expand(dirs.backup);

  const filesToLink = collectStowFiles(absStowPkg, absTarget);

  for (const item of filesToLink) {
    backupFile(item.target, absTarget, absBackup, pkg);
  }
  linkFiles(filesToLink);

  log.info(`Applied: ${pkg}`);
}

function cmdRemove(
  pkg: string,
  opts: { target?: string; sourceDir?: string; backupDir?: string },
): void {
  if (!pkg) fail("package is required");

  const dirs = resolveDirs(opts.target, opts.sourceDir, opts.backupDir);
  const stowPkgDir = path.join(dirs.source, pkg);
  if (!fs.existsSync(stowPkgDir)) fail(`Package does not exist: ${pkg}`);

  const absTarget = expand(dirs.target);
  const absBackup = expand(dirs.backup);
  const filesToLink = collectStowFiles(expand(stowPkgDir), absTarget);

  let removedCount = 0;
  let restoredCount = 0;

  for (const item of filesToLink) {
    const lookup = backupLookup(item.target, absTarget, absBackup, pkg);

    if (lookup.status === "invalid") {
      fail(`Cannot remove package: Invalid timestamp backup found for ${item.target}`);
    }

    const targetState = removableTargetState(item.target, item.stow);
    if (targetState === "managed") {
      fs.rmSync(item.target, { force: true });
      removedCount++;
    }

    if (lookup.status === "found") {
      const success = restoreFile(item.target, lookup.path!);
      if (success) restoredCount++;
    }
  }

  if (restoredCount > 0 || removedCount > 0) {
    log.info(
      `Removed package: ${pkg} (restored ${restoredCount} file(s), removed ${removedCount} managed link(s))`,
    );
  } else {
    log.info(`No files removed for package: ${pkg}`);
  }
}

function cmdStatus(
  pkg: string,
  opts: { target?: string; sourceDir?: string; backupDir?: string },
): StatusRecord[] {
  if (!pkg) fail("package is required");

  const dirs = resolveDirs(opts.target, opts.sourceDir, opts.backupDir);
  const stowPkgDir = path.join(dirs.source, pkg);
  if (!fs.existsSync(stowPkgDir)) fail(`Package does not exist: ${pkg}`);

  const absTarget = expand(dirs.target);
  const absBackup = expand(dirs.backup);

  return packageStatusRecords(stowPkgDir, absTarget, absBackup, pkg);
}

function cmdDoctor(
  pkg: string,
  opts: { target?: string; sourceDir?: string; backupDir?: string },
): StatusRecord[] {
  if (!pkg) fail("package is required");

  const dirs = resolveDirs(opts.target, opts.sourceDir, opts.backupDir);
  const stowPkgDir = path.join(dirs.source, pkg);
  if (!fs.existsSync(stowPkgDir)) fail(`Package does not exist: ${pkg}`);

  const absTarget = expand(dirs.target);
  const absBackup = expand(dirs.backup);
  const records = packageStatusRecords(stowPkgDir, absTarget, absBackup, pkg);
  const issues = records.filter(
    (r) => r.state !== "managed" || r.backup_status === "invalid",
  );

  if (issues.length === 0) return records;

  console.table(issues);
  fail(`Doctor found ${issues.length} issue(s) for package: ${pkg}`);
}

function cmdRestore(
  pkg: string,
  opts: { target?: string; sourceDir?: string; backupDir?: string },
): void {
  if (!pkg) fail("package is required");

  const dirs = resolveDirs(opts.target, opts.sourceDir, opts.backupDir);
  const stowPkgDir = path.join(dirs.source, pkg);
  if (!fs.existsSync(stowPkgDir)) fail(`Package does not exist: ${pkg}`);

  const absTarget = expand(dirs.target);
  const absBackup = expand(dirs.backup);
  const filesToLink = collectStowFiles(expand(stowPkgDir), absTarget);

  let restoredCount = 0;

  for (const item of filesToLink) {
    const latestBackup = findLatestBackup(item.target, absTarget, absBackup, pkg);
    if (latestBackup !== null) {
      const success = restoreFile(item.target, latestBackup);
      if (success) restoredCount++;
    }
  }

  if (restoredCount > 0) {
    log.info(`Restored ${restoredCount} file(s) for package: ${pkg}`);
  } else {
    log.info(`No files restored for package: ${pkg}`);
  }
}

function cmdHelp(): void {
  console.log(`linux-config-stow — Dotfiles manager

USAGE:
    linux-config-stow add     <package> <path>   [--target <dir>] [--source-dir <dir>]
    linux-config-stow apply   <package>          [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
    linux-config-stow remove  <package>          [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
    linux-config-stow status  <package>          [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
    linux-config-stow doctor  <package>          [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]
    linux-config-stow restore <package>          [--target <dir>] [--source-dir <dir>] [--backup-dir <dir>]

OPTIONS:
    --target      Target directory (default: ~)
    --source-dir  Source directory (default: ~/.local/share/linux-config)
    --backup-dir  Backup directory (default: ~/.stow-backups)

EXAMPLES:
    linux-config-stow add vim ~/.vimrc
    linux-config-stow add nvim ~/.config/nvim/init.vim
    linux-config-stow apply vim
    linux-config-stow apply nvim --backup-dir ~/.backups
    linux-config-stow remove vim
    linux-config-stow remove nvim --backup-dir ~/.backups
    linux-config-stow status vim
    linux-config-stow doctor vim --backup-dir ~/.backups
    linux-config-stow restore vim
    linux-config-stow restore nvim --backup-dir ~/.backups
`);
}

// ---------------------------------------------------------------------------
// Exported API for use from other scripts (e.g. setup.ts)
// ---------------------------------------------------------------------------

export {
  resolveDirs,
  toStowName,
  fromStowName,
  computeStowPath,
  collectStowFiles,
  backupScopeDir,
  uniqueBackupPath,
  backupLookup,
  packageStatusRecords,
  cmdAdd,
  cmdApply,
  cmdRemove,
  cmdStatus,
  cmdDoctor,
  cmdRestore,
  main,
};
export type { Dirs, StowFile, StatusRecord, BackupLookupResult, BackupStatus, TargetState };

// ---------------------------------------------------------------------------
// CLI argument parser
// ---------------------------------------------------------------------------

function parseArgs(argv: string[]): {
  command: string;
  positional: string[];
  flags: Record<string, string>;
} {
  const command = argv[0] ?? "help";
  const positional: string[] = [];
  const flags: Record<string, string> = {};

  for (let i = 1; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const value = argv[i + 1] ?? "";
      flags[key] = value;
      i++; // consume value
    } else {
      positional.push(arg);
    }
  }

  return { command, positional, flags };
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

function main(): void {
  const argv = process.argv.slice(2);
  if (argv.length === 0) {
    cmdHelp();
    return;
  }

  const { command, positional, flags } = parseArgs(argv);

  const opts = {
    target: flags["target"],
    sourceDir: flags["source-dir"],
    backupDir: flags["backup-dir"],
  };

  try {
    switch (command) {
      case "add": {
        const [pkg, filePath] = positional;
        if (!pkg || !filePath) { log.error("Usage: linux-config-stow add <package> <path>"); process.exit(1); }
        cmdAdd(pkg, filePath, opts);
        break;
      }
      case "apply": {
        const [pkg] = positional;
        if (!pkg) { log.error("Usage: linux-config-stow apply <package>"); process.exit(1); }
        cmdApply(pkg, opts);
        break;
      }
      case "remove": {
        const [pkg] = positional;
        if (!pkg) { log.error("Usage: linux-config-stow remove <package>"); process.exit(1); }
        cmdRemove(pkg, opts);
        break;
      }
      case "status": {
        const [pkg] = positional;
        if (!pkg) { log.error("Usage: linux-config-stow status <package>"); process.exit(1); }
        const records = cmdStatus(pkg, opts);
        console.table(records);
        break;
      }
      case "doctor": {
        const [pkg] = positional;
        if (!pkg) { log.error("Usage: linux-config-stow doctor <package>"); process.exit(1); }
        cmdDoctor(pkg, opts);
        break;
      }
      case "restore": {
        const [pkg] = positional;
        if (!pkg) { log.error("Usage: linux-config-stow restore <package>"); process.exit(1); }
        cmdRestore(pkg, opts);
        break;
      }
      case "help":
      case "--help":
      case "-h":
        cmdHelp();
        break;
      default:
        log.error(`Unknown command: ${command}`);
        cmdHelp();
        process.exit(1);
    }
  } catch (err) {
    log.error((err as Error).message);
    process.exit(1);
  }
}

if (import.meta.main) {
  main();
}
