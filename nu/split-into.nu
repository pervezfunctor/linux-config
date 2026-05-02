#!/usr/bin/env nu

def main [n: int] {
    let ws = (niri msg -j workspaces | from json | where is_focused | get id | first)

    let wins = (
        niri msg -j windows
        | from json
        | where workspace_id == $ws and is_floating == false
        | sort-by {|w| $w.layout.pos_in_scrolling_layout.0 }
    )

    let count = ($wins | length)
    let take = ([$n $count] | math min)

    if $take > 0 {
        let w = ((100 / $take) | math round --precision 4)
        let head = ($wins | first $take)
        $head | each {|it|
            niri msg action focus-window --id $it.id
            niri msg action set-column-width $"($w)%"
        }
        niri msg action focus-window --id ($head | first | get id)
    }
}
