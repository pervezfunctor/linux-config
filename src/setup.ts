#!/usr/bin/env bun

import { $ } from "bun";
import * as fs from "node:fs/promises";
import * as fsSync from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { cmdApply } from "./stow.ts";

const HOME_DIR = os.homedir();
const DOT_DIR = path.join(HOME_DIR, ".local/share/linux-config");
const REPO_URL = "https://github.com/pervezfunctor/linux-config.git";

const color = (code: number) => (s: string) => `\x1b[${code}m${s}\x1b[0m`;
const c = {
  green: color(32),
  yellow: color(33),
  red: color(31),
  cyan: color(36),
  reset: color(0),
};

const log = {
  info: (msg: string) => console.log(c.green("[INFO]") + " " + msg),
  warn: (msg: string) => console.warn(c.yellow("[WARN]") + " " + msg),
  error: (msg: string) => console.error(c.red("[ERROR]") + " " + msg),
};

function die(msg: string): never {
  log.error(msg);
  process.exit(1);
}

type Platform =
  | "ublue"
  | "fedora"
  | "fedora-atomic"
  | "trixie"
  | "questing"
  | "pikaos"
  | "tumbleweed"
  | "arch"
  | "cachy"
  | "mac"
  | "unsupported";

async function getPlatform(): Promise<Platform> {
  let _platform: Platform | null = null;
  if (_platform) return _platform;

  // macOS
  const uname = await $`uname -s`.quiet().nothrow().text();
  if (uname.trim() === "Darwin") return (_platform = "mac");

  const hasRpmOstree = await hasCmd("rpm-ostree");
  if (hasRpmOstree) {
    return (_platform = (await hasCmd("ujust")) ? "ublue" : "fedora-atomic");
  }

  const osRelease = await fs
    .readFile("/etc/os-release", "utf8")
    .catch(() => "")
    .then((t) => t.toLowerCase());

  const rh = await fs
    .readFile("/etc/redhat-release", "utf8")
    .catch(() => "")
    .then((t) => t.toLowerCase());

  const hostname = os.hostname().toLowerCase();

  if (hostname.includes("cachy")) return (_platform = "cachy");
  if (rh.includes("fedora") || osRelease.includes('id="fedora"') || osRelease.includes("id=fedora"))
    return (_platform = "fedora");
  if (osRelease.includes("trixie")) return (_platform = "trixie");
  if (osRelease.includes("questing")) return (_platform = "questing");
  if (osRelease.includes("tumbleweed")) return (_platform = "tumbleweed");
  if (osRelease.includes("pika")) return (_platform = "pikaos");
  if (osRelease.includes("arch") || osRelease.includes("cachyos")) return (_platform = "arch");

  return (_platform = "unsupported");
}

async function isMac() {
  return (await getPlatform()) === "mac";
}
async function isUblue() {
  return (await getPlatform()) === "ublue";
}
async function isFedoraAtomic() {
  return (await getPlatform()) === "fedora-atomic";
}
async function isFedora() {
  return (await getPlatform()) === "fedora";
}
async function isTrixie() {
  return (await getPlatform()) === "trixie";
}
async function isQuesting() {
  return (await getPlatform()) === "questing";
}
async function isTumbleweed() {
  return (await getPlatform()) === "tumbleweed";
}
async function isPikaos() {
  return (await getPlatform()) === "pikaos";
}
async function isArch() {
  const p = await getPlatform();
  return p === "arch" || p === "cachy";
}
async function isCachy() {
  return (await getPlatform()) === "cachy";
}
async function isApt() {
  return (await isQuesting()) || (await isTrixie()) || (await isPikaos());
}
async function isNonAtomicLinux() {
  return !(await isMac()) && !(await isFedoraAtomic()) && !(await isUblue());
}

async function hasCmd(cmd: string): Promise<boolean> {
  return (await $`which ${cmd}`.quiet().nothrow()).exitCode === 0;
}

