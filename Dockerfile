# =============================================================================
# claude-remote: HAPI + Tailscale 一体化镜像（agent 按需安装）
#
#   - Tailscale : 官方 apt 源安装，userspace 模式（无需 NET_ADMIN/privileged）
#   - HAPI      : npm 全局安装（@twsxtd/hapi），手机/浏览器远程控制
#   - 各 agent CLI（claude / codex / opencode / grok / cursor / kimi / copilot / agy / pi）:
#     不在镜像里，由 entrypoint 按 AGENT 环境变量按需安装
#     （用户级 npm prefix + NPM_REGISTRY 可配），从而显著缩小镜像体积。
#
# 运行时以非 root 用户 `claude` 运行（Claude Code 官方要求非 root 才能使用
# --dangerously-skip-permissions，且更安全）。
# =============================================================================
FROM node:22-bookworm-slim

# ---- 系统依赖 ----------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        git \
        openssh-client \
        tini \
        procps \
    && rm -rf /var/lib/apt/lists/*

# ---- Tailscale（官方 apt 仓库，Debian bookworm）-------------------------------
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
        | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-list \
        | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends tailscale \
    && rm -rf /var/lib/apt/lists/*

# ---- 非 root 用户 -------------------------------------------------------------
RUN useradd --create-home --uid 1000 --shell /bin/bash claude \
    && mkdir -p /workspace /var/lib/tailscale /var/run/tailscale \
    && chown -R claude:claude /workspace /var/lib/tailscale /var/run/tailscale

# ---- HAPI（全局 npm 安装，root 安装到 /usr/local/bin）--------------------------
# registry 可用构建参数覆盖，国内用户：
#   docker build --build-arg NPM_REGISTRY=https://registry.npmmirror.com .
ARG NPM_REGISTRY=https://registry.npmjs.org
USER root
RUN npm install -g @twsxtd/hapi --registry=${NPM_REGISTRY}

# ---- 运行时配置 ----------------------------------------------------------------
# ~/.local/bin 是 entrypoint 里按需安装各 agent 的用户级位置
ENV PATH="/home/claude/.local/bin:${PATH}" \
    CLAUDE_CONFIG_DIR=/home/claude/.claude \
    HAPI_HOME=/home/claude/.hapi \
    DISABLE_AUTOUPDATER=1

RUN mkdir -p /home/claude/.claude /home/claude/.hapi/logs /home/claude/.codex /home/claude/.grok \
             /home/claude/.pi /home/claude/.config/opencode \
    && chown -R claude:claude /home/claude/.claude /home/claude/.hapi /home/claude/.codex /home/claude/.grok /home/claude/.pi /home/claude/.config

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER claude
WORKDIR /workspace

# HAPI hub 端口（走 relay / Tailscale 访问时通常不需要映射出去）
EXPOSE 3006

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
