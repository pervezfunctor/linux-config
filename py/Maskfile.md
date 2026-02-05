# Maskfile

## lint
Run Ruff lint checks.
```sh
pixi run lint
```

## lint:fix
Run Ruff lint checks and attempt to fix any issues.
```sh
pixi run lint-fix
```

## check
Run Pyright type checking followed by Ruff lint in one pass.
```sh
pixi run check
```

## format
Format code using Ruff's formatter.
```sh
pixi run fmt
```

## test
Execute unit tests for the Proxmox helpers.
```sh
pixi run test
```

## typecheck
Run Pyright in strict mode.
```sh
pixi run typecheck
```

## proxmox:dry-run
Example dry-run against a Proxmox host (override arguments as needed).
```sh
pixi run proxmox-dry-run -- "$@"
```

## proxmox:run
Run the maintenance script with custom arguments passed through.
```sh
pixi run proxmox-maintenance -- "$@"
```

## proxmox:batch
Run maintenance across every host defined in the manifest (override args as needed).
```sh
pixi run proxmox-batch -- "$@"
```

## proxmox:config
Launch the interactive manifest wizard to add or edit host entries.
```sh
pixi run proxmox-wizard -- "$@"
```

## proxmox:inventory
Discover guests on a host, verify SSH, and update the manifest with credentials.
```sh
pixi run proxmox-inventory -- "$@"
```
