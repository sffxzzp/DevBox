#!/usr/bin/env bash
# =============================================================================
# Health check: probe the port of the selected control layer.
# 健康检查：按 CONTROL 选择要探测的端口。
#   CONTROL=hapi   -> HAPI_LISTEN_PORT   (default 3006 / 默认 3006)
#   CONTROL=mindfs -> MINDFS_LISTEN_PORT (default 7331 / 默认 7331)
# Run by docker-compose's healthcheck inside the container, so injected env vars
# are readable here.
# 由 docker-compose 的 healthcheck 在容器内调用，可直接读到注入的环境变量。
# =============================================================================
set -euo pipefail

case "${CONTROL:-hapi}" in
  mindfs) port="${MINDFS_LISTEN_PORT:-7331}" ;;
  *)      port="${HAPI_LISTEN_PORT:-3006}" ;;
esac

# A successful TCP connection counts as healthy.
# 能建立 TCP 连接即视为健康。
exec 3<>"/dev/tcp/127.0.0.1/${port}"
