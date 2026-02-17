#!/usr/bin/env nu

use std/log

print "============================================"
print "DISTROBOXES TEST SUITE"
print "============================================"
print ""

# Step 1: Create all distroboxes
print "[1/6] Testing create-all..."
print "--------------------------------------------"
./bin/distroboxes.nu create-all
print ""

# Step 2: Exec all - test with uname
print "[2/6] Testing exec-all..."
print "--------------------------------------------"
./bin/distroboxes.nu exec-all echo "Hello from distrobox"
print ""

# Step 3: Enter specific distrobox and run command
print "[3/6] Testing enter (debian)..."
print "--------------------------------------------"
./bin/distroboxes.nu enter debian cat /etc/os-release
print ""

# Step 4: Restart all
print "[4/6] Testing restart-all..."
print "--------------------------------------------"
./bin/distroboxes.nu restart-all
print ""

# Step 5: Stop all
print "[5/6] Testing stop-all..."
print "--------------------------------------------"
./bin/distroboxes.nu stop-all
print ""

# Step 6: List to confirm stopped
print "[5.5/6] Verifying stopped status..."
print "--------------------------------------------"
./bin/distroboxes.nu list
print ""

# Step 7: Remove all
print "[6/6] Testing remove-all..."
print "--------------------------------------------"
./bin/distroboxes.nu remove-all --yes
print ""

print "============================================"
print "TEST COMPLETE!"
print "============================================"
