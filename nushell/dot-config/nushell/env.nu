use std/util 'path add'

$env.DOT_DIR = $"($env.HOME)/.local/share/linux-config"

$env.EDITOR = ["code", "--wait"]
$env.VISUAL = ["code", "--wait"]

$env.PNPM_HOME = $"($env.HOME)/.local/share/pnpm"
$env.VOLTA_HOME = ($env.HOME | path join .volta)

path add [
    $"($env.HOME)/.local/share/flatpak/exports/bin",
    $"($env.HOME)/.pixi/bin",
    $"($env.DOT_DIR)/nu/installers"
    $"($env.DOT_DIR)/nu"
    $"($env.HOME)/bin",
    $"($env.HOME)/.local/bin",
    $"($env.VOLTA_HOME)/bin",
    $"($env.PNPM_HOME)",
]

$env.XDG_DATA_DIRS ++= $"($env.HOME)/.local/share/flatpak/exports/share"

const auto_includes = $nu.default-config-dir | path join auto-includes.nu
if not ($auto_includes | path exists) {
    ^$"($nu.default-config-dir | path join nushell-sources.nu)"
}
