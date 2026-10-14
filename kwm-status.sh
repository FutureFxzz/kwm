#!/usr/bin/env bash
set -u

fifo="$HOME/.cache/kwm-status.fifo"
mkdir -p "$HOME/.cache"
[[ -p "$fifo" ]] || mkfifo "$fifo"

# Keep the FIFO writer open.
exec 3>"$fifo"

read_cpu() {
    read -r _ u n s i w irq sirq st rest </proc/stat
    echo "$((u+n+s+i+w+irq+sirq+st)) $i"
}

read -r prev_total prev_idle < <(read_cpu)

INTERVAL=0.75
network="OFFLINE"
next_net_check=0

while sleep "$INTERVAL"; do
    read -r total idle < <(read_cpu)
    dt=$((total-prev_total))
    di=$((idle-prev_idle))
    cpu=0
    (( dt > 0 )) && cpu=$(( (dt-di)*100/dt ))
    prev_total=$total
    prev_idle=$idle
    
    # Network status (check every 5 seconds)
    if (( SECONDS >= next_net_check )); then
        network=$(nmcli -t -f TYPE,STATE device status 2>/dev/null |
            awk -F: '
                $2 == "connected" && $1 == "wifi" { wifi=1 }
                $2 == "connected" && $1 == "ethernet" { lan=1 }
                END {
                    if (wifi) print "Wi-Fi"
                    else if (lan) print "LAN"
                    else print "OFFLINE"
                }')

        network=${network:-OFFLINE}
        next_net_check=$((SECONDS + 5))
    fi

    ram=$(free | awk '/^Mem:/ {printf "%d", ($3/$2)*100}')
    clock=$(date '+%H:%M')
    date_str=$(date '+%d %b')

    # PipeWire volume
    vol_info=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
    if [[ "$vol_info" == *"[MUTED]"* ]]; then
        volume="MUTED"
    elif [[ "$vol_info" =~ Volume:\ ([0-9.]+) ]]; then
        volume=$(( $(printf "%.0f" "$(echo "${BASH_REMATCH[1]} * 100" | bc -l)") ))
    else
        volume="N/A"
    fi

        printf '^#c777ffff CPU %s%%  ^#828bb8ff│ RAM %s%%  │ VOL %s  │ NET %s  │ %s %s^#!\n' \
        "$cpu" "$ram" "$volume" "$network" "$date_str" "$clock" >&3
done
