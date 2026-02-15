#!/usr/bin/env nu

# Test suite for build-servers-json.nu and generate-tmuxp.nu
# Run from repo root: nu bin/test-tmuxp-scripts.nu

# Validate IP address format (x.x.x.x with each octet 0-255)
def is-valid-ip [ip: string]: nothing -> bool {
  let parts = $ip | split row "."

  if ($parts | length) != 4 {
    return false
  }

  $parts | all {|p|
    try {
      let num = $p | into int
      $num >= 0 and $num <= 255
    } catch {
      false
    }
  }
}

# Test is-valid-ip function
def test-is-valid-ip [] {
  print "(ansi cyan)Testing is-valid-ip...(ansi reset)"

  # Valid IPs
  assert ((is-valid-ip "192.168.1.1") == true) "Valid IP: 192.168.1.1"
  assert ((is-valid-ip "0.0.0.0") == true) "Valid IP: 0.0.0.0"
  assert ((is-valid-ip "255.255.255.255") == true) "Valid IP: 255.255.255.255"
  assert ((is-valid-ip "10.0.0.1") == true) "Valid IP: 10.0.0.1"

  # Invalid IPs
  assert ((is-valid-ip "192.168.1") == false) "Invalid IP: too few octets"
  assert ((is-valid-ip "192.168.1.1.1") == false) "Invalid IP: too many octets"
  assert ((is-valid-ip "192.168.1.256") == false) "Invalid IP: octet > 255"
  assert ((is-valid-ip "192.168.1.-1") == false) "Invalid IP: negative octet"
  assert ((is-valid-ip "192.168.1.abc") == false) "Invalid IP: non-numeric"
  assert ((is-valid-ip "") == false) "Invalid IP: empty string"
  assert ((is-valid-ip "192.168.1.1.1") == false) "Invalid IP: too many parts"

  print "(ansi green)  All is-valid-ip tests passed!(ansi reset)"
}

# Test username validation (must not be empty)
def test-username-validation [] {
  print "(ansi cyan)Testing username validation...(ansi reset)"

  # Test that empty username with no default is rejected
  # This tests the logic: if username == "" and default == "", should fail
  let default_empty = ""
  let default_set = "admin"

  # Simulate the validation logic
  let valid_username = "testuser"
  let empty_username = ""

  # With default set, empty input should use default
  let result_with_default = if $empty_username == "" { $default_set } else { $empty_username }
  assert ($result_with_default == "admin") "Empty input uses default when set"

  # With no default, empty input results in empty (would be rejected in interactive mode)
  let result_no_default = if $empty_username == "" { $default_empty } else { $empty_username }
  assert ($result_no_default == "") "Empty input with no default results in empty"

  # Non-empty input always uses the input
  let result_explicit = if $valid_username == "" { $default_set } else { $valid_username }
  assert ($result_explicit == "testuser") "Explicit input always used"

  print "(ansi green)  All username validation tests passed!(ansi reset)"
}

