#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.cache"
IMAGE_NAME="liuys36/dameng"
MANIFEST_TAG="8-slim"

detect_arch() {
    local zip="$1"
    local basename
    basename=$(basename "$zip")
    case "$basename" in
        *arm*|*aarch64*) echo "arm64"  ;;
        *x86*|*amd64*)   echo "amd64"  ;;
        *x86_64*)        echo "amd64"  ;;
        *)               echo "unknown" ;;
    esac
}

extract() {
    local zip="$1"
    local arch="$2"
    local installer="${CACHE_DIR}/DMInstall-${arch}.bin"

    [ -f "$installer" ] && { echo "  DMInstall-${arch}.bin already exists, skip."; return 0; }

    mkdir -p "$CACHE_DIR"
    echo "Extracting DMInstall-${arch}.bin from $(basename "$zip")..."
    local iso
    iso="${CACHE_DIR}/$(basename "$zip" .zip).iso"
    unzip -o "$zip" -d "$CACHE_DIR" 2>/dev/null || { echo "Error: unzip failed."; exit 1; }
    [ ! -f "$iso" ] && { echo "Error: ISO not found in zip."; exit 1; }

    if command -v 7z &>/dev/null; then
        7z e "$iso" -o"$CACHE_DIR" DMInstall.bin -y 2>/dev/null
        mv "${CACHE_DIR}/DMInstall.bin" "$installer"
    elif command -v xorriso &>/dev/null; then
        xorriso -osirrox on -indev "$iso" -extract /DMInstall.bin "$installer" 2>/dev/null
    elif command -v isoinfo &>/dev/null; then
        isoinfo -R -x /DMINSTALL.BIN -i "$iso" > "$installer" 2>/dev/null
    else
        echo "Error: Need 7z, xorriso, or isoinfo to extract ISO."
        echo "Install: brew install p7zip"
        exit 1
    fi
    chmod +x "$installer"
    rm -f "$iso"
    echo "Extraction done."
}

build_arch() {
    local arch="$1"
    local zip="$2"
    local push="$3"

    local platform="linux/${arch}"
    local image_tag="${IMAGE_NAME}:8-${arch}"
    local installer_src="${CACHE_DIR}/DMInstall-${arch}.bin"
    local installer_dst="${SCRIPT_DIR}/DMInstall-${arch}.bin"

    [ ! -f "$installer_src" ] && { echo "Error: ${installer_src} not found."; exit 1; }
    cp "$installer_src" "$installer_dst"

    if [ "$push" = "true" ]; then
        echo "Building & pushing ${image_tag} (${platform}) ..."
        docker buildx build --platform "$platform" --push \
            -t "$image_tag" \
            --build-arg "DM8_ARCH=${arch}" \
            --build-arg "DM8_ZIP=$(basename "$zip")" \
            -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
    else
        echo "Building ${image_tag} (${platform}) ..."
        docker buildx build --platform "$platform" --load \
            -t "$image_tag" \
            --build-arg "DM8_ARCH=${arch}" \
            --build-arg "DM8_ZIP=$(basename "$zip")" \
            -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
    fi
    rm -f "$installer_dst"
    echo "Build complete: ${image_tag}"
}

push_manifest() {
    local archs=("$@")
    local targets=()

    for a in "${archs[@]}"; do
        targets+=("${IMAGE_NAME}:8-${a}")
    done

    echo "Creating & pushing multi-arch manifest ${IMAGE_NAME}:${MANIFEST_TAG} ..."
    docker buildx imagetools create \
        -t "${IMAGE_NAME}:${MANIFEST_TAG}" \
        "${targets[@]}"
    echo "Done: ${IMAGE_NAME}:${MANIFEST_TAG} (multi-arch: ${archs[*]})"
}

clean() {
    rm -rf "${CACHE_DIR}"
    echo "Cleaned cache directory."
}

