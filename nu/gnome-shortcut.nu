#!/usr/bin/env nu

# Manage custom keyboard shortcuts in GNOME
#
# Examples:
#   Create a terminal shortcut:
#   > nu gnome-shortcut.nu create "Terminal" -c "ptyxis -s" -s "<Super>Return"
#
#   Create a file manager shortcut:
#   > nu gnome-shortcut.nu create "File Manager" -c "nautilus" -s "<Super>e"
#
#   Create a screenshot shortcut:
#   > nu gnome-shortcut.nu create "Screenshot" -c "gnome-screenshot -i" -s "<Shift><Super>s"
#
#   Create a lock screen shortcut:
#   > nu gnome-shortcut.nu create "Lock Screen" -c "loginctl lock-session" -s "<Super><Ctrl>l"
#
#   List all custom shortcuts:
#   > nu gnome-shortcut.nu list
#
#   Remove a shortcut by name:
#   > nu gnome-shortcut.nu remove -n "Terminal"
#
#   Remove a shortcut interactively (uses fzf):
#   > nu gnome-shortcut.nu remove

const SCHEMA = "org.gnome.settings-daemon.plugins.media-keys"
const BINDING_PREFIX = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"

def "parse-gsettings-list" [input: string] {
    if $input == "@as []" {
        []
    } else {
        $input
            | str replace -a "[" ""
            | str replace -a "]" ""
            | str replace -a "'" ""
            | split row ","
            | each { |s| $s | str trim }
            | where { |s| $s != "" }
    }
}

def "strip-gsettings-quotes" []: string -> string {
    str trim | str replace -a "'" ""
}

def "validate-shortcut" [shortcut: string] {
    let modifiers = ["Super", "Ctrl", "Alt", "Shift", "Meta"]
    let valid_keys = [
        "a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m"
        "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z"
        "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
        "F1" "F2" "F3" "F4" "F5" "F6" "F7" "F8" "F9" "F10" "F11" "F12"
        "Return" "Escape" "Tab" "space" "minus" "equal"
        "bracketleft" "bracketright" "backslash" "semicolon"
        "apostrophe" "grave" "comma" "period" "slash"
        "BackSpace" "Insert" "Delete" "Home" "End" "Page_Up" "Page_Down"
        "Up" "Down" "Left" "Right"
        "KP_0" "KP_1" "KP_2" "KP_3" "KP_4" "KP_5" "KP_6" "KP_7" "KP_8" "KP_9"
        "KP_Add" "KP_Subtract" "KP_Multiply" "KP_Divide"
    ]

    if ($shortcut | is-empty) {
        return "Shortcut cannot be empty"
    }

    let has_modifier = ($modifiers | any { |m| $shortcut | str contains $"<($m)>" })

    let modifier_list = ($modifiers | each { |m| $"<($m)>" } | str join ", ")
    if not $has_modifier {
        return $"Shortcut must contain at least one modifier: ($modifier_list)"
    }

    let key = ($shortcut | str replace -ra '<[^>]+>' '' | str trim)

    if ($key | is-empty) {
        return "Shortcut must have a key after the modifier\(s\)"
    }

    let has_valid_key = ($valid_keys | any { |k| $k == $key })

    if not $has_valid_key {
      return $"Unknown key '($key)'. Use a letter \(a-z\), number \(0-9\), F1-F12, or special key \(Return, Escape, Tab, etc.\)"
    }

    null
}

def "fetch-shortcuts" [] {
    let existing_str = (gsettings get $SCHEMA custom-keybindings | str trim)
    let bindings = (parse-gsettings-list $existing_str)

    if ($bindings | is-empty) {
        return []
    }

    $bindings | each { |binding|
        let path = $"($SCHEMA).custom-keybinding:($binding)"
        {
            name: (gsettings get $path name | strip-gsettings-quotes),
            command: (gsettings get $path command | strip-gsettings-quotes),
            binding: (gsettings get $path binding | strip-gsettings-quotes),
            gpath: $binding,
        }
    }
}