function dirExists(p: string): boolean {
  try {
    return fsSync.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

async function promptYn(prompt: string): Promise<boolean> {
  process.stdout.write(c.cyan(`? ${prompt}`) + c.yellow(" [y/N] ") + "\x1b[0m");
  for await (const line of console) {
    return /^y(es)?$/i.test(line.trim());
  }
  return false;
}

async function touchFiles(dir: string, files: string[]): Promise<void> {
  await fs.mkdir(dir, { recursive: true }).catch(() => {});
  for (const f of files) {
    const fp = path.join(dir, f);
    if (!fsSync.existsSync(fp)) {
      await fs.writeFile(fp, "");
    }
  }
}

async function handle(fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
  } catch (err) {
    log.error((err as Error).message);
  }
}

function setEnv(): void {
  const paths = [
    path.join(HOME_DIR, "bin"),
    path.join(HOME_DIR, ".local/bin"),
    path.join(HOME_DIR, ".cargo/bin"),
    path.join(HOME_DIR, ".local/share/mise/shims"),
    "/home/linuxbrew/.linuxbrew/bin",
    path.join(DOT_DIR, "bin"),
    path.join(DOT_DIR, "nu"),
    path.join(HOME_DIR, ".pixi/bin"),
    path.join(HOME_DIR, ".volta/bin"),
  ];
  process.env.PATH = [...paths, process.env.PATH ?? ""].join(path.delimiter);
  process.env.DOT_DIR = DOT_DIR;
}

async function keepSudoAlive(): Promise<ReturnType<typeof setInterval>> {
  await $`sudo -v`;
  return setInterval(() => $`sudo -n true`.quiet().nothrow(), 55_000);
}

function stopSudoAlive(timer: ReturnType<typeof setInterval>): void {
  clearInterval(timer);
  $`sudo -k`.quiet().nothrow();
}

async function si(packages: readonly string[]): Promise<void> {
  const joined = packages.join(" ");
  log.info(`Installing ${joined}`);
  const p = await getPlatform();
  switch (p) {
    case "mac":
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
    case "cachy":
      await $`sudo pacman -S --quiet --noconfirm ${packages}`;
      break;
    default:
      log.warn(`OS not supported. Not installing ${joined}.`);
      throw new Error(`Unsupported platform: ${p}`);
  }
}

async function updatePackages(): Promise<void> {
  log.info("Updating packages");
  const p = await getPlatform();
  switch (p) {
    case "mac":
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
    case "cachy":
      await $`sudo pacman -Syyu`;
      await $`sudo pacman -Fy`;
      break;
    default:
      log.warn("OS not supported. Not updating.");
  }
}

async function dotfilesClone(): Promise<void> {
  log.info("Cloning dotfiles");
  await $`git clone ${REPO_URL} ${DOT_DIR}`;
}

async function abortRebaseIfNeeded(): Promise<void> {
  const rebaseMerge = path.join(DOT_DIR, ".git", "rebase-merge");
  const rebaseApply = path.join(DOT_DIR, ".git", "rebase-apply");
  if (fsSync.existsSync(rebaseMerge) || fsSync.existsSync(rebaseApply)) {
    log.warn("Aborting rebase");
    await $`git -C ${DOT_DIR} rebase --abort`.nothrow().quiet();
  }
}

async function dotfilesValidate(): Promise<string> {
  await $`git -C ${DOT_DIR} rev-parse --is-inside-work-tree`.quiet();
  const remoteUrl = (await $`git -C ${DOT_DIR} remote get-url origin`.text()).trim();
  if (!remoteUrl) throw new Error("Remote URL is empty. Is 'origin' configured?");
  if (remoteUrl !== REPO_URL)
    throw new Error(`Unexpected remote: expected '${REPO_URL}', got '${remoteUrl}'`);
  return (await $`git -C ${DOT_DIR} status --porcelain=v1`.text()).trim();
}

async function dotfilesPullClean(): Promise<void> {
  log.info("Pulling latest changes (clean repo)");
  const result = await $`git -C ${DOT_DIR} pull --rebase --stat`.nothrow();
  if (result.exitCode !== 0) {
    await abortRebaseIfNeeded();
    throw new Error("git pull --rebase failed on clean repo");
  }
  log.info("Dotfiles updated");
}

async function dotfilesPullDirty(): Promise<void> {
  log.info("Stashing local changes before pull");
  const stashLabel = `setup-autostash-${Date.now()}`;
  await $`git -C ${DOT_DIR} stash push --include-untracked -m ${stashLabel}`;

  const pull = await $`git -C ${DOT_DIR} pull --rebase --stat`.nothrow();
  if (pull.exitCode !== 0) await abortRebaseIfNeeded();

  log.info("Restoring local changes from stash");
  const pop = await $`git -C ${DOT_DIR} stash pop`.nothrow();
  if (pop.exitCode !== 0) throw new Error("Stash pop failed — working tree may have conflicts");
  if (pull.exitCode !== 0) throw new Error("git pull --rebase failed; local changes restored");
  log.info("Dotfiles updated");
}

async function syncDotfiles(): Promise<void> {
  const gitDir = path.join(DOT_DIR, ".git");
  if (!fsSync.existsSync(gitDir)) {
    await dotfilesClone();
    return;
  }
  const status = await dotfilesValidate();
  if (!status) {
    await dotfilesPullClean();
  } else {
    await dotfilesPullDirty();
  }
}

async function stowPackage(pkg: string): Promise<void> {
  log.info(`Stowing ${pkg} dotfiles`);
  await handle(() =>
    Promise.resolve(cmdApply(pkg, { sourceDir: DOT_DIR }))
  );
}

async function setupNushellConfig(): Promise<void> {
  await stowPackage("nushell");
}

async function setupFishConfig(): Promise<void> {
  if (!(await hasCmd("fish"))) {
    log.error("fish not found");
    return;
  }
  log.info("Setting up fish...");
  await stowPackage("fish");
  log.info("Change default shell to fish");
  const fishPath = (await $`which fish`.text()).trim();
  await handle(() => $`chsh -s ${fishPath}`.then(() => {}));
}

async function installPixi(): Promise<void> {
  if (await hasCmd("pixi")) return;
  log.info("Installing pixi...");
  await $`sh -c "$(curl -fsSL https://pixi.sh/install.sh)"`.catch((err: Error) =>
    log.warn(`Failed to install pixi: ${err.message}`),
  );
}

async function installPixiPackages(): Promise<void> {
  log.info("Installing shell tools with pixi");
  const pkgs = [
    "bash-language-server",
    "bat",
    "bottom",
    "carapace",
    "direnv",
    "duf",
    "eza",
    "fd",
    "fzf",
    "gdu",
    "gh",
    "go-gum",
    "go-shfmt",
    "imagemagick",
    "jq",
    "just",
    "lazygit",
    "mask",
    "nushell",
    "ripgrep",
    "shellcheck",
    "tealdeer",
    "tectonic",
    "television",
    "tmuxp",
    "trash-cli",
    "xh",
    "yazi",
    "zoxide",
  ];
  await $`pixi global install ${pkgs}`.nothrow();
  if (!(await hasCmd("tmux"))) await $`pixi global install tmux`.nothrow();
  await $`tldr --update`.nothrow().quiet();
}

async function installBrewFonts(): Promise<void> {
  if (!(await hasCmd("brew"))) await installBrew();
  if (!(await hasCmd("brew"))) {
    log.error("brew not installed, cannot install fonts");
    return;
  }
  await $`brew install --cask font-jetbrains-mono-nerd-font font-fontawesome`;
}

async function installBrew(): Promise<void> {
  if (await hasCmd("brew")) return;
  log.info("Installing brew");
  await $`curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash`;

  const brewBin = (await isMac()) ? "/opt/homebrew/bin" : "/home/linuxbrew/.linuxbrew/bin";
  process.env.PATH = `${brewBin}:${process.env.PATH}`;

  await $`brew tap ublue-os/tap`.nothrow();
  await $`brew install topgrade`.nothrow();
}

async function installParu(): Promise<void> {
  if (await hasCmd("paru")) {
    log.info("paru is already installed");
    return;
  }
  log.info("Installing paru");
  await si(["base-devel"]);
  await $`rm -rf /tmp/paru`.nothrow();
  await $`git clone https://aur.archlinux.org/paru.git /tmp/paru`;
  try {
    await $`makepkg --syncdeps --noconfirm --install`.cwd("/tmp/paru");
  } catch {
    log.warn("Failed to install paru");
  }
  await $`rm -rf /tmp/paru`.nothrow();
}

async function installNix(): Promise<void> {
  if (await hasCmd("nix")) {
    log.info("nix is already installed");
    return;
  }
  log.info("Installing nix...");
  await $`curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate --no-confirm`;
}

async function installHomeManager(): Promise<void> {
  if (!(await hasCmd("nix"))) await installNix();
  log.info("Setting up home-manager");
  const flakePath = path.join(DOT_DIR, "home-manager");
  const user = process.env.USER ?? os.userInfo().username;
  await $`nix run home-manager -- switch --flake ${flakePath}#${user} --impure -b backup`;
}

async function installRust(): Promise<void> {
  if (await hasCmd("rustup")) {
    log.info("rustup is already installed");
    return;
  }
  log.info("Installing rustup...");
  await $`curl -fsSL https://sh.rustup.rs | sh`;
}

async function installNvim(): Promise<void> {
  if (await hasCmd("nvim")) {
    log.info("nvim already installed");
    return;
  }
  if (await hasCmd("pixi")) {
    log.info("Installing neovim with pixi...");
    await $`pixi global install nvim`;
  } else if (await hasCmd("brew")) {
    log.info("Installing neovim with brew...");
    await $`brew install neovim`;
  } else {
    log.error("Cannot install neovim");
  }
}

async function configureNvim(): Promise<void> {
  const nvimConfig = path.join(HOME_DIR, ".config/nvim");
  if (dirExists(nvimConfig)) {
    const ok = await promptYn(
      "Found existing nvim config. Do you want to backup and replace with AstroNvim?",
    );
    if (!ok) return;
  }
  log.info("Setting up AstroNvim...");
  const bak = (p: string) => p + ".bak";
  for (const p of [
    path.join(HOME_DIR, ".config/nvim"),
    path.join(HOME_DIR, ".local/share/nvim"),
    path.join(HOME_DIR, ".local/state/nvim"),
    path.join(HOME_DIR, ".cache/nvim"),
  ]) {
    await $`trash ${bak(p)}`.nothrow().quiet();
    await $`mv ${p} ${bak(p)}`.nothrow().quiet();
  }
  await fs.mkdir(nvimConfig, { recursive: true });
  await $`git clone --depth 1 https://github.com/AstroNvim/template ${nvimConfig}`;
  await $`rm -rf ${path.join(nvimConfig, ".git")}`;
}

async function installBun(): Promise<void> {
  if (await hasCmd("bun")) {
    log.warn("bun already installed. Skipping.");
    return;
  }
  log.info("Installing bun...");
  await $`sh -c "$(curl -fsSL https://bun.com/install)"`;
}

async function installNode(): Promise<void> {
  if (!(await hasCmd("volta"))) {
    log.info("Installing volta...");
    await $`curl -fsSL https://get.volta.sh | bash`;
  }
  log.info("Installing latest node with volta...");
  await $`volta install node@latest`;
}

async function installUv(): Promise<void> {
  if (await hasCmd("uv")) {
    log.info("uv already installed");
  } else {
    log.info("Installing uv...");
    await $`sh -c "$(curl -fsSL https://astral.sh/uv/install.sh)"`;
  }
  if (!(await hasCmd("pipx"))) {
    log.info("Installing pipx with uv...");
    await $`uv tool install pipx`;
  }
}

async function installMise(): Promise<void> {
  if (await hasCmd("mise")) {
    log.info("mise already installed");
    return;
  }
  log.info("Installing mise");
  await $`sh -c "$(curl -fsSL https://mise.run)"`;
}

async function installClaude(): Promise<void> {
  if (await hasCmd("claude")) {
    log.info("claude is already installed");
    return;
  }
  log.info("Installing claude");
  await $`sh -c "$(curl -fsSL https://claude.ai/install.sh)"`;
}

async function installNpmPackages(): Promise<void> {
  if (!(await hasCmd("npm"))) {
    log.error("npm not installed. Run 'node' first.");
    return;
  }
  const npmPkgs = [
    "@google/gemini-cli",
    "@mermaid-js/mermaid-cli",
    "opencode-ai",
    "@openai/codex",
    "typescript",
  ];
  log.info("Installing npm packages");
  for (const pkg of npmPkgs) {
    await $`npm install -g ${pkg}`.nothrow();
  }
}

async function installSystemShell(): Promise<void> {
  await updatePackages();
  let pkgs = ["fish", "gcc", "git", "make", "tar", "tmux", "tree", "unzip", "zstd"];
  if ((await isTumbleweed()) || (await isApt())) pkgs = [...pkgs, "libatomic1"];
  else if ((await isFedora()) || (await isArch())) pkgs = [...pkgs, "libatomic"];
  log.info("Installing system packages");
  await si(pkgs);
  if (await isNonAtomicLinux()) {
    log.info("Updating locate database, this may take a while...");
    await $`sudo updatedb`.nothrow();
  }
}

async function setupDotfiles(): Promise<void> {
  await syncDotfiles();
  await setupNushellConfig();
  await setupFishConfig();
}

async function installDevtools(): Promise<void> {
  await installMise();
  await installUv();
  await installClaude();
  await installNode();
  await installBun();
  await installNpmPackages();
}

async function installSystemDesktop(): Promise<void> {
  await updatePackages();
  log.info("Installing desktop system packages");
  await si(["flatpak", "gnome-keyring", "plocate"]);
}

async function installDistrobox(): Promise<void> {
  log.info("Installing distrobox");
  await si(["podman", "distrobox"]);
}

async function installFlatpaks(): Promise<void> {
  if (!(await hasCmd("flatpak"))) await si(["flatpak"]);
  log.info("Adding flathub remote");
  await $`flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo --user`.nothrow();
  const flatpaks = [
    "com.github.tchx84.Flatseal",
    "md.obsidian.Obsidian",
    "org.gnome.Firmware",
    "org.gnome.Papers",
    "app.zen_browser.zen",
  ];
  log.info("Installing flatpaks...");
  for (const pkg of flatpaks) {
    log.info(`Installing ${pkg}`);
    await $`flatpak --user install -y flathub ${pkg}`.nothrow();
  }
}

async function installWmBase(): Promise<void> {
  let pkgs = [
    "grim",
    "gvfs",
    "imv",
    "kitty",
    "mate-polkit",
    "mpv",
    "nautilus",
    "pipewire",
    "pipewire-pulse",
    "qt5ct",
    "qt6ct",
    "slurp",
    "udiskie",
    "udisks2",
    "wireplumber",
    "wl-clipboard",
    "xdg-desktop-portal-gnome",
    "xdg-desktop-portal-gtk",
    "xdg-desktop-portal-wlr",
  ];
  if (await isApt())
    pkgs = [
      ...pkgs,
      "bibata-cursor-theme",
      "cliphist",
      "gvfs-backends",
      "gvfs-fuse",
      "libsecret-tools",
    ];
  if (await isFedora())
    pkgs = [...pkgs, "adw-gtk3-theme", "cups-pk-helper", "gvfs-fuse", "gvfs-smb", "libsecret"];
  if (await isTumbleweed())
    pkgs = [
      ...pkgs,
      "cliphist",
      "git-credential-libsecret",
      "gtk3-metatheme-adwaita",
      "gvfs-backend-samba",
      "gvfs-fuse",
      "libsecret-1-0",
      "pipewire-pulseaudio",
    ];
  if (await isArch())
    pkgs = [
      ...pkgs,
      "adw-gtk-theme",
      "cava",
      "cliphist",
      "cups-pk-helper",
      "gvfs-smb",
      "kimageformats",
      "libsecret",
      "matugen",
    ];

  await si(pkgs);

  if (await isArch()) {
    await installParu();
    await $`paru -S bibata-cursor-theme`.nothrow();
  }

  await installBrewFonts();

  if (await hasCmd("pipx")) {
    log.info("Installing pywal packages");
    await $`pipx install pywal`.nothrow();
    await $`pipx install pywalfox`.nothrow();
  }

  const pictures = path.join(HOME_DIR, "Pictures");
  await fs.mkdir(path.join(pictures, "Screenshots"), { recursive: true }).catch(() => {});
  await fs.mkdir(path.join(pictures, "Wallpapers"), { recursive: true }).catch(() => {});

  await stowPackage("systemd");
  await stowPackage("kitty");
  await stowPackage("xdg");
}

async function installNiriWm(): Promise<void> {
  await installWmBase();
  if ((await hasCmd("dms")) && (await hasCmd("niri"))) {
    log.info("niri and dms are already installed");
    return;
  }
  log.info("Installing niri");
  if (await isPikaos()) {
    await $`pikman install pika-niri-desktop-minimal pika-niri-settings dms`;
  } else if (await isFedora()) {
    await $`sudo dnf copr enable avengemedia/dms`;
    await si(["niri", "dms", "cliphist"]);
  } else if (await isQuesting()) {
    await $`sudo add-apt-repository ppa:avengemedia/danklinux`;
    await $`sudo add-apt-repository ppa:avengemedia/dms`;
    await $`sudo apt update`;
    await si(["niri", "dms"]);
  } else if (await isTumbleweed()) {
    await $`sudo zypper addrepo https://download.opensuse.org/repositories/home:/AvengeMedia:/dms/openSUSE_Tumbleweed/home:AvengeMedia:dms.repo`;
    await $`sudo zypper refresh`;
    await si(["niri", "dms"]);
  } else if (await isArch()) {
    await $`paru -S niri dms-shell-bin`;
  } else {
    log.error("OS not supported. Not installing niri.");
  }
}

async function configureNiriWm(): Promise<void> {
  if ((await isCachy()) && !(await hasCmd("niri"))) {
    log.error("Use the niri edition of CachyOS instead of this one.");
    return;
  }
  await stowPackage("niri");
  const niriDms = path.join(HOME_DIR, ".config/niri/dms");
  await touchFiles(niriDms, [
    "alttab.kdl",
    "colors.kdl",
    "layout.kdl",
    "wpblur.kdl",
    "binds.kdl",
    "cursor.kdl",
    "outputs.kdl",
  ]);
  await $`systemctl --user add-wants niri.service dms`.nothrow();
}

async function installNiri(): Promise<void> {
  await installNiriWm();
  await configureNiriWm();
}

async function installMangoWc(): Promise<void> {
  await installWmBase();
  if ((await hasCmd("dms")) && (await hasCmd("mango"))) {
    log.info("mangowc and dms are already installed");
    return;
  }
  log.info("Installing mangowc");
  if (await isPikaos()) {
    await $`pikman install mangowc`;
  } else if (await isArch()) {
    await $`paru -S mangowc-git dms-shell-bin`;
  } else if (await isFedora()) {
    const ok = await promptYn(
      "Need terra repository for installing mango. This is NOT stable. Still enable it?",
    );
    if (ok) {
      await $`sudo dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release`;
      await $`sudo dnf copr enable avengemedia/dms`;
      await si(["mangowc", "dms"]);
    }
  } else {
    log.error("Unsupported OS. Not installing mangowc.");
  }
}

async function configureMangoWc(): Promise<void> {
  await stowPackage("mango");
  await stowPackage("systemd");
  const mangoDms = path.join(HOME_DIR, ".config/mango/dms");
  await touchFiles(mangoDms, [
    "alttab.conf",
    "colors.conf",
    "layout.conf",
    "wpblur.conf",
    "binds.conf",
    "cursor.conf",
    "outputs.conf",
  ]);
}

async function installMango(): Promise<void> {
  await installMangoWc();
  await configureMangoWc();
}

async function installVirtManager(): Promise<void> {
  log.info("Installing virt-manager");
  if (!(await isArch())) log.warn("OS other than Arch is not tested for virt-manager");

  let packages = ["virt-install", "virt-manager", "virt-viewer"];
  if ((await isFedora()) || (await isTumbleweed())) packages = [...packages, "libvirt-nss"];
  if ((await isFedora()) || (await isArch()) || (await isTumbleweed()))
    packages = [...packages, "dnsmasq", "libvirt", "qemu-img", "qemu-tools", "swtpm"];
  if (await isTumbleweed())
    packages = [...packages, "qemu", "qemu-x86", "qemu-ui-gtk", "qemu-ui-opengl"];
  if (await isArch())
    packages = [
      ...packages,
      "openbsd-netcat",
      "qemu-full",
      "qemu-hw-display-virtio-gpu",
      "qemu-hw-display-virtio-gpu-gl",
    ];

  await si(packages);
}

async function configureVirt(): Promise<void> {
  log.info("Setting up libvirt");
  for (const group of ["libvirt", "qemu", "libvirt-qemu", "kvm", "libvirtd"]) {
    await $`sudo usermod -aG ${group} ${process.env.USER}`.nothrow();
  }
  await $`sudo systemctl enable --now libvirtd`.nothrow();
  await $`sudo systemctl enable --now libvirtd.socket`.nothrow();
  await $`sudo virsh net-autostart default`.nothrow();
  if (await hasCmd("authselect")) {
    await $`sudo authselect enable-feature with-libvirt`.nothrow();
  }
}

async function installVirt(): Promise<void> {
  await installVirtManager();
  await configureVirt();
}

async function installZed(): Promise<void> {
  if (!(await hasCmd("zed"))) {
    log.info("Installing zed");
    await $`sh -c "$(curl -fsSL https://zed.dev/install.sh)"`;
  }
  await installBrewFonts();
}

type Task = {
  description: string;
  handler: () => Promise<void>;
};

async function multiTask(items: Task[]): Promise<void> {
  const descriptions = items.map((t) => t.description).join("\n");
  const result = await $`echo ${descriptions} | gum choose --no-limit`.nothrow().text();

  const selected = result
    .trim()
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);

  if (selected.length === 0) {
    log.info("No tasks selected.");
    return;
  }

  for (const desc of selected) {
    const item = items.find((t) => t.description === desc);
    if (!item) continue;
    log.info(`Executing: ${item.description}`);
    try {
      await item.handler();
    } catch (err) {
      log.error(`${item.description} failed: ${(err as Error).message}`);
    }
  }
}

