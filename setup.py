#!/usr/bin/env python3
# pyright: strict

from __future__ import annotations

import argparse
import logging
import os
import shutil
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from http.client import HTTPResponse
from typing import Final, Literal, NoReturn, TextIO, cast
from urllib.error import URLError
from urllib.request import urlopen

Target = Literal["shell", "desktop"]
Platform = Literal[
    "ublue",
    "fedora",
    "trixie",
    "questing",
    "pikaos",
    "tumbleweed",
    "arch",
    "fedora-atomic",
    "unsupported",
]

DEFAULT_REPO_URL: Final[str] = "https://github.com/pervezfunctor/linux-config.git"
DEFAULT_TARGETS: Final[tuple[Target, ...]] = ("shell", "desktop")
LOGGER: Final[logging.Logger] = logging.getLogger("linux-config.setup")
LEVEL_COLORS: Final[dict[int, str]] = {
    logging.INFO: "32",
    logging.WARNING: "33",
    logging.ERROR: "31",
}


@dataclass(frozen=True)
class Config:
    home_dir: Path
    dot_dir: Path
    repo_url: str


def read_file(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def configure_logger() -> None:
    LOGGER.handlers.clear()
    LOGGER.setLevel(logging.INFO)
    LOGGER.propagate = False

    formatter = logging.Formatter("%(message)s")

    stdout_handler = logging.StreamHandler(sys.stdout)
    stdout_handler.setLevel(logging.INFO)
    stdout_handler.setFormatter(formatter)
    stdout_handler.addFilter(lambda record: record.levelno < logging.WARNING)

    stderr_handler = logging.StreamHandler(sys.stderr)
    stderr_handler.setLevel(logging.WARNING)
    stderr_handler.setFormatter(formatter)

    LOGGER.addHandler(stdout_handler)
    LOGGER.addHandler(stderr_handler)


def format_level(level: int, name: str, stream: TextIO) -> str:
    color = LEVEL_COLORS.get(level)
    if color is None or os.environ.get("NO_COLOR") or not stream.isatty():
        return name
    return f"\033[{color}m{name}\033[0m"


def log(message: str) -> None:
    LOGGER.info(f"{format_level(logging.INFO, 'INFO', sys.stdout)} {message}")


def warn(message: str) -> None:
    LOGGER.warning(f"{format_level(logging.WARNING, 'WARN', sys.stderr)} {message}")


def error(message: str) -> None:
    LOGGER.error(f"{format_level(logging.ERROR, 'ERROR', sys.stderr)} {message}")


def die(message: str) -> NoReturn:
    error(message)
    raise SystemExit(1)


def parse_os_release(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        value = raw_value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        values[key.upper()] = value.lower()
    return values


def current_os(runner: CommandRunner, release_dir: Path | None = None) -> Platform:
    release_dir = Path("/etc") if release_dir is None else release_dir
    redhat_release = read_file(release_dir / "redhat-release").strip().lower()
    os_release = parse_os_release(read_file(release_dir / "os-release"))
    codename = os_release.get("VERSION_CODENAME", "")
    release_text = " ".join(
        os_release.get(key, "")
        for key in ("ID", "ID_LIKE", "VERSION_CODENAME", "NAME", "PRETTY_NAME")
    )
    has_rpm_ostree = runner.has_cmd("rpm-ostree")
    if has_rpm_ostree and runner.has_cmd("ujust"):
        return "ublue"
    if not has_rpm_ostree and "fedora" in redhat_release:
        return "fedora"
    if codename == "trixie":
        return "trixie"
    if codename == "questing":
        return "questing"
    if "tumbleweed" in release_text:
        return "tumbleweed"
    if "pika" in release_text:
        return "pikaos"
    if "arch" in release_text:
        return "arch"
    if has_rpm_ostree:
        return "fedora-atomic"
    return "unsupported"


def prepend_path(existing_path: str, entries: Sequence[str]) -> str:
    prefix = ":".join(entry for entry in entries if entry)
    if prefix and existing_path:
        return f"{prefix}:{existing_path}"
    return prefix or existing_path


class CommandRunner:
    def __init__(self, config: Config) -> None:
        super().__init__()
        env = dict(os.environ)
        pnpm_home = config.home_dir / ".local/share/pnpm"
        env["PNPM_HOME"] = str(pnpm_home)
        env["PATH"] = prepend_path(
            env.get("PATH", ""),
            [
                str(config.home_dir / "bin"),
                str(config.home_dir / ".local/bin"),
                str(config.home_dir / ".cargo/bin"),
                str(pnpm_home),
                ".local/share/mise/shims",
                "/home/linuxbrew/.linuxbrew/bin",
                str(config.dot_dir / "bin"),
                str(config.dot_dir / "nu"),
                str(config.home_dir / ".pixi/bin"),
                ".volta/bin",
            ],
        )
        self.env: dict[str, str] = env

    def has_cmd(self, *commands: str) -> bool:
        return all(
            shutil.which(command, path=self.env.get("PATH")) is not None
            for command in commands
        )

    def check_cmd(self, *commands: str) -> None:
        for command in commands:
            if not self.has_cmd(command):
                die(f"{command} not installed. Quitting.")

    def exec(
        self,
        command: Sequence[str],
        *,
        check: bool = True,
        input: bytes | None = None,
        cwd: Path | str | None = None,
    ) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(command, env=self.env, check=check, input=input, cwd=cwd)

    def exec_quiet(
        self,
        command: Sequence[str],
        *,
        check: bool = True,
        cwd: Path | str | None = None,
    ) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            command,
            env=self.env,
            check=check,
            cwd=cwd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def exec_capture(
        self,
        command: Sequence[str],
        *,
        check: bool = True,
        cwd: Path | str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            env=self.env,
            check=check,
            cwd=cwd,
            capture_output=True,
            text=True,
        )


def run_setup(config: Config, targets: Sequence[Target]) -> None:
    runner = CommandRunner(config)
    platform = current_os(runner)
    shell_setup = str(config.dot_dir / "nu/setup-shell.nu")
    desktop_setup = str(config.dot_dir / "nu/setup-desktop.nu")

    def si(packages: Sequence[str]) -> None:
        joined = " ".join(packages)
        log(f"Installing {joined}")
        if platform == "ublue":
            command = ["brew", "install", *packages]
        elif platform == "fedora":
            command = ["sudo", "dnf", "install", "-y", *packages]
        elif platform in {"trixie", "questing"}:
            command = ["sudo", "apt", "install", "-y", *packages]
        elif platform == "pikaos":
            command = ["pikman", "install", *packages]
        elif platform == "tumbleweed":
            command = [
                "sudo",
                "zypper",
                "--non-interactive",
                "--quiet",
                "install",
                "--auto-agree-with-licenses",
                *packages,
            ]
        elif platform == "arch":
            command = ["sudo", "pacman", "-S", "--quiet", "--noconfirm", *packages]
        else:
            warn(f"OS not supported. Not installing {joined}.")
            raise subprocess.CalledProcessError(
                returncode=1, cmd=["install", *packages]
            )
        _ = runner.exec(command)

    def update_packages() -> None:
        log("Updating packages")
        commands: list[list[str]] = []
        if platform == "ublue":
            commands = [["brew", "update"], ["brew", "upgrade"]]
        elif platform == "fedora":
            commands = [["sudo", "dnf", "update", "-y"]]
        elif platform in {"trixie", "questing"}:
            commands = [["sudo", "apt", "update"], ["sudo", "apt", "upgrade", "-y"]]
        elif platform == "pikaos":
            commands = [["pikman", "update"], ["pikman", "upgrade"]]
        elif platform == "tumbleweed":
            commands = [["sudo", "zypper", "refresh"], ["sudo", "zypper", "update"]]
        elif platform == "arch":
            commands = [["sudo", "pacman", "-Syyu"], ["sudo", "pacman", "-Fy"]]
        if not commands:
            warn("OS not supported. Not Updating.")
            return
        for command in commands:
            _ = runner.exec(command)

    def install_pixi() -> None:
        log("Installing pixi and essential packages...")
        if not runner.has_cmd("pixi"):
            with cast(HTTPResponse, urlopen("https://pixi.sh/install.sh")) as response:
                script = response.read()
            _ = runner.exec(["/bin/sh"], input=script)
        runner.check_cmd("pixi")

    def sync_dotfiles() -> None:
        git_dir = config.dot_dir / ".git"
        if not git_dir.is_dir():
            log("Cloning dotfiles")
            _ = runner.exec(
                ["git", "clone", "--depth", "1", config.repo_url, str(config.dot_dir)]
            )
            return

        if runner.exec_capture(
            ["git", "status", "--porcelain=v1"], cwd=config.dot_dir
        ).stdout.strip():
            die(
                "Dotfiles repo has local changes. Stash them and run this script again."
            )

        log("Dotfiles repo clean. Pulling latest changes")
        if (
            runner.exec(
                ["git", "pull", "--rebase", "--stat"], cwd=config.dot_dir, check=False
            ).returncode
            == 0
        ):
            log("Dotfiles updated")
            return

        warn("git pull --rebase failed. Checking for in-progress rebase...")
        if (git_dir / "rebase-merge").is_dir() or (git_dir / "rebase-apply").is_dir():
            warn("Aborting rebase")
            result = runner.exec_quiet(
                ["git", "rebase", "--abort"], cwd=config.dot_dir, check=False
            )
            if result.returncode == 0:
                log("Rebase aborted successfully")
            else:
                warn("Failed to abort rebase")

        raise SystemExit(1)

    def install_pixi_packages() -> None:
        result = runner.exec(
            [
                "pixi",
                "global",
                "install",
                "nushell",
                "trash-cli",
                "go-gum",
                "starship",
                "gh",
            ]
        )
        if result.returncode != 0:
            warn("pixi install failed. Quitting.")

        runner.check_cmd("nu", "trash", "starship", "gh")

    def install_packages() -> None:
        log("Installing required packages...")
        for pkg in ("curl", "git", "fish"):
            if not runner.has_cmd(pkg):
                si([pkg])
                runner.check_cmd(pkg)

    if platform == "unsupported":
        die(
            "Only Fedora, Ubuntu Questing, Tumbleweed, Arch, Debian Trixie and PikaOS supported. Quitting."
        )

    update_packages()
    install_packages()

    install_pixi()
    install_pixi_packages()

    sync_dotfiles()

    _ = runner.exec(["nu", shell_setup, "fish", "config"])
    for target in targets:
        if target == "shell":
            _ = runner.exec(["nu", shell_setup])
        else:
            _ = runner.exec(["nu", desktop_setup])


def parse_cli_args(argv: Sequence[str]) -> list[Target]:
    parser = argparse.ArgumentParser(description="Linux workstation setup bootstrapper")
    _ = parser.add_argument(
        "targets",
        nargs="*",
        choices=list(DEFAULT_TARGETS),
        help="Defaults to: shell desktop",
    )
    namespace = parser.parse_args(list(argv))
    raw_targets = cast(list[Target], namespace.targets)
    return list(dict.fromkeys(raw_targets or list(DEFAULT_TARGETS)))


def main(argv: Sequence[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else list(argv)
    configure_logger()

    home_dir = Path.home()

    config = Config(
        home_dir=home_dir,
        dot_dir=home_dir / ".local/share/linux-config",
        repo_url=DEFAULT_REPO_URL,
    )

    try:
        run_setup(config, parse_cli_args(args))
    except subprocess.CalledProcessError as exc:
        error(str(exc))
        return exc.returncode or 1
    except URLError as exc:
        error(f"Network request failed: {exc.reason}")
        return 1
    except KeyboardInterrupt:
        error("Interrupted")
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