def "main create" [
    name: string              # Display name for the shortcut
    --command (-c): string    # Command to execute
    --shortcut (-s): string   # Keyboard shortcut (e.g., "<Super>t")
] {
    let error = (validate-shortcut $shortcut)
    if $error != null {
        print $"(ansi red)✗(ansi reset) ($error)"
        return
    }

    let existing_str = (gsettings get $SCHEMA custom-keybindings | str trim)
    let existing = (parse-gsettings-list $existing_str)

    let new_index = ($existing | length)
    let new_binding = $"($BINDING_PREFIX)custom($new_index)/"

    let updated_bindings = ($existing | append $new_binding)
    let formatted_list = $"[($updated_bindings | each { |b| $"'($b)'" } | str join ', ')]"

    gsettings set $SCHEMA custom-keybindings $formatted_list
    gsettings set $"($SCHEMA).custom-keybinding:($new_binding)" name $name
    gsettings set $"($SCHEMA).custom-keybinding:($new_binding)" command $command
    gsettings set $"($SCHEMA).custom-keybinding:($new_binding)" binding $shortcut

    print $"(ansi green)✓(ansi reset) Created: ($name) → ($command) [($shortcut)]"
}

def "main list" [] {
    let shortcuts = (fetch-shortcuts)

    if ($shortcuts | is-empty) {
        print "No custom keyboard shortcuts configured."
        return
    }

    $shortcuts | select name command binding | table
}

def "main remove" [
    --name (-n): string    # Name of the shortcut to remove (interactive fzf picker if omitted)
] {
    let shortcuts = (fetch-shortcuts)

    if ($shortcuts | is-empty) {
        print "No custom keyboard shortcuts configured."
        return
    }

    let target = if $name != null {
        let found = ($shortcuts | where { |s| $s.name == $name } | first)
        if $found == null {
            print $"(ansi red)✗(ansi reset) No shortcut named '($name)' found."
            return
        }
        $found
    } else {
        let display = ($shortcuts
            | each { |s| $"($s.name)  ($s.binding)  ($s.command)" }
        )
        let selected = ($display | str join "\n" | fzf --prompt="Remove shortcut: " | str trim)
        if ($selected | is-empty) {
            print "No shortcut selected."
            return
        }
        let selected_name = ($selected | split row " " | first)
        let found = ($shortcuts | where { |s| $s.name == $selected_name } | first)
        $found
    }

    let updated_bindings = ($shortcuts
        | where { |s| $s.gpath != $target.gpath }
        | each { |s| $s.gpath }
    )

    if ($updated_bindings | is-empty) {
        gsettings set $SCHEMA custom-keybindings "@as []"
    } else {
        let formatted_list = $"[($updated_bindings | each { |b| $"'($b)'" } | str join ', ')]"
        gsettings set $SCHEMA custom-keybindings $formatted_list
    }

    let binding_schema = "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
    gsettings reset $"($binding_schema):($target.gpath)" name
    gsettings reset $"($binding_schema):($target.gpath)" command
    gsettings reset $"($binding_schema):($target.gpath)" binding

    print $"(ansi green)✓(ansi reset) Removed: ($target.name) [($target.binding)]"
}

def "main help" [] {
    print "Manage custom keyboard shortcuts in GNOME"
    print ""
    print "Subcommands:"
    print "  create <name> -c <cmd> -s <key>  - Create a new keyboard shortcut"
    print "  list                             - List all custom shortcuts"
    print "  remove [-n <name>]               - Remove a shortcut (interactive if no name given)"
    print "  help                             - Show this help message"
    print ""
    print "Examples:"
    print "  nu gnome-shortcut.nu create \"Terminal\" -c \"ptyxis -s\" -s \"<Super>Return\""
    print "  nu gnome-shortcut.nu create \"File Manager\" -c \"nautilus\" -s \"<Super>e\""
    print "  nu gnome-shortcut.nu create \"Screenshot\" -c \"gnome-screenshot -i\" -s \"<Shift><Super>s\""
    print "  nu gnome-shortcut.nu create \"Lock Screen\" -c \"loginctl lock-session\" -s \"<Super>l\""
    print "  nu gnome-shortcut.nu list"
    print "  nu gnome-shortcut.nu remove -n \"Terminal\""
    print "  nu gnome-shortcut.nu remove"
}

def main [] {
    main help
}
