#!/usr/bin/bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
shader_dir=$script_dir/../quickshell/aeris-dashboard/shaders
qsb_bin=${QSB:-/usr/lib64/qt6/bin/qsb}
if [[ ! -x "$qsb_bin" ]]; then
    echo "Qt 6 Shader Tools are required to rebuild shaders (Fedora: qt6-qtshadertools)." >&2
    exit 1
fi
# Ship the compiled pack too: running the dashboard needs no compiler.
for shader in daylight heatmap; do
    "$qsb_bin" --glsl '100 es,120,150' --hlsl 50 --msl 12 \
        -o "$shader_dir/$shader.frag.qsb" "$shader_dir/$shader.frag"
done
