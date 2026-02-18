# Logs

Every invocation of the bootstrap script records a timestamped log file under `~/.linux-config-logs`. Set `LINUX_CONFIG_LOG_DIR=/path/to/logs` if you want to capture runs elsewhere (useful in disposable environments or CI). Once the repository is cloned you can inspect or prune logs with the helper script:

```bash
~/.local/share/linux-config/bin/logs show           # view the most recent log
~/.local/share/linux-config/bin/logs show --select  # pick a specific timestamp interactively
~/.local/share/linux-config/bin/logs clean          # keep only the latest log
```

Pass `--dir /alternate/path` (before the `show`/`clean` command) or export `LINUX_CONFIG_LOG_DIR` to inspect archives that live outside the default location.
