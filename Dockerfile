# ============================================================
# Stage 1: Install DM8 (builder)
# ============================================================
FROM debian:12-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i 's|deb.debian.org|mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources && \
    apt update && \
    apt install -y --no-install-recommends libaio1 sudo && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 10001 dinstall && \
    useradd -u 10001 -g dinstall -m -d /home/dmdba -s /bin/bash dmdba && \
    echo "dmdba hard nofile 65536" >> /etc/security/limits.conf && \
    echo "dmdba soft nofile 65536" >> /etc/security/limits.conf && \
    echo "dmdba hard stack 32768" >> /etc/security/limits.conf && \
    echo "dmdba soft stack 16384" >> /etc/security/limits.conf && \
    echo "dmdba hard data 1048576" >> /etc/security/limits.conf && \
    echo "dmdba soft data 1048576" >> /etc/security/limits.conf

COPY ./DMInstall.bin /tmp/DMInstall.bin
COPY ./dm_install.xml /mnt/dm_install.xml

RUN mkdir -p /opt/dmdbms && \
    chown -R dmdba:dinstall /opt/dmdbms /mnt /tmp && \
    chmod 755 /tmp/DMInstall.bin

USER dmdba
RUN /tmp/DMInstall.bin -q /mnt/dm_install.xml
USER root

RUN rm -rf /mnt /tmp/DMInstall.bin

# ============================================================
# Stage 2: Runtime image (minimal)
# ============================================================
FROM debian:12-slim

ENV DM_INSTALL_PATH=/opt/dmdbms \
    LD_LIBRARY_PATH=/opt/dmdbms/bin \
    CASE_SENSITIVE=Y \
    CHARSET=1 \
    DB_NAME=DAMENG \
    INSTANCE_NAME=DMSERVER \
    PORT_NUM=5236 \
    PAGE_SIZE=8 \
    EXTENT_SIZE=16 \
    LOG_SIZE=4096 \
    BUFFER=8000 \
    TIME_ZONE=+08:00 \
    BLANK_PAD_MODE=0 \
    PAGE_CHECK=3 \
    SYSDBA_PWD=DMdba_123 \
    SYSAUDITOR_PWD=DMAuditor_123 \
    DATA_DIR=/opt/dmdbms/data

RUN sed -i 's|deb.debian.org|mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources && \
    apt update && \
    apt install -y --no-install-recommends libaio1 sudo && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 10001 dinstall && \
    useradd -u 10001 -g dinstall -m -d /home/dmdba -s /bin/bash dmdba && \
    echo "dmdba ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

COPY --from=builder /opt/dmdbms /opt/dmdbms

RUN rm -rf /opt/dmdbms/doc /opt/dmdbms/desktop /opt/dmdbms/samples /opt/dmdbms/uninstall && \
    mkdir -p /opt/dmdbms/data /opt/dmdbms/log && \
    chown -R dmdba:dinstall /opt/dmdbms

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER dmdba
WORKDIR /home/dmdba

VOLUME ["/opt/dmdbms/data"]
EXPOSE 5236
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
