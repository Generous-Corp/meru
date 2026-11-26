#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: bash $0 <Pulp SDK root> <build root>" >&2
    exit 2
fi

sdk_root=$(cd "$1" && pwd -P)
build_root=$2
source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
pulp_dir="$sdk_root/lib/cmake/Pulp"
if [[ ! -f "$pulp_dir/PulpConfig.cmake" ]]; then
    echo "PulpConfig.cmake is missing from $pulp_dir" >&2
    exit 1
fi

export CMAKE_BUILD_PARALLEL_LEVEL=${CMAKE_BUILD_PARALLEL_LEVEL:-3}
export CTEST_PARALLEL_LEVEL=${CTEST_PARALLEL_LEVEL:-3}

build_and_test() {
    local build_dir="$build_root/$1"
    shift
    cmake -S "$source_root" -B "$build_dir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DBUILD_TESTING=ON -DPulp_DIR="$pulp_dir" "$@"
    cmake --build "$build_dir"
    ctest --test-dir "$build_dir" --output-on-failure --no-tests=error
}

# The Vellum editor option is introduced separately from this workflow.
if ! grep -Eiq '^[[:space:]]*option\([[:space:]]*BEADSY_VELLUM_EDITOR[[:space:]]' \
    "$source_root/CMakeLists.txt"; then
    build_and_test standard
    echo "Skipping Vellum editor build because this revision has no BEADSY_VELLUM_EDITOR option."
    exit 0
fi

build_and_test standard -DBEADSY_VELLUM_EDITOR=OFF
for vellum_config in "$sdk_root"/share/pulp/vellum-sdk/*/sdk/lib/cmake/Vellum/VellumConfig.cmake; do
    if [[ -f "$vellum_config" && -f "$pulp_dir/PulpVellumEditorPackage.cmake" ]]; then
        build_and_test vellum -DBEADSY_VELLUM_EDITOR=ON "-DVellum_DIR=${vellum_config%/*}"
        exit 0
    fi
done

echo "Skipping Vellum editor build because the Pulp SDK lacks the Vellum editor package."
