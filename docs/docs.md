# Documentation Index

Welcome to the documentation for the `linux-config` repository. Below is a list of available documentation files and a brief description of each.

## Configuration & Setup
- [**Setup**](setup.md) - Guide for initial setup and package installation using the bootstrap script.
- [**Operating Systems**](operating-systems.md) - Details on supported operating systems including PikaOS and Fedora.
- [**Logs**](logs.md) - Information about the timestamped log files recorded during setup.
- [**Stow Specification**](stow-spec.md) - Technical details and usage of the Nushell-based dotfiles manager.

## Server Management Tools
- [**Build Servers JSON**](build-servers-json.nu.md) - Interactive script to manually create a `servers.json` inventory.
- [**Proxmox Guest Discovery**](proxmox-guests.nu.md) - Interactive tool to discover Proxmox VMs/containers and generate server configs.
- [**SSH Copy ID**](ssh-copy-id.nu.md) - Utility to deploy SSH public keys to multiple servers from a JSON inventory.
- [**Generate tmuxp**](generate-tmuxp.nu.md) - Tool to convert a server inventory into a tmuxp multi-pane SSH configuration.

## Virtualization & Containers
- [**Docker VM**](docker-vm.md) - Management tool for running Docker inside an Incus-managed Debian VM.
- [**Distroboxes**](distroboxes.md) - Commands for managing multiple distrobox environments.
- [**Proxmox Toolkit**](proxmox.md) - Overview of Python-based helpers for Proxmox automation.

## Coding Standards
- [**Nushell Best Practices**](nushell-best-practices.md) - Guide for writing clean and idiomatic Nushell code.
