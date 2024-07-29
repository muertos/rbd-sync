# RBD Sync
Migrates or synchronizes RBD images, including snapshots, between two Ceph clusters for a specific pool.
- `--export`: Snapshots source image and exports all snapshots of image into destination.
- `--sync`: Transfers only the differences between the source and destination images. Will fail if `--export` has not been used initially.

Only boot a VM with the migrated volume after performing a sync of the RBD image data, otherwise the filesystem may be corrupt resulting in a VM that does not boot.

This was created to aid in performing an OpenStack migration of VMs from a source cloud to a destination cloud. Data is streamed using `rbd` over SSH. This tool allows an operator to perform an initial copy of the RBD image data to effectively stage the destination cloud, and then perform a sync of the image data some time later. If you're able to use Ceph RBD mirroring, that is probably a better option.
 
Use at your own risk!

## Requirements
- Root access to remote Ceph cluster over SSH
- Pools of the same name already created in both Ceph clusters

## Usage
Before using this tool, ensure you:
- Create a volume in destination cluster that is the same size as the source image
- Take note of the RBD image name associated with the volume created in the destination cluster
- Delete the RBD image in the destination cloud associated with the volume created in the first step

You will need the RBD source image name, the destination RBD image name, and the pool name from which the image is being migrated.

```sh
# Export and import an image
./rbd-export.sh --export <source_volume_name> <destination_volume_name> <pool> <remote_host>

# Sync differences of an image
./rbd-export.sh --sync <source_volume_name> <destination_volume_name> <pool> <remote_host>
```
