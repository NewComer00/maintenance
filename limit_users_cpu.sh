#!/bin/bash

set -euo pipefail

# Check if systemctl is available
command -v systemctl >/dev/null 2>&1 || { echo >&2 "systemctl is required but not installed. Aborting."; exit 1; }

# Default flag values
DRY_RUN=0
VERBOSE=0
SHOW_ONLY=0

# Function to display help
display_help() {
    echo "Usage: $0 [OPTIONS] <CPU_QUOTA> <USER1> <USER2> ... <USER_N>"
    echo
    echo "Options:"
    echo "  -d, --dry-run        Show the commands that would be executed without running them"
    echo "  -v, --verbose        Enable verbose output"
    echo "  -s, --show           Show current CPUQuotaPerSecUSec for each user and exit"
    echo "  -h, --help           Display this help message and exit"
    echo
    echo "Arguments:"
    echo "  CPU_QUOTA            CPU quota to assign (e.g., 10%). Use '' to remove quota"
    echo "  USER1 ... USER_N     List of users to apply the CPU quota to"
    echo
    echo "Examples:"
    echo "  $0 -d 10% alice bob     # Dry run: show commands for setting 10% quota"
    echo "  $0 -v 10% alice         # Verbose: set 10% quota for user alice"
    echo "  $0 '' alice             # Remove CPU quota for user alice"
    echo "  $0 -s alice bob         # Show current CPUQuotaPerSecUSec for alice and bob"
    echo
    exit 0
}

# Function to validate if a user exists
user_exists() {
    local user="$1"
    getent passwd "$user" > /dev/null 2>&1
}

# Function to normalize time units (ms, s, m, etc.) to microseconds
normalize_to_usec() {
    local input="$1"
    local number unit

    if [[ "$input" =~ ^([0-9]+)([a-zA-Z]+)?$ ]]; then
        number="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]:-us}"  # Default to microseconds
        case "$unit" in
            us) echo "$number" ;;
            ms) echo $((number * 1000)) ;;
            s)  echo $((number * 1000000)) ;;
            m)  echo $((number * 1000)) ;;  # Sometimes systemd uses 'm' for milliseconds
            *)  echo 0 ;;
        esac
    else
        echo 0
    fi
}

# Check if arguments are passed, if not, display help
if [ $# -eq 0 ]; then
    display_help
fi

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run) DRY_RUN=1; shift ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -s|--show)    SHOW_ONLY=1; shift ;;
        -h|--help)    display_help ;;
        *)            break ;;
    esac
done

# Handle --show mode: display current CPUQuota for users
if [ $SHOW_ONLY -eq 1 ]; then
    if [ $# -eq 0 ]; then
        echo "Error: No users provided."
        display_help
    fi
    for user in "$@"; do
        if ! user_exists "$user"; then
            echo "User '$user' does not exist."
            continue
        fi
        uid=$(id -u "$user")
        slice="user-${uid}.slice"
        raw_usec=$(systemctl show "$slice" --property=CPUQuotaPerSecUSec | cut -d= -f2)

        # Handle case when CPUQuotaPerSecUSec is infinity
        if [ "$raw_usec" == "infinity" ]; then
            echo "$user ($slice): CPUQuotaPerSecUSec=infinity -> No CPU quota limit"
            continue
        fi

        usec=$(normalize_to_usec "$raw_usec")
        percent=$(awk -v us="$usec" 'BEGIN { printf "%.1f", (us / 10000) }')
        echo "$user ($slice): CPUQuotaPerSecUSec=$raw_usec -> CPUQuota=${percent}%"
    done
    exit 0
fi

# Parse CPU_QUOTA and users
CPU_QUOTA="${1:-}"
shift

if [ $# -eq 0 ]; then
    echo "Error: Too few arguments."
    display_help
fi

# Ensure CPU_QUOTA ends with a % sign, if not, add it
if [ -n "$CPU_QUOTA" ] && [[ "$CPU_QUOTA" != *% ]]; then
    CPU_QUOTA="${CPU_QUOTA}%"
fi

# Main loop: Set or remove CPUQuota for each user
for user in "$@"; do
    if ! user_exists "$user"; then
        echo "Warning: User '$user' does not exist. Skipping."
        continue
    fi

    uid=$(id -u "$user")
    slice="user-${uid}.slice"

    # Build the systemctl command based on CPU_QUOTA
    if [ -n "$CPU_QUOTA" ]; then
        CMD=(systemctl set-property "$slice" "CPUQuota=$CPU_QUOTA")
    else
        CMD=(systemctl set-property "$slice" "CPUQuota=")
    fi

    # Verbose mode: Show detailed info
    if [ $VERBOSE -eq 1 ]; then
        echo "[Verbose] User '$user' (UID $uid), slice '$slice': ${CMD[*]}"
    fi

    # Dry run mode: Only print the command without executing it
    if [ $DRY_RUN -eq 1 ]; then
        echo "[Dry-run] ${CMD[*]}"
    else
        "${CMD[@]}"
    fi
done
