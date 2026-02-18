#!/usr/bin/env nu

def service-active [service: string]: nothing -> bool {
  let result = (do -i { ^systemctl is-active $service } | complete)
  $result.exit_code == 0 and ($result.stdout | str trim) == "active"
}

def run-sudo [cmd: string]: nothing -> bool {
  let check = (do -i { sudo -n true } | complete)
  if $check.exit_code != 0 {
    print $"  Skipped (no sudo): sudo ($cmd)"
    return false
  }
  let result = (do -i { sudo -n $cmd } | complete)
  if $result.exit_code == 0 { true } else { print $"  Failed: sudo ($cmd)"; false }
}

def ufw-rule-exists [rule: string]: nothing -> bool {
  let result = (do -i { sudo ufw status numbered } | complete)
  if $result.exit_code != 0 { return false }
  $result.stdout | str contains $rule
}

def add-ufw-if-missing [rule: string]: nothing -> bool {
  if (ufw-rule-exists $rule) {
    print $"  Rule already exists: ($rule)"
    true
  } else {
    run-sudo $rule
  }
}

def add-iptables-if-missing [chain: string, rule: string]: nothing -> bool {
  let check = (do -i { sudo iptables -C $chain $rule 2>/dev/null } | complete)
  if $check.exit_code != 0 {
    run-sudo $"iptables -I ($chain) ($rule)"
  } else { true }
}

def add-nft-if-missing [rule: string]: nothing -> bool {
  let check = (do -i { sudo nft -a list ruleset | grep -q "$rule" } | complete)
  if $check.exit_code != 0 {
    run-sudo $"nft add rule inet filter $rule"
  } else { true }
}

export def configure-incus-firewall [bridge: string = "incusbr0"] {
  let sudo_check = (do -i { sudo -n true } | complete)
  if $sudo_check.exit_code != 0 {
    print "Warning: sudo privileges required for firewall configuration."
    print "Run manually with sudo: sudo nu bin/incus-firewall-config.nu"
    return
  }

  if (service-active ufw) {
    print $"UFW detected, configuring ($bridge)..."
    add-ufw-if-missing $"ufw allow in on ($bridge)"
    add-ufw-if-missing $"ufw route allow in on ($bridge)"
    add-ufw-if-missing $"ufw route allow out on ($bridge)"
  }

  if (service-active firewalld) {
    print $"firewalld detected, configuring ($bridge)..."
    run-sudo $"firewall-cmd --zone=trusted --change-interface=($bridge) --permanent"
    run-sudo "firewall-cmd --reload"
  }

  if (service-active docker) {
    print $"Docker detected, configuring iptables for ($bridge)..."
    add-iptables-if-missing "FORWARD" $"-i ($bridge) -j ACCEPT"
    add-iptables-if-missing "FORWARD" $"-o ($bridge) -j ACCEPT"

    let docker_user = (do -i { sudo iptables -L DOCKER-USER 2>/dev/null } | complete)
    if $docker_user.exit_code == 0 {
      add-iptables-if-missing "DOCKER-USER" $"-i ($bridge) -j ACCEPT"
      add-iptables-if-missing "DOCKER-USER" $"-o ($bridge) -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
    }
  }

  if (which nft | is-not-empty) {
    let nft_list = (do -i { sudo nft list ruleset } | complete)
    if $nft_list.exit_code == 0 {
      if ($nft_list.stdout | str contains $bridge) {
        print $"nftables: ($bridge) already configured"
      } else {
        print $"nftables detected, configuring ($bridge)..."
        run-sudo $"nft add table inet filter"
        run-sudo $"nft add chain inet filter forward \{ type filter hook forward priority filter; policy accept; \}"
        run-sudo $"nft add rule inet filter forward iifname \"($bridge)\" accept"
        run-sudo $"nft add rule inet filter forward oifname \"($bridge)\" accept"
      }
    }
  }

  print "Firewall configuration complete."
}

def main [bridge: string = "incusbr0"] {
  configure-incus-firewall $bridge
}
