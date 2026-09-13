# =============================================================================
# devbox: one image bundling AI coding agents + a selectable control layer +
#         Tailscale (agents installed on demand)
# devbox: AI 编程助手 + 可选控制层 + Tailscale 一体化镜像（agent 按需安装）
#
#   - Tailscale : installed from the official apt repo (Debian trixie), userspace
#                 mode (no NET_ADMIN / privileged required)
#                 Tailscale：官方 apt 源安装（Debian trixie），userspace 模式（无需 NET_ADMIN/privileged）
#   - Control   : HAPI (npm @twsxtd/hapi) or MindFS (single static binary); mutually
#                 exclusive, chosen at runtime by the CONTROL env var (default hapi);
#                 provides phone/browser remote control
#                 控制层：HAPI（npm @twsxtd/hapi）或 MindFS（单静态二进制），二者互斥，
#                 由运行时 CONTROL 环境变量选择（默认 hapi），负责手机/浏览器远程控制
#   - Agent CLIs (claude / codex / opencode / grok / cursor / kimi / copilot / agy / pi):
#                 NOT baked in; installed on demand by entrypoint.sh from the AGENT env
#                 var (user-level npm prefix + configurable NPM_REGISTRY), keeping the
#                 image small
#                 各 agent CLI（claude / codex / opencode / grok / cursor / kimi / copilot / agy / pi）：
#                 不在镜像里，由 entrypoint 按 AGENT 环境变量按需安装
#                 （用户级 npm prefix + NPM_REGISTRY 可配），从而显著缩小镜像体积
#   - Runtime dirs and permissions are managed by entrypoint.sh: it starts as root,
#                 auto mkdir + chowns the three bind mounts (./data, ./tailscale,
#                 ./workspace), then drops to devbox (uid 1000), so no manual chown is
#                 needed on the host. (The image layer does no mkdir/chown — it is
#                 pointless and conflicts with --user 1000.)
#                 运行时目录与权限由 entrypoint.sh 统一管理：默认以 root 引导，自动 mkdir + chown
#                 三个 bind mount（./data、./tailscale、./workspace）后降权到 devbox (uid 1000) 运行，
#                 首次启动开箱即用，无需宿主侧手动 chown（镜像层不做 mkdir/chown —— 无意义且会与
#                 --user 1000 冲突）
# =============================================================================
FROM node:lts-trixie-slim

# ---- System dependencies / 系统依赖 ------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        git \
        openssh-client \
        tini \
        procps \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# ---- Tailscale (official apt repo, Debian trixie) / Tailscale（官方 apt 仓库）---
