#!/bin/bash

WIDTH=$(swaymsg -t get_tree | jq '.. | select(.type?) | select(.focused==true).rect.width')
SCREEN_WIDTH=$(swaymsg -t get_outputs | jq '.[] | select(.focused==true).rect.width')

SIZE1=$(echo "$SCREEN_WIDTH * 0.33" | bc | cut -d. -f1)
SIZE2=$(echo "$SCREEN_WIDTH * 0.50" | bc | cut -d. -f1)
SIZE3=$(echo "$SCREEN_WIDTH * 0.66" | bc | cut -d. -f1)

if [ "$WIDTH" -lt "$SIZE2" ]; then
  swaymsg resize set width "$SIZE2" px
elif [ "$WIDTH" -lt "$SIZE3" ]; then
  swaymsg resize set width "$SIZE3" px
else
  swaymsg resize set width "$SIZE1" px
fi
