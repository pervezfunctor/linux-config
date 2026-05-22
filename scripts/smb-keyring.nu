#!/usr/bin/env nu

def main [
  cmd: string = ""
  server: string = "192.168.10.56"
  user: string = ""
] {
  match $cmd {
    "store" => {
      let user = if ($user | is-empty) {
        input "Username: "
      } else {
        $user
      }
      let pass = (input $"Password for ($user)@($server): " --suppress-output)
      print ""
      $pass | ^secret-tool store --label $"($user)@($server)" protocol smb server $server user $user
      print $"Stored credentials for ($user)@($server)"
    }
    "show" => {
      let res = (^secret-tool search --all protocol smb server $server | complete)
      if $res.exit_code != 0 {
        print $"No credentials found for ($server)"
      } else {
        print $res.stdout
      }
    }
    "clear" => {
      if not ($user | is-empty) {
        ^secret-tool clear protocol smb server $server user $user
        print $"Cleared credentials for ($user)@($server)"
      } else {
        ^secret-tool clear protocol smb server $server
        print $"Cleared all SMB credentials for ($server)"
      }
      ^bash ($env.HOME | path join ".linux-config/scripts/clear-smb-creds.bash") $server
    }
    "list" => {
      let res = (^secret-tool search --all protocol smb | complete)
      if $res.exit_code != 0 {
        print "No SMB credentials stored"
      } else {
        print $res.stdout
      }
    }
    "help" | "--help" | "-h" | "" => {
      print $"Usage: smb-keyring <command> [server] [user]"
      print ""
      print "Commands:"
      print "  store [server] [user]   Store SMB credentials"
      print "  show  [server]          Show credentials for a server"
      print "  clear [server] [user]   Clear credentials (optionally for a specific user)"
      print "  list                    List all stored SMB credentials"
      print ""
      print "Examples:"
      print "  smb-keyring store 192.168.10.56 piqbal"
      print "  smb-keyring show  192.168.10.56"
      print "  smb-keyring clear 192.168.10.56 pervez"
      print "  smb-keyring list"
    }
  }
}
