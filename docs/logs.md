# Logs

Every invocation of the bootstrap script records a timestamped log file under `~/.linux-config-logs`. Set `LINUX_CONFIG_LOG_DIR=/path/to/logs` if you want to capture runs elsewhere (useful in disposable environments or CI).

## Viewing Logs

Use the `view-logs.nu` helper script to inspect logs:

In Nushell, pass flags after the subcommand they belong to. For example, use `view-logs.nu show --dir /tmp/my-logs`, not `view-logs.nu --dir /tmp/my-logs show`.

```bash
# View the most recent log (shows all lines by default)
~/.linux-config/nu/view-logs.nu show

# Show only errors/warnings/fatal messages
~/.linux-config/nu/view-logs.nu show --pattern "(?i)error|fatal|warn"

# Interactively pick a log file (requires gum)
~/.linux-config/nu/view-logs.nu show --pick-log

# Text-based interactive selection
~/.linux-config/nu/view-logs.nu show --select

# View a specific log by timestamp
~/.linux-config/nu/view-logs.nu show --timestamp 03-03-012721
```

## Filtering Options

### Level Filter (`-l`, `--level`)

Filter by log level. Valid levels: `all`, `info`, `error`, `warning`/`warn`, `debug`, `trace`.

```bash
# Show only INFO lines
~/.linux-config/nu/view-logs.nu show --level info

# Combine with pattern
~/.linux-config/nu/view-logs.nu show --level info --pattern "install"
```

### Pattern Filter (`-p`, `--pattern`)

Filter lines by regex pattern. The default pattern is `.*` (show all lines).

```bash
# Show only lines containing "install"
~/.linux-config/nu/view-logs.nu show --pattern "install"

# Show errors and warnings (case-insensitive)
~/.linux-config/nu/view-logs.nu show --pattern "(?i)error|fatal|warn|unknown"

# Case-insensitive match
~/.linux-config/nu/view-logs.nu show --pattern "(?i)ERROR|FAIL"
```

## Log Selection Options

| Flag                        | Description                                |
| --------------------------- | ------------------------------------------ |
| (none)                      | Show most recent log                       |
| `-g`, `--pick-log`          | Interactive picker using gum               |
| `-s`, `--select`            | Text-based interactive selection           |
| `-t`, `--timestamp <stamp>` | Select by timestamp (e.g., `03-03-012721`) |

## Cleaning Logs

Keep only the latest log and remove older ones:

```bash
~/.linux-config/nu/view-logs.nu clean
```

## Environment Variables

- `LINUX_CONFIG_LOG_DIR` - Override the default log directory (`~/.linux-config-logs`)

## Examples

```bash
# View the most recent log (all lines)
~/.linux-config/nu/view-logs.nu show

# View only errors/warnings
~/.linux-config/nu/view-logs.nu show --pattern "(?i)error|warn|fatal"

# Pick a log interactively and show all lines
~/.linux-config/nu/view-logs.nu show --pick-log

# Show INFO lines matching "package" from a specific log
~/.linux-config/nu/view-logs.nu show --timestamp 03-03-012721 --level info --pattern "package"

# Use alternate log directory
LINUX_CONFIG_LOG_DIR=/tmp/my-logs ~/.linux-config/nu/view-logs.nu show

# Specify directory via flag
~/.linux-config/nu/view-logs.nu show --dir /tmp/my-logs

# Clean logs in an alternate directory
~/.linux-config/nu/view-logs.nu clean --dir /tmp/my-logs
```
