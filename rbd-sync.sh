#!/usr/bin/env bash

# Description:
#   Migrates or synchronizes RBD images between two Ceph clusters.
#   It supports two main operations:
#     - Export: Creates a snapshot of the source image on the destination cluster.
#     - Sync: Transfers only the differences between the source and destination images.
#
# Prerequisites:
#   Destination image created with Cinder of same size as original
#   The RBD image associated with the destination image must be deleted

help_message="
RBD Image Migration and Synchronization Script

Usage:
  $0 --flag <cpu-cores> <source_image_name> <destination_image_name> <pool> <remote_host>

--export:  Performs a full export of the source image to the destination.
--sync:    Synchronizes the changes (using snapshots) between the source and destination.

Prerequisites:
  Destination image created with Cinder of same size as original
  The RBD image associated with the destination image must be deleted
"

show_help() {
    echo "$help_message"
}

set -e

# process flags
case "$1" in
  --export)
    export_image=true
    shift
    ;;
  --sync)
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

cores=$1
image=$2 
dest_image=$3 
pool=$4
remote=$5
current_snapshot=snap-1

function export_rbd_image() {
  echo "Exporting RBD image: $image"
  echo "Creating snapshot: $image@$current_snapshot"
  rbd snap create -p "$pool" "$image@$current_snapshot"

  # initial image migration
  snapshots=$(rbd -p "$pool" snap ls "$image" | awk 'NR > 1 {print $2}')
  if [[ -n $snapshots ]]; then
    first_snapshot=$(echo $snapshots | awk '{print $1}')
    echo "Exporting snapshot: $image@$first_snapshot"
    taskset -c 0-$cores \
      rbd -p "$pool" export "$image"@"$first_snapshot" - | \
      pigz -c --fast | \
      ssh root@"$remote" "pigz -cd | rbd --dest-pool '$pool' import - '$dest_image'"

    echo "Creating snapshot on $remote: $dest_image@$first_snapshot"
    ssh root@"$remote" "rbd -p '$pool' snap create '$dest_image'@'$first_snapshot'"

    # import remaining snapshots
    current=$first_snapshot
    remaining_snapshots=$(echo $snapshots | awk '{$1=""; print $0}')
    if [[ -n $remaining_snapshots ]]; then
      for snap in $remaining_snapshots; do
        echo "Exporting snapshot: $image@$current"
        taskset -c 0-$cores \
          rbd -p "$pool" export-diff --from-snap "$current" "$image"@"$snap" - | \
          pigz -c --fast | \
          ssh root@"$remote" "pigz -cd | rbd -p '$pool' import-diff - '$dest_image'" 
        current=$snap
      done
    fi
  fi
}

function sync_rbd_diffs() {
  sync_snapshot=snap-sync-$(date +%s)
  echo "Syncing RBD image differences"
  echo "Creating snapshot: $image@$sync_snapshot"
  rbd snap create -p "$pool" "$image@$sync_snapshot"

  # Create new snapshot to capture differences and import
  taskset -c 0-$cores \
    rbd -p "$pool" export-diff --from-snap "$current_snapshot" "$image"@"$sync_snapshot" - | \
    pigz -c --fast | \
    ssh root@"$remote" "pigz -cd | rbd -p '$pool' import-diff - '$dest_image'"
}

if [[ "$export_image" == "true" ]]; then
  export_rbd_image
fi

if [[ "$sync_image" == "true" ]]; then
  sync_rbd_diffs
fi