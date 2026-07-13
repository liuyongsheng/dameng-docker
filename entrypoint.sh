#!/bin/bash
set -e

DM_INSTALL_PATH=${DM_INSTALL_PATH:-/opt/dmdbms}
DM_HOME=${DM_HOME:-${DM_INSTALL_PATH}}
export DM_HOME DM_INSTALL_PATH
export PATH=${DM_INSTALL_PATH}/bin:${PATH}
export LD_LIBRARY_PATH=${DM_INSTALL_PATH}/bin${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

DB_NAME=${DB_NAME:-DAMENG}
INSTANCE_NAME=${INSTANCE_NAME:-DMSERVER}
PORT_NUM=${PORT_NUM:-5236}
PAGE_SIZE=${PAGE_SIZE:-8}
EXTENT_SIZE=${EXTENT_SIZE:-16}
LOG_SIZE=${LOG_SIZE:-256}
CHARSET=${CHARSET:-1}
CASE_SENSITIVE=${CASE_SENSITIVE:-Y}
BUFFER=${BUFFER:-1024}
TIME_ZONE=${TIME_ZONE:-+08:00}
BLANK_PAD_MODE=${BLANK_PAD_MODE:-0}
PAGE_CHECK=${PAGE_CHECK:-3}
SYSDBA_PWD=${SYSDBA_PWD:-DMdba_123}
SYSAUDITOR_PWD=${SYSAUDITOR_PWD:-DMAuditor_123}
AUTO_OVERWRITE=${AUTO_OVERWRITE:-0}
USE_DB_NAME=${USE_DB_NAME:-1}
VARCHAR_TYPE=${VARCHAR_TYPE:-}
ENABLE_FLASHBACK=${ENABLE_FLASHBACK:-1}
DATA_DIR=${DATA_DIR:-${DM_INSTALL_PATH}/data}
INIT_SCRIPTS_DIR=${INIT_SCRIPTS_DIR:-/init-scripts}

if [ ! -f "${DATA_DIR}/${DB_NAME}/dm.ini" ]; then
    echo "Initializing database..."

    DMINIT_ARGS=(
        "PATH=${DATA_DIR}"
        "DB_NAME=${DB_NAME}"
        "INSTANCE_NAME=${INSTANCE_NAME}"
        "PORT_NUM=${PORT_NUM}"
        "PAGE_SIZE=${PAGE_SIZE}"
        "EXTENT_SIZE=${EXTENT_SIZE}"
        "LOG_SIZE=${LOG_SIZE}"
        "CHARSET=${CHARSET}"
        "CASE_SENSITIVE=${CASE_SENSITIVE}"
        "BUFFER=${BUFFER}"
        "TIME_ZONE=${TIME_ZONE}"
        "BLANK_PAD_MODE=${BLANK_PAD_MODE}"
        "PAGE_CHECK=${PAGE_CHECK}"
        "SYSDBA_PWD=${SYSDBA_PWD}"
        "SYSAUDITOR_PWD=${SYSAUDITOR_PWD}"
        "AUTO_OVERWRITE=${AUTO_OVERWRITE}"
        "USE_DB_NAME=${USE_DB_NAME}"
    )

    ${DM_INSTALL_PATH}/bin/dminit "${DMINIT_ARGS[@]}"

    if [ -n "${VARCHAR_TYPE}" ]; then
        echo "VARCHAR_TYPE = ${VARCHAR_TYPE}" >> "${DATA_DIR}/${DB_NAME}/dm.ini"
        echo "VARCHAR_TYPE set to ${VARCHAR_TYPE} in dm.ini"
    fi

    if [ "${ENABLE_FLASHBACK}" = "1" ]; then
        echo "ENABLE_FLASH = 1" >> "${DATA_DIR}/${DB_NAME}/dm.ini"
        echo "Flashback enabled in dm.ini"
    fi

    echo "Database initialized successfully."
fi

# ---------------------------------------------------------------------------
# Init scripts: execute .sql files in order after database is ready
# ---------------------------------------------------------------------------
if [ -d "${INIT_SCRIPTS_DIR}" ]; then
    scripts=()
    while IFS= read -r -d '' f; do
        scripts+=("$f")
    done < <(find "${INIT_SCRIPTS_DIR}" -maxdepth 1 -type f -name '*.sql' -print0 | sort -z)

    if [ ${#scripts[@]} -gt 0 ]; then
        echo "Starting DMServer temporarily for init scripts..."

        ${DM_INSTALL_PATH}/bin/dmserver "${DATA_DIR}/${DB_NAME}/dm.ini" -noconsole &
        DMSERVER_PID=$!

        DM_READY=0
        for i in $(seq 1 30); do
            if ${DM_INSTALL_PATH}/bin/disql -S "SYSDBA/${SYSDBA_PWD}@localhost:${PORT_NUM}" \
                -e "SELECT 1;" 2>/dev/null | grep -q "1"; then
                DM_READY=1
                break
            fi
            sleep 2
        done

        if [ "${DM_READY}" -eq 0 ]; then
            echo "ERROR: database did not become ready"
            kill "${DMSERVER_PID}" 2>/dev/null || true
            exit 1
        fi

        echo "Executing init scripts..."
        for f in "${scripts[@]}"; do
            echo "  ${f##*/}"
            ${DM_INSTALL_PATH}/bin/disql "SYSDBA/${SYSDBA_PWD}@localhost:${PORT_NUM}" '`'"${f}" 2>&1 | grep -v "^$" || {
                echo "ERROR: init script failed: ${f}"
                kill "${DMSERVER_PID}" 2>/dev/null || true
                exit 1
            }
        done

        echo "Shutting down temporary DMServer..."
        ${DM_INSTALL_PATH}/bin/disql -S "SYSDBA/${SYSDBA_PWD}@localhost:${PORT_NUM}" \
            -e "SHUTDOWN IMMEDIATE;" 2>/dev/null || true
        wait "${DMSERVER_PID}" 2>/dev/null || true
        echo "Init scripts completed."
    fi
fi

echo "Starting DmAPService..."
${DM_INSTALL_PATH}/bin/dmap "dmap_ini=${DM_INSTALL_PATH}/bin/dmap.ini" &
DMPID=$!
sleep 1
kill -0 "${DMPID}" 2>/dev/null || echo "Warning: DmAPService may not have started"

echo "Starting DMServer..."
exec ${DM_INSTALL_PATH}/bin/dmserver "${DATA_DIR}/${DB_NAME}/dm.ini" -noconsole