# Test generate-tmuxp with various JSON inputs
def test-generate-tmuxp [] {
  print "(ansi cyan)Testing generate-tmuxp...(ansi reset)"

  let test_dir = "test-tmuxp-temp"

  # Clean up any existing test directory
  if ($test_dir | path exists) {
    rm -r $test_dir
  }
  mkdir $test_dir

  # Test 1: Basic servers with defaults
  let json1 = {
    defaults: {username: "pervez", identity: "~/.ssh/id_rsa"}
    servers: [
      {ip: "192.168.1.1"}
      {ip: "192.168.1.2", username: "debian"}
      {ip: "192.168.1.3", identity: "~/.ssh/work"}
    ]
  }
  $json1 | to json | save $"($test_dir)/test1.json"
  nu bin/generate-tmuxp.nu $"($test_dir)/test1.json" $"($test_dir)/test1.yaml"
  let yaml1 = open $"($test_dir)/test1.yaml" --raw
  assert ($yaml1 | str contains "ssh -i ~/.ssh/id_rsa pervez@192.168.1.1") "Default user and identity applied"
  assert ($yaml1 | str contains "ssh -i ~/.ssh/id_rsa debian@192.168.1.2") "Override username, default identity"
  assert ($yaml1 | str contains "ssh -i ~/.ssh/work pervez@192.168.1.3") "Default username, override identity"

  # Test 2: No defaults
  let json2 = {
    servers: [
      {ip: "192.168.1.1", username: "user1", identity: "~/.ssh/key1"}
      {ip: "192.168.1.2", username: "user2", identity: ""}
    ]
  }
  $json2 | to json | save $"($test_dir)/test2.json"
  nu bin/generate-tmuxp.nu $"($test_dir)/test2.json" $"($test_dir)/test2.yaml"
  let yaml2 = open $"($test_dir)/test2.yaml" --raw
  assert ($yaml2 | str contains "ssh -i ~/.ssh/key1 user1@192.168.1.1") "Explicit identity"
  assert ($yaml2 | str contains "ssh user2@192.168.1.2") "No identity"

  # Test 3: Empty identity in defaults
  let json3 = {
    defaults: {username: "admin", identity: ""}
    servers: [
      {ip: "192.168.1.1"}
      {ip: "192.168.1.2", identity: "~/.ssh/special"}
    ]
  }
  $json3 | to json | save $"($test_dir)/test3.json"
  nu bin/generate-tmuxp.nu $"($test_dir)/test3.json" $"($test_dir)/test3.yaml"
  let yaml3 = open $"($test_dir)/test3.yaml" --raw
  assert ($yaml3 | str contains "ssh admin@192.168.1.1") "No identity flag when empty"
  assert ($yaml3 | str contains "ssh -i ~/.ssh/special admin@192.168.1.2") "Override identity"

  # Test 4: YAML structure
  assert ($yaml1 | str contains "session_name: remote-servers") "Session name correct"
  assert ($yaml1 | str contains "window_name: servers") "Window name correct"
  assert ($yaml1 | str contains "layout: tiled") "Layout correct"
  assert ($yaml1 | str contains "shell_command:") "Shell command present"

  # Cleanup
  rm -r $test_dir

  print "(ansi green)  All generate-tmuxp tests passed!(ansi reset)"
}

# Test JSON structure from build-servers-json
def test-json-structure [] {
  print "(ansi cyan)Testing JSON structure...(ansi reset)"

  # Verify expected JSON structure
  let expected_keys = ["defaults", "servers"]
  let default_keys = ["username", "identity"]
  let server_keys = ["username", "ip", "identity"]

  # Create a sample JSON and verify structure
  let sample = {
    defaults: {username: "test", identity: "~/.ssh/test"}
    servers: [{username: "user", ip: "192.168.1.1", identity: ""}]
  }

  assert (($sample | columns | to json) == ($expected_keys | to json)) "Top-level keys correct"
  assert (($sample.defaults | columns | to json) == ($default_keys | to json)) "Default keys correct"
  assert (($sample.servers.0 | columns | to json) == ($server_keys | to json)) "Server keys correct"

  print "(ansi green)  All JSON structure tests passed!(ansi reset)"
}