async function setupShell(): Promise<void> {
  const p = await getPlatform();
  if (p === "unsupported" || p === "mac") {
    die("Only Fedora, Questing, Tumbleweed, Arch, PikaOS, and Fedora Atomic supported. Quitting.");
  }

  const tasks: Task[] = [];

  if (await isNonAtomicLinux()) {
    tasks.push({ description: "Install system packages (required)", handler: installSystemShell });
  }

  tasks.push(
    {
      description: "Install shell tools (pixi + brew)",
      handler: async () => {
        await installPixi();
        await installPixiPackages();
        await installBrew();
      },
    },
    { description: "Setup dotfiles with stow", handler: setupDotfiles },
    { description: "Install devtools (mise/node/uv/bun/claude)", handler: installDevtools },
    {
      description: "Install Neovim + AstroNvim",
      handler: async () => {
        await installNvim();
        await configureNvim();
      },
    },
    { description: "Install rustup", handler: installRust },
  );

  if (!(await isFedoraAtomic())) {
    tasks.push({ description: "Install nix", handler: installNix });
    tasks.push({ description: "Setup home-manager", handler: installHomeManager });
  }

  await multiTask(tasks);
}

async function setupDesktop(): Promise<void> {
  if (await isMac()) die("desktop option is not available for mac");

  const tasks: Task[] = [];

  if (!(await isFedoraAtomic())) {
    tasks.push(
      { description: "Install system packages (required)", handler: installSystemDesktop },
      { description: "Install distrobox", handler: installDistrobox },
      { description: "Install virt-manager", handler: installVirt },
    );
  }

  tasks.push(
    { description: "Install flatpaks", handler: installFlatpaks },
    { description: "Install zed", handler: installZed },
  );

  if (
    (await isFedora()) ||
    (await isQuesting()) ||
    (await isPikaos()) ||
    (await isTumbleweed()) ||
    (await isArch())
  ) {
    tasks.push({ description: "Install niri WM", handler: installNiri });
  }

  if ((await isFedora()) || (await isPikaos()) || (await isArch())) {
    tasks.push({ description: "Install mangowc WM", handler: installMango });
  }

  await multiTask(tasks);
}

