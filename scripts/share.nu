#!/usr/bin/env nu

def main [] { main help }

def "main scan" [] {
  print "Scanning for SMB and NFS shares on local network...\n"

  print "Discovering SMB servers (mDNS)..."
  let smb = (discover_mdns_servers _smb._tcp)
  if ($smb | is-empty) { print "  No SMB servers found via mDNS." } else {
    print $"  Found SMB servers: ($smb | length)\n"
    for server in $smb {
      print $"  Scanning smb://($server) ..."
      scan_smb_server $server
    }
  }

  print "\nDiscovering NFS servers (mDNS)..."
  let nfs = (discover_mdns_servers _nfs._tcp)
  if ($nfs | is-empty) { print "  No NFS servers found via mDNS." } else {
    print $"  Found NFS servers: ($nfs | length)\n"
    for server in $nfs {
      print $"  Scanning nfs://($server) ..."
      scan_nfs_server $server
    }
  }

  print "\nTip: share ls //server/share  or  share ls server:/export"
}

def "main ls" [
  share: string
  --user: string = ""
  --password: string = ""
] {
  if ($share | str contains ":") and not ($share | str starts-with "//") {
    nfs_list $share
  } else {
    let p = (parse_smb_url $share)
    let auth = (smb_auth_flags $p.server $user $password)
    let target = $"//($p.server)/($p.share)"
    let smb_cmd = (if ($p.path | is-empty) { "ls" } else { $"cd \"($p.path)\"; ls" })
    let r = (^smbclient ...$auth $target -c $"($smb_cmd); quit" | complete)
    if $r.exit_code != 0 { print $"Error: ($r.stderr | str trim)"; return }
    print_smb_ls_output $r.stdout
  }
}

def "main get" [
  remote: string
  local: string
  --user: string = ""
  --password: string = ""
] {
  copy_shared $remote $local --user $user --password $password --direction "download"
}

def "main put" [
  local: string
  remote: string
  --user: string = ""
  --password: string = ""
] {
  copy_shared $local $remote --user $user --password $password --direction "upload"
}

def "main cp" [
  src: string
  dst: string
  --user: string = ""
  --password: string = ""
] {
  let s_rem = (is_remote $src)
  let d_rem = (is_remote $dst)
  if $s_rem and not $d_rem { copy_shared $src $dst --user $user --password $password --direction "download" } else if not $s_rem and $d_rem { copy_shared $src $dst --user $user --password $password --direction "upload" } else if $s_rem and $d_rem { print "Error: at least one path must be local" } else { print "Error: need one local and one remote path (//server/share or server:/export)" }
}

def "main mount" [
  share: string
  mountpoint?: string
  --user: string = ""
  --password: string = ""
] {
  let mp = (ensure_mountpoint $share $mountpoint)
  if ($mp | is-empty) { return }

  if ($share | str contains ":") and not ($share | str starts-with "//") {
    print $"Mounting nfs:($share) -> ($mp) ..."
    ^mount -t nfs $share $mp
  } else {
    let p = (parse_smb_url $share)
    let target = $"//($p.server)/($p.share)"
    print $"Mounting smb:($target) -> ($mp) ..."
    let opts = (if ($user | is-empty) { [] } else if ($password | is-empty) { [$"-o username=($user)"] } else { [$"-o username=($user),password=($password)"] })
    ^mount -t cifs $target $mp ...$opts
  }
  print $"Mounted at ($mp)"
}

def "main umount" [
  mountpoint: string
] {
  ^umount $mountpoint
  print $"Unmounted ($mountpoint)"
}

def "main help" [] {
  print "Network Share Utility"
  print ""
  print "Usage: share <command> [options] [args]"
  print ""
  print "Commands:"
  print "  scan                         Discover SMB/NFS shares on network"
  print "  ls <share> [--user u]       List files in a share"
  print "  get <remote> <local>        Copy FROM share TO local"
  print "  put <local> <remote>        Copy FROM local TO share"
  print "  cp <src> <dst>              Auto-detect direction"
  print "  mount <share> [path]        Mount a share"
  print "  umount <path>               Unmount a share"
  print ""
  print "Share URL formats:"
  print "  SMB:  //server/share[/path]   or  smb://server/share[/path]"
  print "  NFS:  server:/export[/path]"
  print ""
  print "Examples:"
  print "  share scan"
  print "  share ls --user alice //192.168.1.100/shared"
  print "  share get //192.168.1.100/share/file.txt ./"
  print "  share put ./photo.jpg //192.168.1.100/share/"
  print "  share cp //192.168.1.100/share/file.txt ./"
  print "  share mount //192.168.1.100/shared /mnt/share"
  print "  share umount /mnt/share"
  print ""
  print "For SMB credential storage: smb-keyring"
}

