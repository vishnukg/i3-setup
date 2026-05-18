#!/bin/bash
if [ -f ~/.cache/lockscreen.png ]; then
    i3lock -i ~/.cache/lockscreen.png -e -n
else
    i3lock -c 1a1b2e -e -n
fi
