# Operating Systems Supported

## PikaOS Niri Edition

I currently use this setup on [PikaOS](https://wiki.pika-os.com/en/home). PikaOS is based on Debian. I replace `pikabar` and related utilities with [dms](https://danklinux.com/).

If you have never used PikaOS before, I would recommend you to spend a few days with the default `niri` setup before switching to this.

Note that system package manager(`apt`) is painfully slow compared to `dnf` or `pacman` and setup will take a long time.

## Fedora OS

Setup script can optionally install `niri` and `dms` on Fedora. This is the secondary OS I use fairly regularly. You could install Fedora using any of it's official variants, something like sway should work fine too. I use `Fedora Everything` to install basic system software and use script from this repository to setup niri.

## Ubuntu Questing(25.04)

I don't use Ubuntu. Even though I believe this should work fine, this setup might not work currently. I would recommend you to either use Fedora or PikaOS.

## NixOS

If you are using NixOS, use my [nixos-config](https://github.com/pervezfunctor/nix-config) repository.
