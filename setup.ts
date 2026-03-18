#!/usr/bin/env bun

import { $ } from "bun";
import * as fs from "node:fs/promises";
import * as fsSync from "node:fs";
import * as path from "node:path";

type Target = "shell" | "desktop";

type Platform =
  | "ublue"
  | "fedora"
  | "trixie"
  | "questing"
  | "pikaos"
  | "tumbleweed"
  | "arch"
  | "fedora-atomic"
  | "unsupported";

const color = (code: number) => (s: string) => `\x1b[${code}m${s}\x1b[0m`;
const chalk = { green: color(32), yellow: color(33), red: color(31) };
const HOME_DIR = Bun.env["HOME"] ?? "/root";
const DOT_DIR = path.join(HOME_DIR, ".local/share/linux-config");
const REPO_URL = "https://github.com/pervezfunctor/linux-config.git";
const DEFAULT_TARGETS: readonly Target[] = ["shell", "desktop"];

const log = {
  info: (msg: string) => console.log(chalk.green("INFO") + " " + msg),
  warn: (msg: string) => console.warn(chalk.yellow("WARN") + " " + msg),
  error: (msg: string) => console.error(chalk.red("ERROR") + " " + msg),
};

async function hasCmd(cmd: string): Promise<boolean> {
  return (await $`which ${cmd}`.quiet().nothrow()).exitCode === 0;
}

async function checkCmd(...commands: string[]): Promise<void> {
  for (const cmd of commands) {
    if (!(await hasCmd(cmd))) {
      throw new Error(`${cmd} not installed. Quitting.`);
    }
  }
}

async function currentOs(): Promise<Platform> {
  const ostree = await hasCmd("rpm-ostree");
  if (ostree) return (await hasCmd("ujust")) ? "ublue" : "fedora-atomic";

  const rh = await fs
    .readFile("/etc/redhat-release", "utf8")
    .catch(() => "")
    .then((t: string) => t.toLowerCase());
  const osRelease = await fs
    .readFile("/etc/os-release", "utf8")
    .catch(() => "")
    .then((t: string) => t.toLowerCase());

  if (rh.includes("fedora") || osRelease.includes("fedora")) return "fedora";
  if (osRelease.includes("trixie")) return "trixie";
  if (osRelease.includes("questing")) return "questing";
  if (osRelease.includes("tumbleweed")) return "tumbleweed";
  if (osRelease.includes("pika")) return "pikaos";
  if (osRelease.includes("arch")) return "arch";

  return "unsupported";
}

function setEnv(): void {
  const paths = [
    [HOME_DIR, "bin"],
    [HOME_DIR, ".local/bin"],
    [HOME_DIR, ".cargo/bin"],
    [".local/share/mise/shims"],
    ["/home/linuxbrew/.linuxbrew/bin"],
    [DOT_DIR, "bin"],
    [DOT_DIR, "nu"],
    [HOME_DIR, ".pixi/bin"],
    [".volta/bin"],
  ].map(([base, ...rest]) => path.join(String(base), ...rest.map(String)));

  process.env.PATH = [...paths, process.env.PATH || ""].join(path.delimiter);
}

async function si(platform: Platform, packages: readonly string[]): Promise<void> {
  const joined = packages.join(" ");
  log.info(`Installing ${joined}`);
  switch (platform) {
    case "ublue":
      await $`brew install ${packages}`;
      break;
    case "fedora":
      await $`sudo dnf install -y ${packages}`;
      break;
    case "trixie":
    case "questing":
      await $`sudo apt install -y ${packages}`;
      break;
    case "pikaos":
      await $`pikman install ${packages}`;
      break;
    case "tumbleweed":
      await $`sudo zypper --non-interactive --quiet install --auto-agree-with-licenses ${packages}`;
      break;
    case "arch":
      await $`sudo pacman -S --quiet --noconfirm ${packages}`;
      break;
    default:
      log.warn(`OS not supported. Not installing ${joined}.`);
      throw new Error(`Unsupported platform: ${platform}`);
  }
}

