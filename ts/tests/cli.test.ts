#!/usr/bin/env bun

import { describe, expect, it } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const TEST_DIR = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_DIR = path.resolve(TEST_DIR, "..");
const packageJson = JSON.parse(
  fs.readFileSync(path.join(PROJECT_DIR, "package.json"), "utf8"),
) as { bin?: Record<string, string> };

function runScript(command: string, expectedText: string) {
  const result = spawnSync("bun", ["run", command, "--help"], {
    cwd: PROJECT_DIR,
    encoding: "utf8",
  });

  expect(result.status).toBe(0);
  expect(`${result.stdout}${result.stderr}`).toContain(expectedText);
}

describe("CLI package entrypoints", () => {
  it("declares package binaries", () => {
    expect(packageJson.bin).toEqual({
      "linux-config": "./src/setup.ts",
      "linux-config-stow": "./src/stow.ts",
      "linux-config-logs": "./src/view_logs.ts",
    });
  });

  it("exposes the setup CLI locally via bun run setup", () => {
    runScript("setup", "linux-config - Linux system setup CLI");
  });

  it("exposes the stow CLI locally via bun run stow", () => {
    runScript("stow", "linux-config-stow — Dotfiles manager");
  });

  it("exposes the logs CLI locally via bun run logs", () => {
    runScript("logs", "linux-config-logs - Inspect bootstrap logs");
  });
});
