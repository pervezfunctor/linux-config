#!/usr/bin/env nu

use ./lib.nu
use ./logs.nu

export def safe-ln [src: string, dest: string] {
    try {
        ^ln -sf $src $dest
        true
    } catch {
        false
    }
}

export def safe-rm [path: string] {
    try {
        ^rm -f $path
        true
    } catch {
        false
    }
}

export def safe-cp [src: string, dest: string] {
    try {
        ^cp $src $dest
        true
    } catch {
        false
    }
}

export def safe-mkdir [path: string] {
    try {
        mkdir $path
        true
    } catch {
        false
    }
}
