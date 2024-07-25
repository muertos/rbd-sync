#!/usr/bin/env bash

# Description:
#   Migrates or synchronizes RBD images between two Ceph clusters.
#   It supports two main operations:
#     - Export: Creates a snapshot of the source image on the destination cluster.
#     - Sync: Transfers only the differences between the source and destination images.
# 
# Prerequisites:
#   Destination volume created with Cinder of same size as original
#   The RBD image associated with the destination volume must be deleted

help_message="
RBD Image Migration and Synchronization Script

Usage:
  $0 --flag <source_volume_name> <destination_volume_name> <pool> <remote_host>

--export-rbd-image:  Performs a full export of the source image to the destination.
--sync-rbd-image:    Synchronizes the changes (using snapshots) between the source and destination.

Prerequisites:
  Destination volume created with Cinder of same size as original
  The RBD image associated with the destination volume must be deleted
"

show_help() {
    echo "$help_message"
}

set -e

export_image=false
sync_image=false
initial_snapshot=snap-1
latest_snapshot=snap-2

# process flags
case "$1" in 
  --export-rbd-image)
    export_image=true
    shift
    ;;
  --sync-rbd-image)
    sync_image=true
    shift
    ;;
  --help)
    show_help
    exit 0
    ;;
  *)
    echo "Invalid flag: $1" >&2 
    show_help
    exit 1
    ;;
esac

volume=$1 # "volume-8231313d-37d7-4c58-942d-68a4d9ea38d8"
dest_volume=$2 # "volume-3e19dc0b-cff2-4599-807a-9b60e97daaee"
pool=$3
remote=$4

function export_rbd_image() {
  echo "Exporting RBD image $volume"
  # Snapshot image
  echo "Creating snapshot: $volume@$initial_snapshot"
  rbd snap create -p "$pool" "$volume@$initial_snapshot"

  # Export and import RBD image
  rbd export -p "$pool" --image "$volume" --snap "$initial_snapshot" - | \
    pigz -c --fast | \
    ssh root@$remote "pigz -cd | rbd import --dest-pool '$pool' - volumes/'$dest_volume'"
}

function sync_rbd_diffs() {
  echo "Syncing RBD image differences"
  # Create original snapshot in destination image
  echo "Creating remote snapshot: $dest_volume@$initial_snapshot"
  ssh root@$remote "rbd -p '$pool' snap create '$dest_volume@$initial_snapshot'"

  # Create latest snapshot
  echo "Creating snapshot: $volume@$latest_snapshot"
  rbd snap create -p "$pool" "$volume@$latest_snapshot"

  # Create new snapshot to capture differences and import
  rbd -p "$pool" export-diff --image "$volume" --snap "$latest_snapshot" --from-snap "$initial_snapshot" - | \
    ssh root@$remote "rbd -p '$pool' import-diff - '$dest_volume'"
}

if [[ "$export_image" == "true" ]]; then
  export_rbd_image
fi

if [[ "$sync_image" == "true" ]]; then
  sync_rbd_diffs
fi
