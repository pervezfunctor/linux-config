#!/usr/bin/env nu

def get-log-dir [
    dir?: string
] {
    if $dir != null {
        $dir
    } else {
        $env.LINUX_CONFIG_LOG_DIR? | default $"($env.HOME)/.linux-config-logs"
    }
}

def load-logs [
    dir: string
] {
    let log_dir = ($dir | path expand)
    if not ($log_dir | path exists) {
        try { mkdir $log_dir } catch { }
    }

    let logs = try {
        glob ($log_dir | path join "*.log") | each { |f| ls $f } | flatten | sort-by modified -r
    } catch {
        []
    }

    if ($logs | is-empty) {
        print -e $"No log files found in ($log_dir)"
        print -e "Run bootstrap or specify a different directory with --dir or LINUX_CONFIG_LOG_DIR."
        error make {
            msg: "No logs found"
        }
    }

    $logs
}

def "main clean" [
    --dir: string
] {
    let log_dir = (get-log-dir $dir)
    let logs = try {
        load-logs $log_dir
    } catch {
        return
    }

    let keep_file = ($logs | first)

    if ($logs | length) <= 1 {
        let name = ($keep_file.name | path basename)
        print $"Only one log present \(($name)\); nothing to clean."
        return
    }

    let to_remove = ($logs | skip 1)
    for log in $to_remove {
        rm -f $log.name
    }

    let name = ($keep_file.name | path basename)
    print $"Kept ($name); removed ($to_remove | length) older log\(s\)."
}

def display-log [file_path: string, level: string, pattern: string] {
    let file_name = ($file_path | path basename)
    print $"==== ($file_name) ===="

    let content = open --raw $file_path

    let level_filtered = if $level == "all" {
        $content
    } else {
        $content | lines | where { |line| $line | str upcase | str contains $"[($level | str upcase)]" } | str join "\n"
    }

    let filtered = if $pattern == "" or $pattern == ".*" {
        $level_filtered
    } else {
        $level_filtered | lines | where { |line| $line =~ $pattern } | str join "\n"
    }

    if ($filtered | is-empty) {
        let level_msg = if $level == "all" { "" } else { $" level='($level)'" }
        let pattern_msg = if $pattern == "" or $pattern == ".*" { "" } else { $" pattern='($pattern)'" }
        print $"No lines found matching filters:($level_msg)($pattern_msg)"
        print "Try: --level all --pattern '.*' to show all lines"
        return
    }

    if (which less | is-empty) {
        print $filtered
    } else {
        $filtered | ^less -R
    }
}

def find-log-by-timestamp [logs: list<record>, timestamp: string] {
    let matched = ($logs | where { |it| ($it.name | path basename) | str contains $timestamp })
    if ($matched | is-empty) {
        print -e $"No log found matching timestamp: ($timestamp)"
        return null
    }
    $matched | first
}

def select-interactively [logs: list<record>] {
    print "Available log files:"
    let indexed_logs = ($logs | enumerate)
    for idx_log in $indexed_logs {
        let idx = $idx_log.index + 1
        let name = ($idx_log.item.name | path basename)
        let padded_idx = ($idx | into string | fill -a right -w 2)
        print $"  ($padded_idx)\) ($name)"
    }

    let choice = (input "Select log by number or timestamp (default=1): " | str trim)
    if ($choice | is-empty) {
        $logs | first
    } else if ($choice =~ '^[0-9]+$') {
        let selection = ($choice | into int) - 1
        if $selection < 0 or $selection >= ($logs | length) {
            print -e $"Invalid selection: ($choice)"
            return null
        }
        $logs | get $selection
    } else {
        find-log-by-timestamp $logs $choice
    }
}

def pick-log-with-gum [logs: list<record>] {
    if (which gum | is-empty) {
        print -e "gum is not installed. Falling back to --select behavior."
        return (select-interactively $logs)
    }

    let choices = ($logs | each { |log|
        let name = ($log.name | path basename)
        let size = ($log.size | into string)
        let modified = ($log.modified | format date "%Y-%m-%d %H:%M:%S")
        $"($name)\t($modified)\t($size)"
    })

    let selected = ($choices | str join "\n" | ^gum choose --header "Select a log file:")

    if ($selected | is-empty) {
        return null
    }

    let selected_name = ($selected | split row "\t" | first)
    $logs | where { |it| ($it.name | path basename) == $selected_name } | first
}

def "main show" [
    --dir: string
    --timestamp (-t): string
    --select (-s)
    --pick-log (-g)
    --level (-l): string = "all"
    --pattern (-p): string = ".*"
] {
    let valid_levels = ["all" "info" "error" "warning" "warn" "debug" "trace"]
    if not (($level | str downcase) in $valid_levels) {
        print -e $"Invalid level: ($level). Valid levels are: ($valid_levels | str join ', ')"
        return
    }

    let log_dir = (get-log-dir $dir)
    let logs = try {
        load-logs $log_dir
    } catch {
        return
    }

    let target = if $pick_log {
        pick-log-with-gum $logs
    } else if $select {
        select-interactively $logs
    } else if $timestamp != null {
        find-log-by-timestamp $logs $timestamp
    } else {
        $logs | first
    }

    if $target != null {
        display-log $target.name ($level | str downcase) $pattern
    }
}

def main [
    --dir: string
] {
    let default_dir = ($env.LINUX_CONFIG_LOG_DIR? | default $"($env.HOME)/.linux-config-logs")
    print "Usage: logs <command> [options]"
    print ""
    print "Commands:"
    print "  clean             Remove all log files except the most recent one."
    print "  show [options]    Display log contents. Defaults to the most recent log."
    print ""
    print "Show options:"
    print "  -t, --timestamp <stamp>  Display the log matching the timestamp (YYYYMMDD-HHMMSS)."
    print "  -s, --select             Interactively choose a log by timestamp or index (text-based)."
    print "  -g, --pick-log           Interactively pick a log using gum (requires gum installed)."
    print "  -l, --level <level>      Filter by log level: all, info, error, warning, debug, trace. (default: all)"
    print "  -p, --pattern <regex>    Filter lines by regex pattern. (default: .*) (show all)"
    print ""
    print $"By default logs are read from ($default_dir)."
    print "Override with the LINUX_CONFIG_LOG_DIR environment variable or the --dir flag."
}
