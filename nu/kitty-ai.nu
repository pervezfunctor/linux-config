#!/usr/bin/env nu

def main [
    config?: string
] {

    let config_file = (
        if ($config | is-empty) { "terminals.json" } else { $config }
        | path expand
    )

    let entries = open $config_file

    for entry in $entries {
        let cwd = ($entry.cwd | path expand)
        let cmd = $entry.cmd

        ^bash -c $"nohup kitty bash -lc 'cd ($cwd) && ($cmd); exec $SHELL' >/dev/null 2>&1 &"
    }
}