async function updatePackages(platform: Platform): Promise<void> {
  log.info("Updating packages");
  switch (platform) {
    case "ublue":
      await $`brew update`;
      await $`brew upgrade`;
      break;
    case "fedora":
      await $`sudo dnf update -y`;
      break;
    case "trixie":
    case "questing":
      await $`sudo apt update`;
      await $`sudo apt upgrade -y`;
      break;
    case "pikaos":
      await $`pikman update`;
      await $`pikman upgrade`;
      break;
    case "tumbleweed":
      await $`sudo zypper refresh`;
      await $`sudo zypper update`;
      break;
    case "arch":
      await $`sudo pacman -Syyu`;
      await $`sudo pacman -Fy`;
      break;
    default:
      log.warn("OS not supported. Not updating.");
      break;
  }
}

async function installPixi(): Promise<void> {
  log.info("Installing pixi and essential packages...");
  if (!(await hasCmd("pixi"))) {
    await $`curl -fsSL https://pixi.sh/install.sh | sh`.catch((err: Error) =>
      log.warn(`Failed to download pixi: ${err.message}`),
    );
  }
  await checkCmd("pixi");
}

async function syncDotfiles(): Promise<void> {
  if (!fsSync.existsSync(path.join(DOT_DIR, ".git"))) {
    log.info("Cloning dotfiles");
    await $`git clone --depth 1 ${REPO_URL} ${DOT_DIR}`;
    return;
  }

  if ((await $`git -C ${DOT_DIR} status --porcelain=v1`).text().trim()) {
    throw new Error("Dotfiles repo has local changes. Stash them and run this script again.");
  }

  log.info("Dotfiles repo clean. Pulling latest changes");
  if ((await $`git -C ${DOT_DIR} pull --rebase --stat`.nothrow()).exitCode === 0) {
    log.info("Dotfiles updated");
    return;
  }

  log.warn("Pull failed. Aborting rebase...");
  await $`git -C ${DOT_DIR} rebase --abort`.nothrow().quiet();
  throw new Error("Failed to sync dotfiles");
}

async function installPixiPackages(): Promise<void> {
  const pkgs = ["nushell", "trash-cli", "go-gum", "starship", "gh"];
  const result = await $`pixi global install ${pkgs}`.nothrow();
  if (result.exitCode !== 0) {
    log.warn("pixi install failed. Quitting.");
  }
  await checkCmd("nu", "trash", "starship", "gh");
}

async function installPackages(platform: Platform): Promise<void> {
  log.info("Installing required packages...");
  const required = ["curl", "git", "fish"];
  for (const pkg of required) {
    if (!(await hasCmd(pkg))) {
      await si(platform, [pkg]);
      await checkCmd(pkg);
    }
  }
}

async function runSetup(targets: readonly Target[]): Promise<void> {
  setEnv();

  const platform = await currentOs();

  if (platform === "unsupported") {
    throw new Error(
      "Only Fedora, Ubuntu Questing, Tumbleweed, Arch, Debian Trixie and PikaOS supported. Quitting.",
    );
  }

  await updatePackages(platform);
  await installPackages(platform);
  await installPixi();
  await installPixiPackages();
  await syncDotfiles();

  const shellSetup = path.join(DOT_DIR, "nu/setup-shell.nu");
  await $`nu ${shellSetup} fish config`;
  for (const target of targets) {
    if (target === "shell") {
      await $`nu ${shellSetup}`;
    } else {
      const desktopSetup = path.join(DOT_DIR, "nu/setup-desktop.nu");
      await $`nu ${desktopSetup}`;
    }
  }
}

function parseCliArgs(argv: readonly string[]): readonly Target[] {
  const targets: Target[] = [];
  for (const arg of argv) {
    if (arg === "shell" || arg === "desktop") {
      targets.push(arg);
    }
  }
  const uniqueTargets = Array.from(new Set(targets));
  return uniqueTargets.length > 0 ? uniqueTargets : [...DEFAULT_TARGETS];
}

async function main(argv?: readonly string[]): Promise<number> {
  const args = argv ?? process.argv.slice(2);

  try {
    await runSetup(parseCliArgs(args));
  } catch (err) {
    const error = err as Error;
    log.error(error.message);
    return 1;
  }
  return 0;
}

main().then((code) => process.exit(code));