# NOTE: the keyring filename must be <codename>.tailscale-keyring.list
#       (using <codename>.tailscale-list returns 404)
# 注意：keyring 文件名必须是 <codename>.tailscale-keyring.list
#       （写成 <codename>.tailscale-list 会 404）
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
        | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
        | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends tailscale \
    && rm -rf /var/lib/apt/lists/*

# ---- Non-root user / 非 root 用户 --------------------------------------------
# The base image (node:lts-trixie-slim) already ships a uid/gid 1000 user `node`
# (home=/home/node); rename it to devbox and move its home, so we avoid useradd
# --uid 1000 failing on the conflict (--user 1000 still works).
# Only the user is created here; no data dirs are created/chowned (entrypoint.sh
# manages runtime dirs).
# The base image's `node` user already uses /bin/bash with uid/gid 1000, so usermod
# does not change the shell and no chsh is needed.
# 基础镜像（node:lts-trixie-slim）已自带 uid/gid 1000 的用户 `node`（home=/home/node），
# 直接改名为 devbox 并迁移家目录，避免 useradd --uid 1000 因冲突报错（--user 1000 仍可用）。
# 只建用户，不创建/授权任何数据目录（运行时目录由 entrypoint.sh 统一创建）。
# 基础镜像的 node 用户本就是 /bin/bash 且 uid/gid 1000，usermod 不改 shell，无需再 chsh。
RUN groupmod -n devbox node \
    && usermod --login devbox --home /home/devbox --move-home node

# Passwordless sudo for devbox so agents like Claude Code can install OS packages
# during a session (standard devcontainer practice; equivalent to root — delete this
# file if you do not need it).
# devbox 免密 sudo：让 Claude Code 等 agent 能在会话里自行安装系统依赖
# （devcontainer 标准做法；等同 root 权限，若不需要可删除此文件）
RUN echo 'devbox ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/devbox \
    && chmod 440 /etc/sudoers.d/devbox

# ---- HAPI (global npm install to /usr/local/bin) -----------------------------
#           HAPI（全局 npm 安装到 /usr/local/bin）--------------------------------
# The registry can be overridden at build time; for mainland China:
#   docker build --build-arg NPM_REGISTRY=https://registry.npmmirror.com .
# registry 可用构建参数覆盖，国内用户：
#   docker build --build-arg NPM_REGISTRY=https://registry.npmmirror.com .
ARG NPM_REGISTRY=https://registry.npmjs.org
USER root
RUN npm install -g @twsxtd/hapi --registry=${NPM_REGISTRY}

# ---- MindFS (optional control layer: single static binary, zero deps) --------
#           MindFS（可选控制层：单静态二进制，零依赖）------------------------------
# Mutually exclusive with HAPI; selected by entrypoint's CONTROL var
# (CONTROL=hapi|mindfs). Only the binary and its bundled agents.json are installed
# (MindFS uses it to auto-detect installed agent CLIs).
#   pin version:    --build-arg MINDFS_VERSION=v0.5.1
#   download base:  --build-arg MINDFS_BASE_URL=https://github.com (use a mirror in China)
# 与 HAPI 互斥，由 entrypoint 的 CONTROL 变量选择（CONTROL=hapi|mindfs）。
# 只装二进制和它自带的 agents.json（MindFS 靠此自动检测已安装的 agent CLI）。
#   版本锁定： --build-arg MINDFS_VERSION=v0.5.1
#   下载源前缀：--build-arg MINDFS_BASE_URL=https://github.com（国内可换镜像站点）
ARG MINDFS_VERSION=v0.5.1
ARG MINDFS_BASE_URL=https://github.com
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) m=amd64 ;; \
        arm64) m=arm64 ;; \
        armhf|armv7) m=arm ;; \
        *) echo "unsupported build arch: $arch" >&2; exit 1 ;; \
    esac; \
    name="mindfs_${MINDFS_VERSION}_linux_${m}"; \
    curl -fsSL "${MINDFS_BASE_URL}/a9gent/mindfs/releases/download/${MINDFS_VERSION}/${name}.tar.gz" -o /tmp/mindfs.tgz; \
    tar -xzf /tmp/mindfs.tgz -C /tmp; \
    install -m0755 "/tmp/${name}/mindfs" /usr/local/bin/mindfs; \
    mkdir -p /usr/local/share/mindfs; \
    install -m0644 "/tmp/${name}/agents.json" /usr/local/share/mindfs/agents.json; \
    rm -rf /tmp/mindfs.tgz "/tmp/${name}"

# ---- Runtime config / 运行时配置 ---------------------------------------------
# ~/.local/bin is where entrypoint installs agents on demand (user-level).
# ~/.local/bin 是 entrypoint 里按需安装各 agent 的用户级位置
ENV PATH="/home/devbox/.local/bin:${PATH}" \
    CLAUDE_CONFIG_DIR=/home/devbox/.claude \
    HAPI_HOME=/home/devbox/.hapi \
    DISABLE_AUTOUPDATER=1

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# Starts as root (so entrypoint can bootstrap ownership), then drops to devbox
# (uid 1000); `docker exec` into devbox needs -u devbox.
# 默认以 root 启动（供 entrypoint 引导授权），随后自动降权到 devbox (uid 1000) 运行；
# docker exec 进入 devbox 用户需加 -u devbox。
USER root
WORKDIR /workspace

# Control-layer ports: HAPI hub 3006 / MindFS 7331 (usually no need to publish them
# when accessing via relay / Tailscale).
# 控制层端口：HAPI hub 3006 / MindFS 7331（走 relay / Tailscale 时通常不需要映射出去）
EXPOSE 3006 7331

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
