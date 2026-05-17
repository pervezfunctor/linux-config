#!/usr/bin/env nu

def main [] {
    let files = glob ($env.FILE_PWD | path join "**/*.nu") --no-dir
    mut has_errors = false

    for f in $files {
        let diag = ^nu --ide-check 1 $f | lines | where { ($in | str contains '"severity":"Error"') }
        if ($diag | is-not-empty) {
            $has_errors = true
            print $"(ansi red)($f)(ansi reset)"
            for d in $diag {
                let span = $d | from json | get span
                let ctx = open --raw $f | str substring ($span.start)..($span.end)
                print $"  (ansi yellow)($span.start)-($span.end)(ansi reset): ($ctx)"
            }
        }
    }

    if not $has_errors {
        print $"(ansi green)All nu files compile clean.(ansi reset)"
    }
}
