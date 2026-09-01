# Storage

## Layout

| Purpose | Model | Linux device | Configuration |
|---|---|---|---|
| Fedora system | Samsung 990 PRO 1 TB | `/dev/nvme0n1` | Btrfs root and home |
| Hackintosh experiments | Lexar NM620 512 GB | `/dev/nvme1n1` | Reserved; do not format from Fedora |
| Bulk storage | Seagate 4 TB | `/dev/sda1` | Btrfs label `Storage`, mounted at `/mnt/storage` |

The bulk-storage mount uses:

```text
btrfs defaults,noatime,compress=zstd:1,nofail 0 0
```

The filesystem root at `/mnt/storage` is owned by the local user. The persistent
mount is defined by filesystem UUID in `/etc/fstab`; the UUID is intentionally
not copied into this repository.