def is_remote [p: string] {
  ($p | str starts-with "//") or (($p | str contains ":") and not ($p | str starts-with "/") and not ($p | str starts-with "~") and not ($p | str contains "://"))
}

def parse_smb_url [url: string] {
  let clean = ($url | str replace "smb://" "//")
  let raw = ($clean | split row "/" | where {|x| ($x | str length) > 0})
  let server = ($raw | first)
  let share = (if ($raw | length) >= 2 { $raw.1 } else { "" })
  let path = (if ($raw | length) >= 3 { $raw | skip 2 | str join "/" } else { "" })
  let ends_slash = ($clean | str ends-with "/")
  { server: $server, share: $share, path: $path, ends_slash: $ends_slash }
}

def discover_mdns_servers [service: string] {
  bash -c $"avahi-browse ($service) -rt 2>/dev/null" | lines | find "address =" | parse --regex '\[(?P<ip>[\d\.]+)\]' | get ip | uniq
}

def scan_smb_server [server: string] {
  let smb_result = (smbclient -N -L $"//($server)" | complete)
  if $smb_result.exit_code != 0 {
    let stderr = ($smb_result.stderr | str trim)
    let stdout = ($smb_result.stdout | str trim)
    if (($stdout | str downcase | str starts-with "session setup failed") or ($stderr | str contains "NT_STATUS_ACCESS_DENIED") or ($stderr | str contains "NT_STATUS_LOGON_FAILURE")) {
      print "    (requires authentication)"
    } else if ($stderr | str length) > 0 {
      for el in ($stderr | lines | find -v "^$" | find "NT_STATUS") {
        print $"    ($el | str trim)"
      }
    }
    return
  }
  for line in ($smb_result.stdout | lines) {
    let trimmed = ($line | str trim)
    if ($trimmed | is-empty) { continue }
    let parts = ($trimmed | split row -r "\\s+")
    if ($parts | length) >= 2 {
      let name = ($parts | first)
      let desc = ($parts | skip 1 | str join " ")
      if (($name | str length) > 0
        and not ($name | str starts-with "---")
        and not ($name | str starts-with "Sharename")
        and not ($name | str starts-with "Server")
        and not ($name | str starts-with "Workgroup")) {
        print $"    │  ($name)  ─  ($desc)"
      }
    }
  }
}

def scan_nfs_server [server: string] {
  let r = (showmount -e $server | complete)
  if $r.exit_code != 0 { print $"    ($r.stderr | str trim)"; return }
  for line in ($r.stdout | lines | skip 1) {
    let export_path = ($line | split row -r '\s+' | first)
    if ($export_path | str length) > 0 { print $"    │  $export_path" }
  }
}

def smb_auth_flags [server: string, user: string, password: string] {
  if ($user | is-empty) { return ["-N"] }
  let pw = (if ($password | is-empty) { lookup_smb_password $server $user } else { $password })
  if ($pw | is-empty) { ["-U", $user] } else { ["-U", $"($user)%($pw)"] }
}

def lookup_smb_password [server: string, user: string] {
  let r = (^secret-tool search --all protocol smb server $server user $user | complete)
  if $r.exit_code == 0 {
    let secret_lines = ($r.stdout | lines | where {|line| ($line | str trim | str starts-with "secret = ") })
    if ($secret_lines | length) > 0 { return ($secret_lines.0 | str trim | str replace "secret = " "") }
  }
  ""
}

def nfs_list [share: string] {
  let tmpdir = (mktemp -d)
  try {
    ^mount -t nfs $share $tmpdir
    print (ls -a $tmpdir | select name type size modified)
    ^umount $tmpdir
  } catch { |e| print $"Error: ($e.msg)" }
  rm -rf $tmpdir
}

