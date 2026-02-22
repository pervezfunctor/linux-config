#!/usr/bin/env nu

use ../nu/lib.nu [has-cmd]

def show-help [] {
    print $"Usage: sudo-warm <tool> [args...]

Keeps sudo timestamp refreshed in background, then launches an AI tool.
On first run, you'll be prompted for your sudo password. Subsequent
sudo commands work without re-prompting until the timeout (~5 min).

Arguments:
  tool    AI tool to launch: opencode, kilo, or claude
  args    Arguments to pass to the tool

Examples:
  sudo-warm opencode
  sudo-warm opencode --help
  sudo-warm kilo \"fix the bug in foo.py\"
  sudo-warm claude \"explain this code\"
"
}

export def keep-sudo-alive []: nothing -> int {
    ^sudo -v
    job spawn {
        loop {
            ^sudo -n true
            sleep 55sec
        }
    }
}

export def stop-sudo-alive [job_id: int] {
    do -i {
        job kill $job_id
        ^sudo -k
    }
}

def main [tool: string, ...args: string] {
    if $tool in ["-h" "--help"] {
        show-help
        return
    }

    if $tool not-in ["opencode" "kilo" "claude"] {
        print $"Usage: sudo-warm <opencode|kilo|claude> [args...]" (ansi reset)
        exit 1
    }

    if not (has-cmd "sudo") {
        print $"Error: sudo not found" (ansi reset)
        exit 1
    }

    let job_id = (keep-sudo-alive)

    try {
        ^$tool ...$args
    } catch {
        stop-sudo-alive $job_id
        exit $env.LAST_EXIT_CODE
    }

    stop-sudo-alive $job_id
}