function printHelp(): void {
  console.log(`
setup.ts - Linux system setup script (TypeScript/Bun)

Usage:
  bun setup.ts [command]

Top-level commands:
  shell          Interactive shell environment setup
  desktop        Interactive desktop environment setup
  (no args)      Run both shell and desktop setup

Shell commands:
  system-shell   Install system packages for shell
  pixi           Install pixi package manager
  pixi-pkgs      Install pixi packages
  brew           Install Homebrew
  dotfiles       Sync dotfiles and apply configs
  fish-config    Stow fish config and set as default shell
  nu-config      Stow nushell config
  devtools       Install mise, uv, node, bun, claude, npm pkgs
  nvim           Install and configure AstroNvim
  rust           Install rustup
  nix            Install nix
  home-manager   Setup home-manager with nix

Desktop commands:
  system-desktop  Install desktop system packages
  distrobox       Install distrobox + podman
  flatpaks        Install flatpak apps
  fonts           Install fonts via brew cask
  zed             Install zed editor + fonts
  virt            Install and configure virt-manager/libvirt
  niri            Install and configure niri WM
  mangowc         Install and configure mangowc WM

Supported Systems:
  Fedora (standard and atomic), Debian Trixie, Ubuntu Questing,
  openSUSE Tumbleweed, Arch Linux, CachyOS, PikaOS
`);
}

