#!/usr/bin/env nu

export def default-if-empty [default_val: any] {
    if ($in | is-empty) { $default_val } else { $in }
}

export def try-relative [path: string, base: string] {
    do -i { $path | path relative-to $base } | default ($path | path basename)
}

export def ensure-parent-dir [path: string] {
    let parent = ($path | path dirname)
    if not ($parent | path exists) {
        mkdir $parent
    }
}

export def validate-path [path: string, --required] {
    if $required and not ($path | path exists) {
        error make {
            msg: $"Path does not exist: ($path)"
            label: { text: $path, span: (metadata $path).span }
        }
    }
    $path
}

export def validate-file [path: string] {
    let file_type = do -i { $path | path type } | default "none"
    if $file_type != 'file' and $file_type != 'symlink' {
        error make {
            msg: $"Not a file: ($path)"
            label: { text: $path, span: (metadata $path).span }
        }
    }
    $path
}
