#!/bin/bash

input=$(cat)

dir=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
model_id=$(echo "$input" | jq -r '.model.id')
output_style=$(echo "$input" | jq -r '.output_style.name')

dim="\033[38;5;247m"
reset="\033[0m"
bold="\033[1m"
cyan="\033[36m"
yellow="\033[33m"
green="\033[32m"
red="\033[31m"
magenta="\033[35m"
blue="\033[34m"
orange="\033[38;5;208m"

# Color helper: green <50, yellow 50-79, red >=80
color_for_pct() {
    local p=$1
    if [ "$p" -ge 80 ]; then echo "$red"
    elif [ "$p" -ge 50 ]; then echo "$yellow"
    else echo "$green"; fi
}

# Context window runs hotter than quota: red >=45, orange 37-44, yellow 20-36
ctx_color_for_pct() {
    local p=$1
    if [ "$p" -ge 45 ]; then echo "$red"
    elif [ "$p" -ge 37 ]; then echo "$orange"
    elif [ "$p" -ge 20 ]; then echo "$yellow"
    else echo "$green"; fi
}

# 5-cell fill bar: filled cells take $2, empty cells stay grey.
# Scaled so the bar is full at 50% — anything past that is already red.
fill_bar() {
    local p=$1 color=$2 width=5 scale=50 i filled full="" empty=""
    filled=$((p * width / scale))
    [ "$filled" -gt "$width" ] && filled=$width
    for ((i = 0; i < filled; i++)); do full+="█"; done
    for ((i = filled; i < width; i++)); do empty+="░"; done
    printf "%s" "${color}${full}${reset}${dim}${empty}${reset}"
}

# Format a duration in seconds → "2h13m" / "47m" / "3d4h"
fmt_duration() {
    local s=$1
    [ "$s" -lt 0 ] && s=0
    local d=$((s / 86400))
    local h=$(((s % 86400) / 3600))
    local m=$(((s % 3600) / 60))
    if [ "$d" -gt 0 ]; then
        printf "%dd%dh" "$d" "$h"
    elif [ "$h" -gt 0 ]; then
        printf "%dh%dm" "$h" "$m"
    else
        printf "%dm" "$m"
    fi
}

# --- Line 1: orientation ---

git_info=""
if git -C "$dir" rev-parse --git-dir &>/dev/null; then
    branch=$(git -C "$dir" -c core.useBuiltinFSMonitor=false rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')
    if [ -n "$branch" ]; then
        if git -C "$dir" -c core.useBuiltinFSMonitor=false diff-index --quiet HEAD -- 2>/dev/null; then
            git_info="$branch"
        else
            git_info="${branch}*"
        fi
    fi
fi

short_model=$(echo "$model" | sed 's/Claude //' | sed 's/ /-/g')
if [[ "$model_id" == *"opus"* ]]; then
    model_str="${bold}${yellow}${short_model}${reset}"
elif [[ "$model_id" == *"sonnet"* ]]; then
    model_str="${cyan}${short_model}${reset}"
elif [[ "$model_id" == *"haiku"* ]]; then
    model_str="${blue}${short_model}${reset}"
else
    model_str="${short_model}"
fi

ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
[[ "$ctx_pct" =~ ^[0-9]+$ ]] || ctx_pct=0
ctx_color=$(ctx_color_for_pct "$ctx_pct")

now=$(date +%s)
fh_pct_raw=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
sd_pct_raw=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

effort=$(echo "$input" | jq -r '.effort.level // empty')
case "$effort" in
    max)    effort_str="${bold}${red}max${reset}" ;;
    xhigh)  effort_str="${bold}${red}xhigh${reset}" ;;
    high)   effort_str="${red}high${reset}" ;;
    medium) effort_str="${yellow}med${reset}" ;;
    low)    effort_str="${green}low${reset}" ;;
    "")     effort_str="" ;;
    *)      effort_str="${dim}${effort}${reset}" ;;
esac

sep="${dim} · ${reset}"
line="${model_str}"
[ -n "$effort_str" ] && line+="${sep}${dim}effort${reset} ${effort_str}"
[ -n "$git_info" ] && line+="${sep}${magenta}${git_info}${reset}"
line+="${sep}${dim}ctx${reset} $(fill_bar "$ctx_pct" "$ctx_color") ${ctx_color}${ctx_pct}%${reset}"

if [ -n "$fh_pct_raw" ] || [ -n "$sd_pct_raw" ]; then
    line+="${sep}${dim}usage${reset}"
fi

if [ -n "$fh_pct_raw" ]; then
    fh_pct=$(printf "%.0f" "$fh_pct_raw" 2>/dev/null || echo 0)
    fh_color=$(color_for_pct "$fh_pct")
    fh_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    fh_suffix=""
    [[ "$fh_reset" =~ ^[0-9]+$ ]] && fh_suffix=" ${dim}($(fmt_duration $((fh_reset - now))) left)${reset}"
    line+=" ${dim}5h${reset} ${fh_color}${fh_pct}%${reset}${fh_suffix}"
fi

if [ -n "$sd_pct_raw" ]; then
    sd_pct=$(printf "%.0f" "$sd_pct_raw" 2>/dev/null || echo 0)
    sd_color=$(color_for_pct "$sd_pct")
    sd_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
    sd_suffix=""
    [[ "$sd_reset" =~ ^[0-9]+$ ]] && sd_suffix=" ${dim}($(fmt_duration $((sd_reset - now))) left)${reset}"
    line+="${sep}${dim}7d${reset} ${sd_color}${sd_pct}%${reset}${sd_suffix}"
fi

if [ "$output_style" != "null" ] && [ "$output_style" != "default" ]; then
    line+="${sep}${dim}${output_style}${reset}"
fi

printf "%b" "$line"
