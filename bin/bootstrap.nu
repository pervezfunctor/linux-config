use ../nu/logs.nu *
use ../nu/lib.nu *
use ../nu/setup-lib.nu *

def main [] {
  init-log-file
  bootstrap
  let job_id = (keep-sudo-alive)

  base-install

  let linux_config_dir = ($env.CURRENT_FILE | path dirname)
  nu ($linux_config_dir | path join "setup-shell.nu")
  nu ($linux_config_dir | path join "setup-desktop.nu")

  stop-sudo-alive $job_id
}
