#!/usr/bin/env nu

def has-secret-tool [] {
    (which secret-tool | is-not-empty)
}

def fail [msg: string] {
    error make { msg: $msg }
}

def json-to-list [json: string] {
    $json | from json | items {|k, v| [$k, ($v | into string)] } | flatten
}

def "main store" [
    --label (-l): string
    --attr (-a): string
] {
    if not (has-secret-tool) { fail "secret-tool not found" }

    let label = if $label == null { "keyring-entry" } else { $label }

    let secret = (^bash -c 'read -rsp "secret: " s; echo "$s"' | str trim)
    if ($secret | is-empty) {
        fail "secret cannot be empty"
    }

    let base = ["store", $"--label=($label)"]
    let cli_args = if $attr != null { $base | append (json-to-list $attr) } else { $base }

    $secret | ^secret-tool ...$cli_args
    print "Stored"
}

def "main get" [
    --attr (-a): string
] {
    if not (has-secret-tool) { fail "secret-tool not found" }
    if $attr == null { fail "--attr is required" }

    let cli_args = (["lookup"] | append (json-to-list $attr))
    let result = (do -i { ^secret-tool ...$cli_args } | str trim)
    if ($result | is-empty) {
        print "(not found)"
    } else {
        print $result
    }
}

def "main search" [
    --attr (-a): string
] {
    if not (has-secret-tool) { fail "secret-tool not found" }
    if $attr == null { fail "--attr is required" }

    let cli_args = (["search", "--all"] | append (json-to-list $attr))
    let result = (do -i { ^secret-tool ...$cli_args } | str trim)
    if ($result | is-empty) {
        print "(none found)"
    } else {
        print $result
    }
}

def "main clear" [
    --attr (-a): string
] {
    if not (has-secret-tool) { fail "secret-tool not found" }
    if $attr == null { fail "--attr is required" }

    let cli_args = (["clear"] | append (json-to-list $attr))
    do -i { ^secret-tool ...$cli_args }
    print "Cleared"
}

def "main list" [] {
    if not (has-secret-tool) { fail "secret-tool not found" }

    let raw = (^secret-tool search --all xdg:schema "org.freedesktop.Secret.Generic" err> /dev/null)
    let entries = ($raw | lines | where ($in | str starts-with "label = ") | parse "label = {name}" | get name)

    if ($entries | is-empty) {
        print "(no entries)"
        return
    }

    $entries | enumerate | each {|it| $"[($it.index)] ($it.item)"} | str join "\n" | print
}

def "main help" [] {
    print "Usage: keyring <command> [flags]

Commands:
  store   Store a secret (hidden prompt)
  get     Lookup stored secret
  search  Find entries matching attributes
  clear   Delete entries matching attributes
  list    List all entries

Flags:
  -l, --label <text>   Label for the entry (store only)
  -a, --attr <json>    Attributes as JSON object (required for get/search/clear)

Examples:
  keyring store -l 'piqbal@truenas' -a '{\"protocol\":\"smb\",\"server\":\"192.168.10.56\",\"user\":\"piqbal\"}'
  keyring get   -a '{\"protocol\":\"smb\",\"server\":\"192.168.10.56\",\"user\":\"piqbal\"}'
  keyring search -a '{\"protocol\":\"smb\"}'
  keyring clear -a '{\"protocol\":\"smb\",\"server\":\"192.168.10.56\"}'
  keyring list"
}

def "main" [] {
    if not (has-secret-tool) {
        fail "secret-tool is not installed (try: apt install libsecret-tools)"
    }
    main help
}
