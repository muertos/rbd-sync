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
Usage:
  $0 --export|--sync <cpu-cores> <source_image> <dest_image> <source_pool> <dest_pool> <remote_host>

--export:  Performs a full export of the source image to the destination.
--sync:    Synchronizes the changes (using snapshots) between the source and destination.
"

show_help() {
    echo "$help_message"
}

#set -e

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
    show_help
    exit 1
    ;;
esac

cores=$1
image=$2
dest_image=$3
source_pool=$4
dest_pool=$5
remote=$6
current_snapshot=snap-1

function export_rbd_image() {
  echo "Exporting RBD image: $image from pool $source_pool"
  echo "Creating snapshot: $image@$current_snapshot"
  rbd snap create -p "$source_pool" "$image@$current_snapshot"

  # initial image migration
  snapshots=$(rbd -p "$source_pool" snap ls "$image" | awk 'NR > 1 {print $2}')
  if [[ -n $snapshots ]]; then
    first_snapshot=$(echo $snapshots | awk '{print $1}')
    echo "Exporting snapshot: $image@$first_snapshot"
    rbd -p "$source_pool" export "$image"@"$first_snapshot" - | \
      pigz -c --fast -p "$cores" | \
      ssh root@"$remote" "pigz -cd | rbd --dest-pool '$dest_pool' import - '$dest_image'"

    echo "Creating snapshot on $remote: $dest_image@$first_snapshot in pool $dest_pool"
    ssh root@"$remote" "rbd -p '$dest_pool' snap create '$dest_image'@'$first_snapshot'"

    # import remaining snapshots
    current=$first_snapshot
    remaining_snapshots=$(echo $snapshots | awk '{$1=""; print $0}')
    if [[ -n $remaining_snapshots ]]; then
      for snap in $remaining_snapshots; do
        echo "Exporting snapshot diff: $image@$current -> $snap"
        rbd -p "$source_pool" export-diff --from-snap "$current" "$image"@"$snap" - | \
          pigz -c --fast -p "$cores" | \
          ssh root@"$remote" "pigz -cd | rbd import-diff - '$dest_pool/$dest_image'"
        current=$snap
      done
    fi
  fi
}

function sync_rbd_diffs() {
  # TODO: add snap rollback to initial "snap-1"
  sync_snapshot=snap-sync-$(date +%s)
  echo "Syncing RBD image differences"
  echo "Creating snapshot: $image@$sync_snapshot"
  rbd snap create -p "$source_pool" "$image@$sync_snapshot"

  # Create new snapshot to capture differences and import
  rbd -p "$source_pool" export-diff --from-snap "$current_snapshot" "$image"@"$sync_snapshot" - | \
    pigz -c --fast -p "$cores" | \
    ssh root@"$remote" "pigz -cd | rbd import-diff - '$dest_pool/$dest_image'"
}

if [[ "$export_image" == "true" ]]; then
  export_rbd_image
fi

if [[ "$sync_image" == "true" ]]; then
  # TODO: ensure destination VMs are stopped prior to running
  sync_rbd_diffs
fi
