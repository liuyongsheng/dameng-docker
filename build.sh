#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="${SCRIPT_DIR}/DMInstall.bin"
IMAGE_NAME="liuys36/dm8"
CONTAINER_NAME="dm8"
ZIP_FILE=""
ISO_FILE=""
IMAGE_TAG=""

detect_version() {
    local zips
    zips=$(ls "${SCRIPT_DIR}"/dm8_*.zip 2>/dev/null)
    [ -z "$zips" ] && { echo "Error: no dm8_*.zip found in ${SCRIPT_DIR}"; exit 1; }

    local count
    count=$(echo "$zips" | wc -l)
    [ "$count" -gt 1 ] && {
        echo "Warning: multiple dm8_*.zip found, using the first one:"
        echo "$zips" | head -1
    }

    local zip
    zip=$(echo "$zips" | head -1)
    ZIP_FILE="$zip"
    local basename
    basename=$(basename "$zip" .zip)
    ISO_FILE="${SCRIPT_DIR}/${basename}.iso"
    IMAGE_TAG="${basename}"
}

extract() {
    detect_version

    if [ -f "${INSTALLER}" ]; then
        echo "DMInstall.bin already exists, skip extraction."
        return
    fi

    echo "Extracting DMInstall.bin from ${ZIP_FILE}..."
    echo "-> Extracting ISO from zip..."
    unzip -o "${ZIP_FILE}" -d "${SCRIPT_DIR}" 2>/dev/null
    [ ! -f "${ISO_FILE}" ] && { echo "Error: ISO extraction failed."; exit 1; }

    echo "-> Extracting DMInstall.bin from ISO..."
    if command -v 7z &>/dev/null; then
        7z e "${ISO_FILE}" -o"${SCRIPT_DIR}" DMInstall.bin -y
    elif command -v xorriso &>/dev/null; then
        xorriso -osirrox on -indev "${ISO_FILE}" -extract /DMInstall.bin "${INSTALLER}"
    elif command -v isoinfo &>/dev/null; then
        isoinfo -R -x /DMINSTALL.BIN -i "${ISO_FILE}" > "${INSTALLER}"
    else
        echo "Error: Need 7z, xorriso, or isoinfo to extract ISO."
        echo "Install: brew install p7zip"
        exit 1
    fi
    chmod +x "${INSTALLER}"
    rm -f "${ISO_FILE}"
    echo "Extraction done."
}

build() {
    rm -f "${INSTALLER}"
    extract
    echo "Building ${IMAGE_NAME}:${IMAGE_TAG} ..."
    docker buildx build \
        --platform linux/amd64 \
        --load \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        -f "${SCRIPT_DIR}/Dockerfile" \
        "${SCRIPT_DIR}"
    echo ""
    echo "Build complete: ${IMAGE_NAME}:${IMAGE_TAG}"
}

run() {
    detect_version
    local pwd="${SYSDBA_PWD:-DMdba_123}"
    docker run -d --name "${CONTAINER_NAME}" \
        -p 5236:5236 \
        -e SYSDBA_PWD="${pwd}" \
        "${IMAGE_NAME}:${IMAGE_TAG}"
    echo "Container '${CONTAINER_NAME}' started, port 5236."
    echo "Connect: docker exec ${CONTAINER_NAME} /opt/dmdbms/bin/disql SYSDBA/${pwd}@localhost:5236"
}

stop() {
    docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
    echo "Container '${CONTAINER_NAME}' stopped and removed."
}

clean() {
    rm -f "${INSTALLER}"
    echo "Cleaned: DMInstall.bin."
}

case "${1:-build}" in
    build)  build ;;
    run)    run ;;
    stop)   stop ;;
    clean)  clean ;;
    *)
        echo "Usage: $0 {build|run|stop|clean}"
        echo ""
        echo "  build  Extract installer and build Docker image (default)"
        echo "  run    Start DM8 container"
        echo "  stop   Stop and remove DM8 container"
        echo "  clean  Remove DMInstall.bin"
        exit 1
        ;;
esac
