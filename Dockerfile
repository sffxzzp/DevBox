# =============================================================================
# devbox: HAPI + Tailscale 一体化镜像（agent 按需安装）
#
#   - Tailscale : 官方 apt 源安装（Debian trixie），userspace 模式（无需 NET_ADMIN/privileged）
#   - HAPI      : npm 全局安装（@twsxtd/hapi），手机/浏览器远程控制
#   - 各 agent CLI（claude / codex / opencode / grok / cursor / kimi / copilot / agy / pi）:
#     不在镜像里，由 entrypoint 按 AGENT 环境变量按需安装
#     （用户级 npm prefix + NPM_REGISTRY 可配），从而显著缩小镜像体积。
#   - 运行时目录与权限由 entrypoint.sh 统一管理：默认以 root 引导，自动 mkdir + chown
#     三个 bind mount（./data、./tailscale、./workspace）后降权到 devbox (uid 1000) 运行，
#     首次启动开箱即用，无需宿主侧手动 chown（镜像层不做 mkdir/chown —— 无意义且会与
#     --user 1000 冲突）。
# =============================================================================
FROM node:lts-trixie-slim

# ---- 系统依赖 ----------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        git \
        openssh-client \
        tini \
        procps \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# ---- Tailscale（官方 apt 仓库，Debian trixie）---------------------------------
# 注意：keyring 文件名必须是 <codename>.tailscale-keyring.list
#       （写成 <codename>.tailscale-list 会 404）
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
        | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
        | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends tailscale \
    && rm -rf /var/lib/apt/lists/*

# ---- 非 root 用户 -------------------------------------------------------------
# 基础镜像（node:lts-trixie-slim）已自带 uid/gid 1000 的用户 `node`（home=/home/node），
# 直接改名为 devbox 并迁移家目录，避免 useradd --uid 1000 因冲突报错（--user 1000 仍可用）。
# 只建用户，不创建/授权任何数据目录（运行时目录由 entrypoint.sh 统一创建）。
# 基础镜像的 node 用户本就是 /bin/bash 且 uid/gid 1000，usermod 不改 shell，无需再 chsh。
RUN groupmod -n devbox node \
    && usermod --login devbox --home /home/devbox --move-home node

# devbox 免密 sudo：让 Claude Code 等 agent 能在会话里自行安装系统依赖
# （devcontainer 标准做法；等同 root 权限，若不需要可删除此文件）
RUN echo 'devbox ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/devbox \
    && chmod 440 /etc/sudoers.d/devbox

# ---- HAPI（全局 npm 安装，root 安装到 /usr/local/bin）--------------------------
# registry 可用构建参数覆盖，国内用户：
#   docker build --build-arg NPM_REGISTRY=https://registry.npmmirror.com .
ARG NPM_REGISTRY=https://registry.npmjs.org
USER root
RUN npm install -g @twsxtd/hapi --registry=${NPM_REGISTRY}

# ---- 运行时配置 ----------------------------------------------------------------
# ~/.local/bin 是 entrypoint 里按需安装各 agent 的用户级位置
ENV PATH="/home/devbox/.local/bin:${PATH}" \
    CLAUDE_CONFIG_DIR=/home/devbox/.claude \
    HAPI_HOME=/home/devbox/.hapi \
    DISABLE_AUTOUPDATER=1

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 默认以 root 启动（供 entrypoint 引导授权），随后自动降权到 devbox (uid 1000) 运行；
# docker exec 进入 devbox 用户需加 -u devbox。
USER root
WORKDIR /workspace

# HAPI hub 端口（走 relay / Tailscale 访问时通常不需要映射出去）
EXPOSE 3006

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
