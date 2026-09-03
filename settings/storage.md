# Storage

## Layout

| Purpose | Model | Linux device | Configuration |
|---|---|---|---|
| Fedora system and regular AI models | Samsung 990 PRO 1 TB | `/dev/nvme0n1` | Btrfs root and home; models at `/home/drei/AI/models` |
| Hackintosh experiments | Lexar NM620 512 GB | `/dev/nvme1n1` | Reserved; do not format from Fedora |
| Workspace and AI testing | Samsung 860 EVO 1 TB | Device letters may change | Btrfs label `Workspace`, mounted at `/mnt/workspace` |
| Documents | Seagate BarraCuda SSD 500 GB | Device letters may change | Btrfs label `Documents`, mounted at `/mnt/documents` |
| Bulk storage | Seagate 4 TB | Device letters may change | Btrfs label `Storage`, mounted at `/mnt/storage` |

The persistent mounts use filesystem UUIDs in `/etc/fstab`; UUIDs are
intentionally not copied into this repository. The removable device letters are
not treated as identities.

The Btrfs data mounts use:

```text
btrfs defaults,noatime,compress=zstd:1,nofail,x-gvfs-show 0 0
```

The filesystem roots are owned by the local user. `/mnt/workspace/AI` is the
scratch area for AI downloads, comparisons, and LM Studio experiments. Main
models that are used regularly are promoted to `/home/drei/AI/models` on the
990 PRO.
