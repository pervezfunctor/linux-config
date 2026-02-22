#!/usr/bin/env nu

use std/log

export-env {
    $env.LOG_FILE = $"($env.HOME)/.linux-config-logs/bootstrap-(date now | format date '%m-%d-%H%M%S').log"
}

export def init-log-file [] {
    mkdir ($env.LOG_FILE | path dirname)
}

def file-log [level: string, msg: string] {
    $"(date now | format date '%m-%d %H:%M:%S') [($level)] ($msg)\n"
    | save --append $env.LOG_FILE
}

export def log+ [msg: string] { log info $msg; file-log "INFO" $msg }
export def warn+ [msg: string] { log warning $msg; file-log "WARNING" $msg }
export def error+ [msg: string] { log error $msg; file-log "ERROR" $msg }
export def die [msg: string] {
    log critical $msg
    file-log "CRITICAL" $msg
    error make {
        msg: $msg
        label: {
            text: "fatal error"
            span: (metadata $msg).span
        }
    }
}