usage() {
    cat <<EOF
Usage: $0 {build|push|manifest|clean} [options]

Commands:
  build         Build Docker image (default)
    --arch ARCH Target architecture: amd64 or arm64
    --all       Build for all available architectures
    --push      Build, push and create multi-arch manifest
  push          Push existing local images and create multi-arch manifest
  manifest      Create and push multi-arch manifest from registry images
  clean         Remove cache directory

Tags:  ${IMAGE_NAME}:8-{amd64,arm64} (per-arch)
       ${IMAGE_NAME}:${MANIFEST_TAG} (multi-arch manifest)

Examples:
  $0                          # Auto-detect, build local
  $0 --arch arm64             # Build arm64 locally
  $0 --all                    # Build both archs locally
  $0 --all --push             # Build + push + manifest
  $0 push                     # Push existing local images + manifest
  $0 manifest                 # Create manifest from already-pushed images
  $0 clean                    # Clean cache
EOF
}

find_zip_by_arch() {
    local target="$1"
    for i in "${!ARCHS[@]}"; do
        [ "${ARCHS[$i]}" = "$target" ] && { echo "${ZIPS[$i]}"; return 0; }
    done
    return 1
}

# --- Main ---

ARCH=""
ALL=false
PUSH=false

case "${1:-build}" in
    clean)     clean; exit 0 ;;
    push)
        echo "Pushing existing images..."
        docker push "${IMAGE_NAME}:8-amd64"
        docker push "${IMAGE_NAME}:8-arm64"
        push_manifest amd64 arm64
        echo "All pushed. Pull with: docker pull ${IMAGE_NAME}:${MANIFEST_TAG}"
        exit 0
        ;;
    manifest)
        push_manifest amd64 arm64
        echo "Pull with: docker pull ${IMAGE_NAME}:${MANIFEST_TAG}"
        exit 0
        ;;
    --help|-h) usage; exit 0 ;;
esac

[[ "$1" == "build" || "$1" == "--build" ]] && shift

while [ $# -gt 0 ]; do
    case "$1" in
        --arch) shift; ARCH="$1" ;;
        --all)  ALL=true ;;
        --push) PUSH=true ;;
        *)      usage; exit 1 ;;
    esac
    shift
done

# Discover available zips
ARCHS=()
ZIPS=()
for f in "$SCRIPT_DIR"/dm8_*.zip; do
    [ -f "$f" ] || continue
    a=$(detect_arch "$f")
    [ "$a" = "unknown" ] && { echo "Warning: cannot detect arch from $(basename "$f"), skipping."; continue; }
    ARCHS+=("$a")
    ZIPS+=("$f")
done

[ ${#ARCHS[@]} -eq 0 ] && { echo "Error: no dm8_*.zip found in ${SCRIPT_DIR}"; exit 1; }

# Determine which archs to build
BUILD_ARCHS=()
if [ -n "$ARCH" ]; then
    BUILD_ARCHS=("$ARCH")
elif $ALL || $PUSH; then
    BUILD_ARCHS=("${ARCHS[@]}")
else
    [ ${#ARCHS[@]} -gt 1 ] && {
        echo "Error: multiple zips found. Use --arch or --all to specify:"
        for i in "${!ARCHS[@]}"; do echo "  ${ARCHS[$i]}: $(basename "${ZIPS[$i]}")"; done
        exit 1
    }
    BUILD_ARCHS=("${ARCHS[0]}")
fi

# Extract binaries
for a in "${BUILD_ARCHS[@]}"; do
    zip=$(find_zip_by_arch "$a")
    extract "$zip" "$a"
done

# Build
for a in "${BUILD_ARCHS[@]}"; do
    zip=$(find_zip_by_arch "$a")
    build_arch "$a" "$zip" "$PUSH"
done

# Push manifest
if $PUSH && [ ${#BUILD_ARCHS[@]} -ge 2 ]; then
    push_manifest "${BUILD_ARCHS[@]}"
    echo "All pushed. Pull with: docker pull ${IMAGE_NAME}:${MANIFEST_TAG}"
elif $PUSH; then
    echo "Pushed: ${IMAGE_NAME}:8-${BUILD_ARCHS[0]}"
fi
