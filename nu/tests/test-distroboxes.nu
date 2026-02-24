#!/usr/bin/env nu

use std/log

print "============================================"
print "DISTROBOXES TEST SUITE"
print "============================================"
print ""

print "[1/6] Testing create-all..."
print "--------------------------------------------"
../distroboxes.nu create-all
print ""

print "[2/6] Testing exec-all..."
print "--------------------------------------------"
../distroboxes.nu exec-all echo "Hello from distrobox"
print ""

print "[3/6] Testing enter (debian-tmuxp)..."
print "--------------------------------------------"
../distroboxes.nu enter debian-tmuxp cat /etc/os-release
print ""

# Step 4: Enter all distroboxes sequentially
print "[4/6] Testing enter-all..."
print "--------------------------------------------"
../distroboxes.nu enter-all
print ""

print "[5/6] Testing restart-all..."
print "--------------------------------------------"
../distroboxes.nu restart-all
print ""

print "[6/6] Testing stop-all..."
print "--------------------------------------------"
../distroboxes.nu stop-all
print ""

print "[6.5/6] Verifying stopped status..."
print "--------------------------------------------"
../distroboxes.nu list
print ""

print "[7/7] Testing remove-all..."
print "--------------------------------------------"
../distroboxes.nu remove-all --yes
print ""

print "============================================"
print "TEST COMPLETE!"
print "============================================"
