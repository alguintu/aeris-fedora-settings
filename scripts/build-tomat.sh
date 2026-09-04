#!/usr/bin/bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tomat/source.env"
[[ $tomat_revision =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid Tomat source pin.' >&2; exit 1; }
tomat_cache=${XDG_CACHE_HOME:-$HOME/.cache}/aeris-tomat-build
source_dir=$tomat_cache/source/$tomat_revision
target_dir=$tomat_cache/target/$tomat_revision
for dependency in cargo git pkg-config; do
    command -v "$dependency" >/dev/null || { echo "Missing build dependency: $dependency" >&2; exit 1; }
done

# Prefer system development files; a user-local Fedora ALSA sysroot also works.
# This does not change the runtime library or disable audio.
if ! pkg-config --exists alsa; then
    if [[ -f $tomat_cache/sysroot/usr/lib64/pkgconfig/alsa.pc ]]; then
        export PKG_CONFIG_SYSROOT_DIR=$tomat_cache/sysroot
        export PKG_CONFIG_PATH=$tomat_cache/sysroot/usr/lib64/pkgconfig
    else
        echo 'ALSA build files are required (Fedora: alsa-lib-devel, pkgconf-pkg-config).' >&2
        echo 'Install them or provide PKG_CONFIG_PATH/PKG_CONFIG_SYSROOT_DIR for a local sysroot.' >&2
        exit 1
    fi
fi
pkg-config --exists alsa

if [[ ! -d $source_dir/.git ]]; then
    mkdir -p -- "$source_dir"
    git -C "$source_dir" init --quiet
    git -C "$source_dir" remote add origin "$tomat_repository"
    git -C "$source_dir" fetch --depth=1 origin "$tomat_revision"
    git -C "$source_dir" checkout --detach FETCH_HEAD
fi
[[ $(git -C "$source_dir" rev-parse HEAD) == "$tomat_revision" ]] || {
    echo "Wrong source revision in $source_dir; leaving it untouched." >&2; exit 1;
}
[[ -z $(git -C "$source_dir" status --porcelain --untracked-files=no) ]] || {
    echo "Modified source in $source_dir; leaving it untouched." >&2; exit 1;
}
# Upstream build.rs uses root-relative asset paths, so build from its checkout.
(cd -- "$source_dir" && cargo build --release --locked --target-dir "$target_dir")
[[ $("$target_dir/release/tomat" --version) == "tomat $tomat_version" ]]
"$target_dir/release/tomat" seek --help >/dev/null
echo "Built $tomat_version from $tomat_revision"
