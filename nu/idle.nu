#!/usr/bin/env nu

def has-cmd [cmd: string]: nothing -> bool {
  (which $cmd | is-not-empty)
}

def get-compositor []: nothing -> string {
  let desktop = ($env.XDG_CURRENT_DESKTOP? | default "" | str downcase)
  if $desktop =~ "hyprland" { return "hyprland" }
  if $desktop =~ "niri" { return "niri" }
  if $desktop =~ "sway" { return "sway" }
  if $desktop =~ "mango" { return "mango" }
  ""
}

def is-vm []: nothing -> bool {
  if (has-cmd "systemd-detect-virt") {
    let result = (^systemd-detect-virt --vm | complete)
    if $result.exit_code == 0 and ($result.stdout | str trim) != "none" {
      return true
    }
  }
  if ("/sys/class/dmi/id/product_name" | path exists) {
    let product = (open /sys/class/dmi/id/product_name | str downcase)
    if $product =~ "virtual|vmware|qemu|kvm|virtualbox|xen|bochs" {
      return true
    }
  }
  false
}

def monitor-off []: nothing -> nothing {
  let comp = (get-compositor)
  match $comp {
    "hyprland" => { ^hyprctl dispatch dpms off }
    "niri" => { ^niri msg action power-off-monitors }
    "sway" => { ^swaymsg "output * power off" }
    "mango" => {
      for output in ["DP-1" "DP-2" "HDMI-A-1" "HDMI-A-2" "eDP-1"] {
        do -i { ^mmsg -d $"disable_monitor,($output)" }
      }
    }
    _ => { if (has-cmd "wlr-randr") { ^wlr-randr --output '*' --off } }
  }
}

def monitor-on []: nothing -> nothing {
  let comp = (get-compositor)
  match $comp {
    "hyprland" => { ^hyprctl dispatch dpms on }
    "niri" => { ^niri msg action power-on-monitors }
    "sway" => { ^swaymsg "output * power on" }
    "mango" => {
      for output in ["DP-1" "DP-2" "HDMI-A-1" "HDMI-A-2" "eDP-1"] {
        do -i { ^mmsg -d $"enable_monitor,($output)" }
      }
    }
    _ => { if (has-cmd "wlr-randr") { ^wlr-randr --output '*' --on } }
  }
}

def system-sleep []: nothing -> nothing {
  if (has-cmd "systemctl") {
    ^systemctl suspend
  } else if (has-cmd "loginctl") {
    ^loginctl suspend
  }
}

def show-help [] {
  print "idle.nu - Idle management for Wayland compositors"
  print ""
  print "Usage: nu idle.nu [command]"
  print ""
  print "Commands:"
  print "  (no args)    Start idle daemon with default timeouts"
  print "  monitor-off  Turn off monitors immediately"
  print "  monitor-on   Turn on monitors immediately"
  print "  system-sleep Suspend the system"
  print "  help         Show this help message"
  print ""
  print "Supported Compositors:"
  print "  - niri"
  print "  - hyprland"
  print "  - sway"
  print "  - mango"
  print ""
  print "Timeouts:"
  print "  Monitor off: 3 minutes"
  print "  System sleep: 10 minutes (disabled in VMs)"
  print ""
  print "Requirements:"
  print "  - swayidle"
}

def "main monitor-off" []: nothing -> nothing { monitor-off }
def "main monitor-on" []: nothing -> nothing { monitor-on }
def "main system-sleep" []: nothing -> nothing { system-sleep }
def "main help" []: nothing -> nothing { show-help }

def main [
  --help (-h)
]: nothing -> nothing {
  if $help {
    show-help
    return
  }
  if not (has-cmd "swayidle") {
    error make { msg: "swayidle not found" }
  }

  let comp = (get-compositor)
  if $comp == "" {
    error make { msg: "Unsupported compositor. Expected: niri, sway, hyprland, or mango" }
  }

  let script_path = $env.CURRENT_FILE
  let vm = (is-vm)
  let monitor_timeout = 180
  let sleep_timeout = 600

  mut cmd_parts = [
    "swayidle"
    "-w"
    "timeout"
    ($monitor_timeout | into string)
    $"nu ($script_path) monitor-off"
    "resume"
    $"nu ($script_path) monitor-on"
  ]

  if not $vm {
    $cmd_parts = $cmd_parts ++ [
      "timeout"
      ($sleep_timeout | into string)
      $"nu ($script_path) system-sleep"
    ]
  }

  run-external $cmd_parts.0 ...($cmd_parts | skip 1)
}
