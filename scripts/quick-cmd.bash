#!/usr/bin/env bash

hold=""
for arg in "$@"; do
  case "$arg" in
  --hold) hold=1 ;;
  esac
done

kitty \
  --title "quick-run" \
  --class scratch-terminal \
  --override "remember_window_size=no" \
  --override "initial_window_width=800" \
  --override "initial_window_height=120" \
  bash -ic "printf '❯ '; read -r cmd; eval \"\$cmd\"; ${hold:+read -p 'Press enter to close...'}"