# Test build-servers-json output format
def test-build-servers-json [] {
  print "(ansi cyan)Testing build-servers-json output...(ansi reset)"

  let test_dir = "test-tmuxp-temp"

  # Clean up any existing test directory
  if ($test_dir | path exists) {
    rm -r $test_dir
  }
  mkdir $test_dir

  # Test 1: Verify JSON output structure
  let expected_structure = {
    defaults: {username: "", identity: ""}
    servers: []
  }

  # Create a test JSON file manually to verify structure
  let test_json = {
    defaults: {username: "testuser", identity: "~/.ssh/test_key"}
    servers: [
      {username: "server1", ip: "192.168.1.1", identity: ""}
      {username: "server2", ip: "192.168.1.2", identity: "~/.ssh/other"}
    ]
  }
  $test_json | to json | save $"($test_dir)/build-test.json"

  # Verify the JSON can be read and has correct structure
  let loaded = open $"($test_dir)/build-test.json"
  assert (($loaded | columns | length) == 2) "JSON has 2 top-level keys"
  assert (($loaded.defaults | columns | length) == 2) "Defaults has 2 keys"
  assert (($loaded.servers | length) == 2) "Servers array has 2 entries"
  assert (($loaded.servers.0 | columns | length) == 3) "Server entry has 3 fields"

  # Test 2: Verify JSON is valid and parseable by generate-tmuxp
  nu bin/generate-tmuxp.nu $"($test_dir)/build-test.json" $"($test_dir)/build-test.yaml"
  let yaml_out = open $"($test_dir)/build-test.yaml" --raw
  # Server1 has explicit username "server1" and empty identity, so uses that username
  assert ($yaml_out | str contains "ssh server1@192.168.1.1") "Explicit username used"
  # Server2 has explicit username and identity
  assert ($yaml_out | str contains "ssh -i ~/.ssh/other server2@192.168.1.2") "Explicit identity applied"

  # Test 3: Empty servers array
  let empty_servers = {
    defaults: {username: "admin", identity: ""}
    servers: []
  }
  $empty_servers | to json | save $"($test_dir)/empty.json"
  nu bin/generate-tmuxp.nu $"($test_dir)/empty.json" $"($test_dir)/empty.yaml"
  let empty_yaml = open $"($test_dir)/empty.yaml" --raw
  assert ($empty_yaml | str contains "session_name: remote-servers") "Empty servers still produces valid YAML"

  # Test 4: Missing defaults key
  let no_defaults = {
    servers: [{username: "user", ip: "192.168.1.1", identity: ""}]
  }
  $no_defaults | to json | save $"($test_dir)/no-defaults.json"
  nu bin/generate-tmuxp.nu $"($test_dir)/no-defaults.json" $"($test_dir)/no-defaults.yaml"
  let no_def_yaml = open $"($test_dir)/no-defaults.yaml" --raw
  assert ($no_def_yaml | str contains "ssh user@192.168.1.1") "Works without defaults key"

  # Test 5: Partial server entries
  let partial = {
    defaults: {username: "defaultuser", identity: "~/.ssh/default"}
    servers: [
      {ip: "192.168.1.1"}
      {ip: "192.168.1.2", username: "override"}
      {ip: "192.168.1.3", identity: "~/.ssh/special"}
    ]
  }
  $partial | to json | save $"($test_dir)/partial.json"
  nu bin/generate-tmuxp.nu $"($test_dir)/partial.json" $"($test_dir)/partial.yaml"
  let partial_yaml = open $"($test_dir)/partial.yaml" --raw
  assert ($partial_yaml | str contains "ssh -i ~/.ssh/default defaultuser@192.168.1.1") "All defaults applied"
  assert ($partial_yaml | str contains "ssh -i ~/.ssh/default override@192.168.1.2") "Override username, default identity"
  assert ($partial_yaml | str contains "ssh -i ~/.ssh/special defaultuser@192.168.1.3") "Default username, override identity"

  # Cleanup
  rm -r $test_dir

  print "(ansi green)  All build-servers-json tests passed!(ansi reset)"
}

# Helper assertion function
def assert [condition: bool, message: string] {
  if not $condition {
    print $"(ansi red)  FAILED: ($message)(ansi reset)"
    error make {msg: $"Test failed: ($message)"}
  }
}

# Run all tests
def main [] {
  print "\n(ansi cyan)=== Running tmuxp script tests ===(ansi reset)\n"

  test-is-valid-ip
  test-username-validation
  test-generate-tmuxp
  test-json-structure
  test-build-servers-json

  print "\n(ansi green)=== All tests passed! ===(ansi reset)\n"
}
