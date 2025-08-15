#!/bin/bash

# This script automates the execution of rbd-sync.sh for all volumes
# listed in a mapping file, dynamically selecting the correct source pool.

# --- Configuration ---
RBD_SYNC_SCRIPT="./rbd-sync.sh"
# The Ceph pool where Nova stores ephemeral disks on the source
EPHEMERAL_POOL="vms"
# The destination pool for all Cinder volumes is hardcoded
DEST_CINDER_POOL="volumes"
# ---

# --- Help Message ---
help_message="
Usage:
  $0 <--export|--sync> <mapping-file.csv> <cpu-cores> <source-cinder-pool> <remote_host>

Example (Initial Export):
  $0 --export volume_id_map.csv 8 volumes root@destination-host
"

# --- Script Logic ---
if [ "$#" -ne 5 ]; then
    echo "Error: Invalid number of arguments."
    echo "$help_message"
    exit 1
fi

OPERATION=$1
MAP_FILE=$2
CORES=$3
SOURCE_CINDER_POOL=$4
REMOTE_HOST=$5

# Validate required files exist
if [ ! -f "$MAP_FILE" ]; then
    echo "Error: Mapping file '$MAP_FILE' not found."
    exit 1
fi
if [ ! -x "$RBD_SYNC_SCRIPT" ]; then
    echo "Error: rbd-sync.sh script not found or not executable."
    exit 1
fi

# Read the mapping file into an array to make the loop robust.
mapfile -t lines < <(tail -n +2 "$MAP_FILE")

# Loop through the lines stored in the array.
for line in "${lines[@]}"; do
    # Sanitize and parse the source and destination volumes.
    source_volume=$(echo "$line" | tr -d '\r' | cut -d, -f1)
    dest_volume=$(echo "$line" | tr -d '\r' | cut -d, -f2)

    # Determine the correct source pool based on the image name
    if [[ "$source_volume" == *"_disk" ]]; then
      # This is an ephemeral disk from a boot-from-image VM
      CURRENT_SOURCE_POOL="$EPHEMERAL_POOL"
    else
      # This is a Cinder volume
      CURRENT_SOURCE_POOL="$SOURCE_CINDER_POOL"
    fi

    echo "=========================================================="
    echo "Processing Source: $source_volume (from pool: $CURRENT_SOURCE_POOL)"
    echo "       ->   Dest: $dest_volume (to pool: $DEST_CINDER_POOL)"
    echo "=========================================================="
    
    # Call rbd-sync.sh inside a subshell to completely isolate its process
    # Pass both the source and the hardcoded destination pool
    ( "$RBD_SYNC_SCRIPT" "$OPERATION" "$CORES" "$source_volume" "$dest_volume" "$CURRENT_SOURCE_POOL" "$DEST_CINDER_POOL" "$REMOTE_HOST" < /dev/null )
    
    echo
done

echo "All volumes have been processed."
