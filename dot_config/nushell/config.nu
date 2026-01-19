$env.config = {
    show_banner: false
}

def jupyter-lab [] {
    let jupyter_dir = ($nu.home-path | path join jupyter-lab)

    if not ($jupyter_dir | path exists) {
        error make {
            msg: "Directory does not exist"
            label: {
                text: $jupyter_dir
                span: (metadata $jupyter_dir).span
            }
        }
    }

    let jupyter = ($jupyter_dir | path join .venv | path join bin | path join jupyter)
    if not ($jupyter | path exists) {
        error make { msg: "Virtual environment not found" }
    }

    ^$jupyter lab
}

def 'has_cmd' [ app: string ] {
  (which $app | is-not-empty)
}

if (($nu.home-path | path join .cargo/env.nu) | path exists) {
    source $"($nu.home-path)/.cargo/env.nu"
}

if (($nu.default-config-dir | path join mise.nu) | path exists) {
    use ($nu.default-config-dir | path join mise.nu)
}

source ($nu.default-config-dir | path join starship.nu)
source ($nu.default-config-dir | path join zoxide.nu)