async function main(): Promise<number> {
  setEnv();

  const args = process.argv.slice(2);
  const cmd = args[0];

  const timer = await keepSudoAlive();
  try {
    switch (cmd) {
      case "shell":
        await setupShell();
        break;
      case "system-shell":
        await installSystemShell();
        break;
      case "pixi":
        await installPixi();
        break;
      case "pixi-pkgs":
        await installPixiPackages();
        break;
      case "brew":
        await installBrew();
        break;
      case "dotfiles":
        await setupDotfiles();
        break;
      case "fish-config":
        await setupFishConfig();
        break;
      case "nu-config":
        await setupNushellConfig();
        break;
      case "devtools":
        await installDevtools();
        break;
      case "nvim":
        await installNvim();
        await configureNvim();
        break;
      case "rust":
        await installRust();
        break;
      case "nix":
        await installNix();
        break;
      case "home-manager":
        await installHomeManager();
        break;
      case "bun":
        await installBun();
        break;
      case "node":
        await installNode();
        break;
      case "uv":
        await installUv();
        break;
      case "mise":
        await installMise();
        break;
      case "claude":
        await installClaude();
        break;
      case "npm-pkgs":
        await installNpmPackages();
        break;
      case "desktop":
        await setupDesktop();
        break;
      case "system-desktop":
        await installSystemDesktop();
        break;
      case "distrobox":
        await installDistrobox();
        break;
      case "flatpaks":
        await installFlatpaks();
        break;
      case "fonts":
        await installBrewFonts();
        break;
      case "zed":
        await installZed();
        break;
      case "virt":
        await installVirt();
        break;
      case "niri":
        await installNiri();
        break;
      case "mangowc":
        await installMango();
        break;
      case "stow":
        if (!args[1]) {
          log.error("Usage: bun setup.ts stow <package>");
          return 1;
        }
        await stowPackage(args[1]);
        break;
      case undefined:
      case "all":
        await setupShell();
        await setupDesktop();
        break;
      case "help":
      case "--help":
      case "-h":
        printHelp();
        break;
      default:
        log.error(`Unknown command: ${cmd}`);
        printHelp();
        return 1;
    }
  } catch (err) {
    log.error((err as Error).message);
    return 1;
  } finally {
    stopSudoAlive(timer);
  }

  return 0;
}

main().then((code) => process.exit(code));
