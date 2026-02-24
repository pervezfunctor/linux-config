#!/usr/bin/env nu

use std/log

def log+ [msg: string] { log info $msg }
def warn+ [msg: string] { log warning $msg }
def error+ [msg: string] { log error $msg }

log+ "=== Testing docker-vm.nu ==="

def test-result [test_name: string, passed: bool, detail: string] {
    let status = if $passed { "[PASS]" } else { "[FAIL]" }
    print $"($status) ($test_name)"
    if not $passed {
        print $"  Detail: ($detail)"
    }
}

def contains [text: string, pattern: string] {
    $text | grep $pattern | is-not-empty
}

log+ "=== Test 1: Script loads without error ==="

let source_result = (do -i { nu -c 'use ../docker-vm.nu; null' } | complete)
test-result "script loads" ($source_result.exit_code == 0) $"Exit code: ($source_result.exit_code)"

log+ ""
log+ "=== Test 2: Help command ==="

let help_result = (do -i { nu ../docker-vm.nu help } | complete)
test-result "help command runs" ($help_result.exit_code == 0) $"Exit code: ($help_result.exit_code)"
test-result "help contains title" (contains $help_result.stdout "docker-vm.nu") "Should contain 'docker-vm.nu'"
test-result "help contains create" (contains $help_result.stdout "create") "Should contain 'create'"
test-result "help contains start" (contains $help_result.stdout "start") "Should contain 'start'"
test-result "help contains stop" (contains $help_result.stdout "stop") "Should contain 'stop'"
test-result "help contains restart" (contains $help_result.stdout "restart") "Should contain 'restart'"
test-result "help contains remove" (contains $help_result.stdout "remove") "Should contain 'remove'"
test-result "help contains exec" (contains $help_result.stdout "exec") "Should contain 'exec'"
test-result "help contains status" (contains $help_result.stdout "status") "Should contain 'status'"

log+ ""
log+ "=== Test 3: Unknown command handling ==="

let unknown_result = (do -i { nu ../docker-vm.nu invalid_command } | complete)
test-result "unknown command fails" ($unknown_result.exit_code != 0) $"Exit code: ($unknown_result.exit_code)"
let unknown_output = $unknown_result.stdout + $unknown_result.stderr
test-result "unknown command shows usage" (contains $unknown_output "Usage:") "Should show usage"

log+ ""
log+ "=== Test 4: Remove command (non-existent VM) ==="

let remove_no_vm = (do -i { nu ../docker-vm.nu remove } | complete)
test-result "remove command handles missing VM gracefully" ($remove_no_vm.exit_code == 0) "Should succeed (no-op)"

log+ ""
log+ "=== Test 5: Status command (non-existent VM) ==="

let status_no_vm = (do -i { nu ../docker-vm.nu status } | complete)
test-result "status command fails without VM" ($status_no_vm.exit_code != 0) "Should fail"
test-result "status shows error message" (contains $status_no_vm.stderr "does not exist") "Should show error"

log+ ""
log+ "=== Test 6: Start command (non-existent VM) ==="

let start_no_vm = (do -i { nu ../docker-vm.nu start } | complete)
test-result "start command fails without VM" ($start_no_vm.exit_code != 0) "Should fail"
test-result "start shows error message" (contains $start_no_vm.stderr "does not exist") "Should show error"

log+ ""
log+ "=== Test 7: Stop command (non-existent VM) ==="

let stop_no_vm = (do -i { nu ../docker-vm.nu stop } | complete)
test-result "stop command fails without VM" ($stop_no_vm.exit_code != 0) "Should fail"
test-result "stop shows error message" (contains $stop_no_vm.stderr "does not exist") "Should show error"

log+ ""
log+ "=== Test 8: Restart command (non-existent VM) ==="

let restart_no_vm = (do -i { nu ../docker-vm.nu restart } | complete)
test-result "restart command fails without VM" ($restart_no_vm.exit_code != 0) "Should fail"
test-result "restart shows error message" (contains $restart_no_vm.stderr "does not exist") "Should show error"

log+ ""
log+ "=== Test 9: Exec command (non-existent VM) ==="

let exec_no_vm = (do -i { nu ../docker-vm.nu exec echo hello } | complete)
test-result "exec command fails without VM" ($exec_no_vm.exit_code != 0) "Should fail"
test-result "exec shows error message" (contains $exec_no_vm.stderr "does not exist") "Should show error"

log+ ""
log+ "=== Test 10: -h flag ==="

let help_h_result = (do -i { nu ../docker-vm.nu -h } | complete)
test-result "-h flag shows help" ($help_h_result.exit_code == 0) "Should succeed"

log+ ""
log+ "=== Test 11: --help flag ==="

let help_long_result = (do -i { nu ../docker-vm.nu --help } | complete)
test-result "--help flag shows help" ($help_long_result.exit_code == 0) "Should succeed"

log+ ""
log+ "=== Test 12: Constants are defined ==="

let const_check = (do -i { nu -c 'source ../docker-vm.nu; print $VM_NAME' } | complete)
test-result "VM_NAME constant defined" ($const_check.exit_code == 0) $"Exit code: ($const_check.exit_code)"

log+ ""
log+ "=== All tests completed ==="
