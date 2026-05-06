#!/usr/bin/env nu

def main [] {
    let ws_map = niri msg --json workspaces
        | from json
        | select id idx
        | rename workspace_id ws_idx

    let windows = niri msg --json windows
        | from json
        | select id title app_id workspace_id is_focused
        | join $ws_map workspace_id

    if ($windows | is-empty) { return }

    let choice = $windows
        | each {|w|
            let indicator = if $w.is_focused { " *" } else { "" }
            $"($w.ws_idx): ($w.app_id) — ($w.title)($indicator)\t($w.id)"
        }
        | str join "\n"

    let selection = ($choice | fuzzel --dmenu --index --anchor top  --y-margin 200 --placeholder "Switch to window" --prompt "❯ " --lines 5 --width 60 --match-mode fzf | into int)

    if $selection == -1 { return }

    let target_id = $windows | get $selection | get id
    niri msg action focus-window --id $target_id
}
