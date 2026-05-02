#!/usr/bin/env nu

let ws = (niri msg -j workspaces | from json | where is_focused | get id | first)

let wins = (
    niri msg -j windows
    | from json
    | where workspace_id == $ws and is_floating == false
)

let count = ($wins | length)

if $count > 0 {
    let w = ((100 / $count) | math round --precision 4)
    $wins | each {|it|
        niri msg action focus-window --id $it.id
        niri msg action set-column-width $"($w)%"
    }
}
