#!/bin/bash

# Exit on errors, unset variables, and pipeline failures
set -euo pipefail

# Default values for flags
DRY_RUN=0
VERBOSE=0

# Function to display help
display_help() {
    echo "Usage: $0 [-d|--dry-run] [-v|--verbose] <CPU_QUOTA> <USER1> <USER2> ... <USER_N>"
    echo
    echo "   -d, --dry-run      Display the commands that would be executed, without making any changes."
    echo "   -v, --verbose      Display detailed information about each operation."
    echo "   CPU_QUOTA          The CPU quota (as a percentage, e.g., '10%') to set for each user slice."
    echo "                      To remove the CPU quota, use an empty value for CPU_QUOTA."
    echo "   USER1 ... USER_N   List of usernames to apply the CPU quota to."
    echo
    echo "Example:"
    echo "   $0 -d 10% user1 user2     # Display the commands without executing them."
    echo "   $0 -v 10% user1 user2     # Display detailed information during execution."
    echo "   $0 10% user1 user2        # Set the CPU quota to 10% for user1 and user2."
    echo "   $0 '' user1 user2         # Remove the CPU quota for user1 and user2."
    exit 0
}

# Check for --help argument
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    display_help
fi

# Check for --dry-run and --verbose flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        *)
            break
            ;;
    esac
done

# The first non-option argument should be CPU_QUOTA
CPU_QUOTA="$1"
shift  # Now $@ are users

# Check if any users were provided
if [ $# -eq 0 ]; then
    echo "Error: No users provided."
    display_help
fi

# Function to validate if a user exists
user_exists() {
    local user="$1"
    if getent passwd "$user" > /dev/null 2>&1; then
        return 0  # User exists
    else
        return 1  # User does not exist
    fi
}

# If verbose mode is enabled, display what we are about to do
if [ $VERBOSE -eq 1 ]; then
    echo "Setting CPU quota to '$CPU_QUOTA' for the following users: $@"
    if [ $DRY_RUN -eq 1 ]; then
        echo "Dry-run mode is enabled: No changes will be made."
    fi
fi

# Loop through all users and apply CPU quota
for user in "$@"; do
    # Validate if the user exists
    if ! user_exists "$user"; then
        echo "Warning: User '$user' does not exist. Skipping."
        continue
    fi

    # Get the user ID (UID) for the user
    user_id=$(id -u "$user")

    # Define the slice name using the user ID
    slice="user-${user_id}.slice"

    # Construct the systemd command for setting CPUQuota
    if [ -n "$CPU_QUOTA" ]; then
        # Ensure the CPU_QUOTA has the percentage sign
        if [[ "$CPU_QUOTA" != *% ]]; then
            CPU_QUOTA="${CPU_QUOTA}%"
        fi
        # Set the specified CPUQuota
        CMD="systemctl set-property $slice CPUQuota=$CPU_QUOTA"
    else
        # Remove the CPUQuota (empty value)
        CMD="systemctl set-property $slice CPUQuota="
    fi

    # If verbose mode is enabled, print what is happening
    if [ $VERBOSE -eq 1 ]; then
        echo "Executing command for $user (UID: $user_id): $CMD"
    fi

    # Dry-run mode: print the command, but do not execute
    if [ $DRY_RUN -eq 1 ]; then
        echo "Dry-run: $CMD"
    else
        # Execute the command to set or remove the CPUQuota
        eval "$CMD"
    fi
done
