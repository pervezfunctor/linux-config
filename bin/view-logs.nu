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
        ls $"($log_dir)/*.log" | sort-by modified -r
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

def display-log [file_path: string] {
    let file_name = ($file_path | path basename)
    print $"==== ($file_name) ===="

    if (which less | is-empty) {
        open --raw $file_path | print
    } else {
        ^less -R $file_path
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

def "main show" [
    --dir: string
    --timestamp (-t): string
    --select (-s)
] {
    let log_dir = (get-log-dir $dir)
    let logs = try {
        load-logs $log_dir
    } catch {
        return
    }

    let target = if $select {
        select-interactively $logs
    } else if $timestamp != null {
        find-log-by-timestamp $logs $timestamp
    } else {
        $logs | first
    }

    if $target != null {
        display-log $target.name
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
    print "  -s, --select             Interactively choose a log by timestamp or index."
    print ""
    print $"By default logs are read from ($default_dir)."
    print "Override with the LINUX_CONFIG_LOG_DIR environment variable or the --dir flag."
}
