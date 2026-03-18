#!/usr/bin/env bun

/**
 * test-stow.ts — Integration test suite for stow.ts
 *
 * Mirrors the behaviour tested in nu/tests/test-stow.nu.
 * Run with:  bun test tests/stow.test.ts
 *            (or: bun run tests/stow.test.ts)
 */

import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import {
  toStowName,
  fromStowName,
  uniqueBackupPath,
  cmdAdd,
  cmdApply,
  cmdRemove,
  cmdStatus,
  cmdDoctor,
  cmdRestore,
} from "../src/stow.ts";

// ---------------------------------------------------------------------------
// Test harness helpers
// ---------------------------------------------------------------------------

function pathType(p: string): string {
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

function readContent(p: string): string {
  try {
    return fs.readFileSync(p, "utf8");
  } catch {
    return "";
  }
}

function isExecutable(p: string): boolean {
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function findFiles(root: string): string[] {
  const results: string[] = [];
  function walk(dir: string): void {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) walk(full);
      else results.push(full);
    }
  }
  walk(root);
  return results;
}

function readlink(p: string): string {
  try { return fs.readlinkSync(p); } catch { return ""; }
}

// ---------------------------------------------------------------------------
// Temporary test workspace
// ---------------------------------------------------------------------------

const now = new Date();
const ts = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}_${String(now.getHours()).padStart(2, "0")}${String(now.getMinutes()).padStart(2, "0")}${String(now.getSeconds()).padStart(2, "0")}`;
const TEST_BASE = path.join(os.tmpdir(), `stow-test-${ts}`);
const SOURCE_DIR = path.join(TEST_BASE, "source");
const TARGET_DIR = path.join(TEST_BASE, "target");
const BACKUP_DIR = path.join(TEST_BASE, "backups");

beforeAll(() => {
  fs.mkdirSync(SOURCE_DIR, { recursive: true });
  fs.mkdirSync(TARGET_DIR, { recursive: true });
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
});

afterAll(() => {
  fs.rmSync(TEST_BASE, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Unit tests: name conversion helpers
// ---------------------------------------------------------------------------

describe("toStowName / fromStowName", () => {
  it("converts .config → dot-config", () => {
    expect(toStowName(".config")).toBe("dot-config");
  });

  it("leaves non-dot names alone", () => {
    expect(toStowName("config")).toBe("config");
  });

  it("converts dot-config → .config", () => {
    expect(fromStowName("dot-config")).toBe(".config");
  });

  it("leaves non-dot- prefixed names alone", () => {
    expect(fromStowName("config")).toBe("config");
  });
});

// ---------------------------------------------------------------------------
// Unit tests: uniqueBackupPath
// ---------------------------------------------------------------------------

describe("uniqueBackupPath", () => {
  it("returns base path when no collision", () => {
    const dir = path.join(TEST_BASE, "uniq-test");
    fs.mkdirSync(dir, { recursive: true });
    const p = uniqueBackupPath(dir, ".vimrc", "20260101_010101");
    expect(p).toBe(path.join(dir, ".vimrc-20260101_010101"));
  });

  it("adds -1 on first collision", () => {
    const dir = path.join(TEST_BASE, "collision-test");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, ".vimrc-20260101_010101"), "first");
    const p = uniqueBackupPath(dir, ".vimrc", "20260101_010101");
    expect(p).toBe(path.join(dir, ".vimrc-20260101_010101-1"));
  });

  it("adds -2 when -1 also exists", () => {
    const dir = path.join(TEST_BASE, "collision-test2");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, ".vimrc-20260101_010101"), "first");
    fs.writeFileSync(path.join(dir, ".vimrc-20260101_010101-1"), "second");
    const p = uniqueBackupPath(dir, ".vimrc", "20260101_010101");
    expect(p).toBe(path.join(dir, ".vimrc-20260101_010101-2"));
  });
});

// ---------------------------------------------------------------------------
// Integration: add basic
// ---------------------------------------------------------------------------

describe("stow add — basic", () => {
  const vimrcPath = path.join(TARGET_DIR, ".vimrc");
  const stowVim = path.join(SOURCE_DIR, "vim", "dot-vimrc");

  beforeAll(() => {
    fs.writeFileSync(vimrcPath, "vimrc content");
    cmdAdd("vim", vimrcPath, { target: TARGET_DIR, sourceDir: SOURCE_DIR });
  });

  it("stages file under source/vim/dot-vimrc", () => {
    expect(fs.existsSync(stowVim)).toBe(true);
  });

  it("replaces original with symlink", () => {
    expect(pathType(vimrcPath)).toBe("symlink");
  });

  it("symlink content matches original", () => {
    expect(readContent(vimrcPath)).toBe("vimrc content");
  });
});

// ---------------------------------------------------------------------------
// Integration: add preserves executable bit
// ---------------------------------------------------------------------------

describe("stow add — executable bit", () => {
  const binDir = path.join(TARGET_DIR, ".local", "bin");
  const execTarget = path.join(binDir, "demo");
  const stagedExec = path.join(SOURCE_DIR, "bin", "dot-local", "bin", "demo");

  beforeAll(() => {
    fs.mkdirSync(binDir, { recursive: true });
    fs.writeFileSync(execTarget, "#!/usr/bin/env bash\necho demo");
    fs.chmodSync(execTarget, 0o755);
    cmdAdd("bin", execTarget, { target: TARGET_DIR, sourceDir: SOURCE_DIR });
  });

  it("staged file retains executable bit", () => {
    expect(isExecutable(stagedExec)).toBe(true);
  });

  it("deployed symlink is executable", () => {
    expect(isExecutable(execTarget)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Integration: add — rejections
// ---------------------------------------------------------------------------

describe("stow add — rejections", () => {
  it("rejects a directory", () => {
    const d = path.join(TARGET_DIR, ".config");
    fs.mkdirSync(d, { recursive: true });
    expect(() =>
      cmdAdd("nvim", d, { target: TARGET_DIR, sourceDir: SOURCE_DIR }),
    ).toThrow();
  });

  it("rejects a symlink-to-file", () => {
    const real = path.join(TEST_BASE, "aliases-real");
    fs.writeFileSync(real, "alias ll='ls -la'");
    const link = path.join(TARGET_DIR, ".aliases");
    try { fs.rmSync(link, { force: true }); } catch { /* ok */ }
    fs.symlinkSync(real, link);
    expect(() =>
      cmdAdd("shell", link, { target: TARGET_DIR, sourceDir: SOURCE_DIR }),
    ).toThrow();
  });

  it("rejects a file outside the target", () => {
    const outside = path.join(TEST_BASE, "outside.txt");
    fs.writeFileSync(outside, "outside content");
    expect(() =>
      cmdAdd("out", outside, { target: TARGET_DIR, sourceDir: SOURCE_DIR }),
    ).toThrow();
  });
});

// ---------------------------------------------------------------------------
// Integration: add nested dot-path
// ---------------------------------------------------------------------------

describe("stow add — nested dot-path", () => {
  const nvimDir = path.join(TARGET_DIR, ".config", "nvim");
  const initLua = path.join(nvimDir, "init.lua");
  const staged = path.join(SOURCE_DIR, "nvim", "dot-config", "nvim", "init.lua");

  beforeAll(() => {
    fs.mkdirSync(nvimDir, { recursive: true });
    fs.writeFileSync(initLua, "lua config");
    cmdAdd("nvim", initLua, { target: TARGET_DIR, sourceDir: SOURCE_DIR });
  });

  it("stages file at correct dot-converted path", () => {
    expect(fs.existsSync(staged)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Integration: re-add refreshes staged content
// ---------------------------------------------------------------------------

describe("stow add — re-add updates staged content", () => {
  const vimrcPath = path.join(TARGET_DIR, ".vimrc");
  const stowVim = path.join(SOURCE_DIR, "vim", "dot-vimrc");

  beforeAll(() => {
    // Remove existing symlink and write a new file
    try { fs.rmSync(vimrcPath, { force: true }); } catch { /* ok */ }
    fs.writeFileSync(vimrcPath, "vimrc content v2");
    cmdAdd("vim", vimrcPath, { target: TARGET_DIR, sourceDir: SOURCE_DIR });
  });

  it("staged file content is updated", () => {
    expect(readContent(stowVim)).toBe("vimrc content v2");
  });
});

// ---------------------------------------------------------------------------
// Integration: apply, restore
// ---------------------------------------------------------------------------

describe("stow apply / restore", () => {
  const target2 = path.join(TEST_BASE, "target2");
  let t2Vimrc: string;

  beforeAll(() => {
    fs.mkdirSync(target2, { recursive: true });
    t2Vimrc = path.join(target2, ".vimrc");
    fs.writeFileSync(t2Vimrc, "OLD VIMRC CONTENT");
    cmdApply("vim", { target: target2, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR });
  });

  it("apply creates symlink at target", () => {
    expect(pathType(t2Vimrc)).toBe("symlink");
  });

  it("apply creates a backup of the original file", () => {
    // Find any backup files in the backup dir whose basename starts with ".vimrc-"
    const backups = findFiles(BACKUP_DIR).filter((f) =>
      path.basename(f).startsWith(".vimrc-"),
    );
    expect(backups.length).toBeGreaterThan(0);
  });

  it("apply backup content matches original", () => {
    const backups = findFiles(BACKUP_DIR).filter((f) =>
      path.basename(f).startsWith(".vimrc-"),
    );
    expect(readContent(backups[0])).toBe("OLD VIMRC CONTENT");
  });

  it("apply over existing symlink succeeds", () => {
    const target3 = path.join(TEST_BASE, "target3");
    fs.mkdirSync(target3, { recursive: true });
    const t3Vimrc = path.join(target3, ".vimrc");
    fs.symlinkSync("/dummy", t3Vimrc);
    expect(() =>
      cmdApply("vim", { target: target3, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR }),
    ).not.toThrow();
    // Symlink now points into our source dir
    expect(readlink(t3Vimrc)).toContain(path.join(SOURCE_DIR, "vim"));
  });

  it("apply fails on directory collision", () => {
    const target4 = path.join(TEST_BASE, "target4");
    fs.mkdirSync(path.join(target4, ".vimrc"), { recursive: true });
    expect(() =>
      cmdApply("vim", { target: target4, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR }),
    ).toThrow();
  });

  it("apply fails for missing package", () => {
    expect(() =>
      cmdApply("imaginary", { target: target2, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR }),
    ).toThrow();
  });

  it("restore recreates real file", () => {
    cmdRestore("vim", { target: target2, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR });
    expect(pathType(t2Vimrc)).toBe("file");
  });

  it("restore recovers original content", () => {
    expect(readContent(t2Vimrc)).toBe("OLD VIMRC CONTENT");
  });
});

// ---------------------------------------------------------------------------
// Integration: remove
// ---------------------------------------------------------------------------

describe("stow remove", () => {
  const targetRemove = path.join(TEST_BASE, "target-remove");
  const trVimrc = path.join(targetRemove, ".vimrc");

  beforeAll(() => {
    fs.mkdirSync(targetRemove, { recursive: true });
    fs.writeFileSync(trVimrc, "REMOVE ORIGINAL");
    cmdApply("vim", { target: targetRemove, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR });
    cmdRemove("vim", { target: targetRemove, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR });
  });

  it("remove restores backup content", () => {
    expect(readContent(trVimrc)).toBe("REMOVE ORIGINAL");
  });

  it("remove restores a real file", () => {
    expect(pathType(trVimrc)).toBe("file");
  });

  it("remove without backup leaves target absent", () => {
    const targetRemoveClean = path.join(TEST_BASE, "target-remove-clean");
    fs.mkdirSync(targetRemoveClean, { recursive: true });
    const cleanVimrc = path.join(targetRemoveClean, ".vimrc");
    // Apply with no pre-existing file (no backup created)
    cmdApply("vim", { target: targetRemoveClean, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR });
    cmdRemove("vim", { target: targetRemoveClean, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR });
    expect(fs.existsSync(cleanVimrc)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Integration: status / doctor
// ---------------------------------------------------------------------------

describe("stow status / doctor", () => {
  const targetStatusOk = path.join(TEST_BASE, "target-status-ok");

  beforeAll(() => {
    fs.mkdirSync(targetStatusOk, { recursive: true });
    cmdApply("vim", { target: targetStatusOk, sourceDir: SOURCE_DIR, backupDir: BACKUP_DIR });
  });

  it("status reports all entries as managed", () => {
    const records = cmdStatus("vim", {
      target: targetStatusOk,
      sourceDir: SOURCE_DIR,
      backupDir: BACKUP_DIR,
    });
    expect(records.every((r) => r.state === "managed")).toBe(true);
  });

  it("doctor passes for a cleanly managed package", () => {
    expect(() =>
      cmdDoctor("vim", {
        target: targetStatusOk,
        sourceDir: SOURCE_DIR,
        backupDir: BACKUP_DIR,
      }),
    ).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// Integration: multi-file package (apply / doctor / remove)
// ---------------------------------------------------------------------------

describe("stow multi-file package", () => {
  const targetMulti = path.join(TEST_BASE, "target-multi");
  const configA = path.join(targetMulti, ".config", "app", "config-a.toml");
  const configB = path.join(targetMulti, ".config", "app", "config-b.toml");
  const profile = path.join(targetMulti, ".profile");

  beforeAll(() => {
    // Stage files directly into source (simulates having already run 'add')
    const multiPkgDir = path.join(SOURCE_DIR, "multi");
    fs.mkdirSync(path.join(multiPkgDir, "dot-config", "app"), { recursive: true });
    fs.writeFileSync(
      path.join(multiPkgDir, "dot-config", "app", "config-a.toml"),
      "config-a content",
    );
    fs.writeFileSync(
      path.join(multiPkgDir, "dot-config", "app", "config-b.toml"),
      "config-b content",
    );
    fs.writeFileSync(path.join(multiPkgDir, "dot-profile"), "profile content");

    fs.mkdirSync(targetMulti, { recursive: true });
    cmdApply("multi", {
      target: targetMulti,
      sourceDir: SOURCE_DIR,
      backupDir: BACKUP_DIR,
    });
  });

  it("apply creates first symlink (config-a.toml)", () => {
    expect(pathType(configA)).toBe("symlink");
  });

  it("apply creates second symlink (config-b.toml)", () => {
    expect(pathType(configB)).toBe("symlink");
  });

  it("apply creates dot-prefixed symlink (.profile)", () => {
    expect(pathType(profile)).toBe("symlink");
  });

  it("doctor passes for multi-file package", () => {
    expect(() =>
      cmdDoctor("multi", {
        target: targetMulti,
        sourceDir: SOURCE_DIR,
        backupDir: BACKUP_DIR,
      }),
    ).not.toThrow();
  });

  it("remove clears all managed symlinks", () => {
    cmdRemove("multi", {
      target: targetMulti,
      sourceDir: SOURCE_DIR,
      backupDir: BACKUP_DIR,
    });
    expect(fs.existsSync(configA)).toBe(false);
    expect(fs.existsSync(configB)).toBe(false);
    expect(fs.existsSync(profile)).toBe(false);
  });
});
