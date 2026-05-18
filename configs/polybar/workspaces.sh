#!/bin/bash
i3-msg -t get_workspaces | python3 -c "
import json, sys

colors = ['', '#89b4fa', '#a6e3a1', '#cba6f7', '#74c7ec', '#b4befe', '#94e2d5', '#f9e2af', '#f5c2e7', '#89b4fa', '#a6e3a1']
text_dark = '#000000'

def dim(hex_color, factor=0.35):
    r = int(int(hex_color[1:3], 16) * factor)
    g = int(int(hex_color[3:5], 16) * factor)
    b = int(int(hex_color[5:7], 16) * factor)
    return f'#{r:02x}{g:02x}{b:02x}'

workspaces = json.load(sys.stdin)
workspaces.sort(key=lambda w: w['num'])
parts = []
for ws in workspaces:
    num = min(ws['num'], len(colors) - 1)
    color = colors[num]
    name = ws['name']
    click = f'i3-msg workspace \"{name}\"'
    if ws['focused']:
        parts.append(f'%{{B{color}}}%{{F{text_dark}}}%{{A1:{click}:}} {name} %{{A}}%{{B-}}%{{F-}}')
    elif ws['urgent']:
        parts.append(f'%{{B#e06c75}}%{{F{text_dark}}}%{{A1:{click}:}} {name} %{{A}}%{{B-}}%{{F-}}')
    else:
        parts.append(f'%{{B{dim(color)}}}%{{F{text_dark}}}%{{A1:{click}:}} {name} %{{A}}%{{B-}}%{{F-}}')
print(''.join(parts))
"