def print_smb_ls_output [stdout: string] {
  for line in ($stdout | lines) {
    let trimmed = ($line | str trim)
    if ($trimmed | is-empty) { continue }
    if ($trimmed | str contains "blocks of size") { continue }
    let parts = ($trimmed | split row -r "\\s+")
    if ($parts | length) >= 4 {
      let name = ($parts | first)
      let attrs = ($parts | select 1 | first)
      let size = ($parts | select 2 | first)
      let date = ($parts | skip 3 | str join " ")
      let icon = (if ($attrs | str contains "D") { "📁" } else { "📄" })
      print $"  ($icon) ($name)  ($size)  ($date)"
    }
  }
}

def ensure_mountpoint [share: string, mountpoint?: string] {
  let mp = (if ($mountpoint | is-empty) { $"/mnt/($share | split row '/' | last)" } else { $mountpoint })
  if ($mp | path exists) {
    if not ((ls $mp | length) == 0) { print $"Error: ($mp) is not empty"; return "" }
  } else {
    ^mkdir -p $mp
  }
  $mp
}

def nfs_copy [src: string, dst: string, direction: string] {
  let tmp = (mktemp -d)
  try {
    if $direction == "download" {
      ^mount -t nfs $src $tmp
      ^mkdir -p $dst
      ^cp -r $"($tmp)/." $dst
    } else {
      ^mount -t nfs $dst $tmp
      ^cp -r $src $"($tmp)/"
    }
    ^umount $tmp
  } catch { |e| print $"Error: ($e.msg)"; rm -rf $tmp; return }
  rm -rf $tmp
  print (if $direction == "download" { $"Downloaded to ($dst)" } else { $"Uploaded ($src) to remote" })
}

def smb_download [target: string, auth: list, path: string, local: string, ends_slash: bool] {
  if ($path | is-empty) { print "Error: specify a file path to download"; return }
  let success = if $ends_slash {
    let r = (^smbclient ...$auth $target -c $"cd \"($path)\"; ls; quit" | complete)
    $r.exit_code == 0
  } else {
    let filename = ($path | split row "/" | last)
    let cdpath = ($path | split row "/" | drop 1 | str join "/")
    let cmd = (if ($cdpath | is-empty) { $"get \"($filename)\" \"($local)\"" } else { $"cd \"($cdpath)\"; get \"($filename)\" \"($local)\"" })
    let r = (^smbclient ...$auth $target -c $"($cmd); quit" | complete)
    $r.exit_code == 0
  }
  if $success { print $"Downloaded to ($local)" } else { print "Download failed" }
}

def smb_upload [target: string, auth: list, path: string, local: string, ends_slash: bool] {
  let local_basename = ($local | split row "/" | last)
  let success = if ($path | is-empty) {
    let r = (^smbclient ...$auth $target -c $"put \"($local)\" \"($local_basename)\"; quit" | complete)
    $r.exit_code == 0
  } else if $ends_slash {
    let r = (^smbclient ...$auth $target -c $"cd \"($path)\"; put \"($local)\" \"($local_basename)\"; quit" | complete)
    $r.exit_code == 0
  } else {
    let target_name = ($path | split row "/" | last)
    let cdpath = ($path | split row "/" | drop 1 | str join "/")
    let cmd = (if ($cdpath | is-empty) { $"put \"($local)\" \"($target_name)\"" } else { $"cd \"($cdpath)\"; put \"($local)\" \"($target_name)\"" })
    let r = (^smbclient ...$auth $target -c $"($cmd); quit" | complete)
    $r.exit_code == 0
  }
  if $success { print $"Uploaded ($local) to remote" } else { print "Upload failed" }
}

def copy_shared [a: string, b: string, --user: string = "", --password: string = "", --direction: string] {
  if $direction == "download" {
    let remote = $a; let local = $b
    if ($remote | str contains "//") {
      let p = (parse_smb_url $remote)
      let auth = (smb_auth_flags $p.server $user $password)
      smb_download $"//($p.server)/($p.share)" $auth $p.path $local $p.ends_slash
    } else {
      nfs_copy $remote $local "download"
    }
  } else {
    let local = $a; let remote = $b
    if ($remote | str contains "//") {
      let p = (parse_smb_url $remote)
      let auth = (smb_auth_flags $p.server $user $password)
      smb_upload $"//($p.server)/($p.share)" $auth $p.path $local $p.ends_slash
    } else {
      nfs_copy $local $remote "upload"
    }
  }
}
