#!/usr/bin/env bash
# =============================================================================
# devbox 容器入口脚本
#
#  0. 运行时目录与权限（root 引导：mkdir+chown bind mount 后降权到 devbox/uid 1000 运行）
#  0.5 按需安装 agent（AGENT 变量控制：claude/codex/opencode/grok/cursor/kimi/copilot/agy/pi，
#     NPM_REGISTRY 可配镜像）
#  1. （可选）TS_AUTHKEY 存在时启动 Tailscale（userspace 模式，无需特权）
#  1.5-1.8 按 CODEX_* / GROK_* / PI_* / OPENCODE_* 环境变量生成各 agent 的自定义端点配置
#  2. 启动 HAPI hub —— 智能通道：Tailscale 连接成功时默认 --no-relay（走 Tailscale），
#     否则默认 --relay（官方公共中继）。HAPI_NO_RELAY 可显式覆盖。
#  3. 启动 HAPI runner（支持从手机/浏览器远程新建会话）
#  4. 将 hub 日志转发到 stdout（docker logs 可看到访问入口 / token）
# =============================================================================
set -euo pipefail

HAPI_PORT="${HAPI_LISTEN_PORT:-3006}"

log() { echo "[entrypoint] $*"; }

# ---------------------------------------------------------------------------
# 0) 运行时目录与权限 —— root 引导：自动授权 bind mount 后降权到 devbox (uid 1000)
#    bind mount（./data → /home/devbox、./tailscale → /var/lib/tailscale、./workspace）
#    由 Docker 首次自动创建时属主是 root，容器内 uid 1000 无法写入也无法 chown。
#    因此默认以 root 启动本脚本：统一 mkdir + chown 这三个目录归 devbox，再用 setpriv
#    降权为 devbox 重新执行脚本，此后所有进程都以 uid 1000 运行（等效 --user 1000）。
#    宿主侧无需任何手动 chown。若被强制以非 root 启动（docker run --user 1000 /
#    compose user:），则跳过授权，由下面的 FATAL 给出提示。
# ---------------------------------------------------------------------------
if [ "$(id -u)" = "0" ]; then
  log "以 root 引导：自动授权 /home/devbox、/var/lib/tailscale、/workspace、/var/run/tailscale，然后降权到 devbox (uid 1000)..."
  mkdir -p /home/devbox /var/lib/tailscale /workspace
  # 仅当目录属主不是 devbox(uid 1000) 时才 chown（首次创建或宿主预置了 root 内容时触发一次；
  # 之后每次重启跳过，避免反复改写宿主目录内文件的属主）
  if [ "$(stat -c %u /home/devbox)" != "1000" ] \
     || [ "$(stat -c %u /var/lib/tailscale)" != "1000" ] \
     || [ "$(stat -c %u /workspace)" != "1000" ]; then
    chown -R devbox:devbox /home/devbox /var/lib/tailscale /workspace 2>/dev/null || true
  fi
  # tailscale CLI 默认连接 /var/run/tailscale/tailscaled.sock：引导时创建并授权给 devbox
  mkdir -p /var/run/tailscale
  chown devbox:devbox /var/run/tailscale 2>/dev/null || true
  export HOME=/home/devbox
  exec setpriv --reuid=1000 --regid=1000 --init-groups /usr/local/bin/entrypoint.sh "$@"
fi
LOG_DIR="${HAPI_HOME:-$HOME/.hapi}/logs"
if ! mkdir -p "$HOME/.claude" "$HOME/.hapi/logs" "$HOME/.codex" "$HOME/.grok" \
         "$HOME/.pi/agent" "$HOME/.config/opencode" "$LOG_DIR"; then
  log "FATAL: 无法创建 $HOME 下的配置目录 —— ./data 不可写。"
  log "       容器以非 root 启动时无法自动授权；请用默认用户启动（去掉 --user / user: 配置），"
  log "       或在宿主机执行：sudo chown -R 1000:1000 data tailscale"
  exit 1
fi

HUB_PID=""
TAIL_PID=""
TS_CONNECTED=0        # tailscale up 是否真的成功

# ---------------------------------------------------------------------------
# 0.5) 按需安装 agent —— 镜像里不预装，启动时按需安装以缩小体积
#    AGENT          : 逗号分隔，如 claude / codex / opencode / grok / cursor / kimi / copilot / agy / pi / none
#    NPM_REGISTRY   : npm 镜像地址，国内用户可设 https://registry.npmmirror.com
#    CLAUDE_VERSION / CODEX_VERSION / OPENCODE_VERSION / COPILOT_VERSION / PI_VERSION : 版本锁定（默认 latest）
#    以非 root 运行：npm 装的用用户级 prefix 装到 ~/.local/bin；curl 安装脚本同理
# ---------------------------------------------------------------------------
export PATH="$HOME/.local/bin:${PATH}"
NPM_PREFIX="$HOME/.local"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org}"

install_agent() {
  local pkg="$1" version="$2" bin="$3"
  if command -v "$bin" >/dev/null 2>&1; then
    log "Agent '$bin' already available: $(command -v "$bin") (设了 ${bin^^}_VERSION 锁版本需先手动删除旧安装)"
    return 0
  fi
  log "Installing $bin ($pkg@$version) from $NPM_REGISTRY ..."
  if npm install -g --prefix "$NPM_PREFIX" "$pkg@$version" --registry="$NPM_REGISTRY" \
      >"/tmp/install-${bin}.log" 2>&1; then
    hash -r
    log "$bin installed: $(command -v "$bin" || echo "$NPM_PREFIX/bin/$bin")"
  else
    log "WARNING: failed to install $bin — see /tmp/install-${bin}.log (check NPM_REGISTRY / network)."
  fi
}

# 通过官方 curl 安装脚本装的 agent（不走 npm registry，国内下载可能较慢）
install_curl() {
  local url="$1" bin="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    log "Agent '$bin' already available: $(command -v "$bin")"
    return 0
  fi
  log "Installing $bin from $url ..."
  if curl -fsSL "$url" | bash >"/tmp/install-${bin}.log" 2>&1; then
    hash -r
    log "$bin installed: $(command -v "$bin" || echo "$NPM_PREFIX/bin/$bin")"
  else
    log "WARNING: failed to install $bin — see /tmp/install-${bin}.log (网络可达性/代理问题，国内可考虑手动安装)."
  fi
}

AGENTS="${AGENT:-claude}"
IFS=',' read -r -a AGENT_LIST <<< "$AGENTS"
for a in "${AGENT_LIST[@]}"; do
  a="$(echo "$a" | xargs)"   # 去空格（.env 里 "claude, codex" 常见）
  case "$a" in
    claude|cc)   install_agent "@anthropic-ai/claude-code"       "${CLAUDE_VERSION:-latest}" claude ;;
    codex)       install_agent "@openai/codex"                   "${CODEX_VERSION:-latest}" codex ;;
    opencode)    install_agent "opencode-ai"                      "${OPENCODE_VERSION:-latest}" opencode ;;
    grok)        install_curl "https://x.ai/cli/install.sh"       grok ;;
    cursor)      install_curl "https://cursor.com/install"        agent ;;
    kimi)        install_curl "https://code.kimi.com/kimi-code/install.sh" kimi ;;
    copilot)     install_agent "@github/copilot"                  "${COPILOT_VERSION:-latest}" copilot ;;
    agy|antigravity) install_curl "https://antigravity.google/cli/install.sh" agy ;;
    pi)          install_agent "@earendil-works/pi-coding-agent"  "${PI_VERSION:-latest}" pi ;;
    none|"")    log "AGENT=none — skipping agent installation." ;;
    *)           log "WARNING: unknown agent '$a' in AGENT (supported: claude, codex, opencode, grok, cursor, kimi, copilot, agy, pi, none)." ;;
  esac
done

# ---------------------------------------------------------------------------
# 1) Tailscale（可选：仅在设置了 TS_AUTHKEY 时启用）
# ---------------------------------------------------------------------------
TS_AUTHKEY="$(echo "${TS_AUTHKEY:-}" | xargs)"   # 去空格，避免 .env 里尾随空格导致失败
if [ -n "$TS_AUTHKEY" ]; then
  log "Starting tailscaled (userspace networking, no privileged caps required)..."
  # 使用默认 socket 路径 /var/run/tailscale/tailscaled.sock（root 引导时已创建并授权给
  # devbox），这样 tailscale CLI 无需 --socket 即可连接；state 存 ./tailscale bind 里持久化
  mkdir -p /var/lib/tailscale 2>/dev/null \
    || log "WARNING: cannot write /var/lib/tailscale — check ./tailscale 挂载权限。"
  rm -f /var/run/tailscale/tailscaled.sock
  tailscaled \
    --tun=userspace-networking \
    --state=/var/lib/tailscale/tailscaled.state \
    >/tmp/tailscaled.log 2>&1 &

  # 等待 unix socket 就绪
  for _ in $(seq 1 30); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
  done

  TS_UP=(up --authkey="$TS_AUTHKEY" --hostname="${TS_HOSTNAME:-devbox-vps}")
  if [ "${TS_SSH:-true}" = "true" ]; then
    TS_UP+=(--ssh)          # 启用 Tailscale SSH，可从任意设备 ssh 进容器
  fi
  if [ -n "${TS_EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    TS_UP+=($TS_EXTRA_ARGS)
  fi

  if tailscale "${TS_UP[@]}" >/tmp/tailscale-up.log 2>&1; then
    TS_CONNECTED=1
    log "Tailscale connected: $(tailscale ip -4 2>/dev/null | tr '\n' ' ')"
    # 有 Tailscale 时默认把 hub 绑定到所有网卡，方便通过 tailnet IP:3006 直连
    export HAPI_LISTEN_HOST="${HAPI_LISTEN_HOST:-0.0.0.0}"
  else
    log "WARNING: 'tailscale up' failed (see /tmp/tailscale-up.log). Falling back to HAPI public relay."
  fi
else
  log "TS_AUTHKEY not set — skipping Tailscale (will use HAPI public relay by default)."
fi

export HAPI_LISTEN_HOST="${HAPI_LISTEN_HOST:-127.0.0.1}"

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 1.5-1.8) 各 agent 自定义端点配置（可选）—— 按环境变量自动生成
#      通用守卫 gen_config：两个必填变量都设置且目标文件不存在 → mkdir + 调用生成函数；
#      只设置其中一个 → 打警告。各生成函数负责写文件（printf 避免特殊字符展开）与详细日志。
#      已存在的配置文件不会被覆盖（优先用挂载的文件方式配置）。
# ---------------------------------------------------------------------------
gen_config() { # 描述 目标路径 值1 值2 生成函数 变量1名 变量2名
  local desc="$1" path="$2" v1="$3" v2="$4" gen="$5" n1="$6" n2="${7:-}"
  if [ -n "$v1" ] && [ -n "$v2" ] && [ ! -f "$path" ]; then
    mkdir -p "$(dirname "$path")"
    "$gen"
  elif [ -n "$v1" ] || [ -n "$v2" ]; then
    log "WARNING: $desc 配置不完整 —— 需要同时设置 $n1 和 $n2 才会生成 $(basename "$path")。"
  fi
}

# 1.5) Codex —— 生成 ~/.codex/config.toml（env_key 方式，无需交互登录）
#      注意：Codex 的 wire_api 目前只支持 "responses"，网关需兼容 OpenAI Responses API。
CODEX_HOME="${HOME}/.codex"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.1}"
gen_codex() {
  # 用 printf 写配置，避免 heredoc 对含 $、反引号等特殊字符的值做 shell 展开
  printf '%s\n' \
    '# 由 devbox entrypoint 根据环境变量自动生成' \
    'model_provider = "custom"' \
    "model = \"$CODEX_MODEL\"" \
    '' \
    '[model_providers.custom]' \
    'name = "custom gateway"' \
    "base_url = \"$CODEX_BASE_URL\"" \
    'env_key = "CODEX_API_KEY"' \
    'wire_api = "responses"' \
    >"$CODEX_HOME/config.toml"
  log "Codex: generated $CODEX_HOME/config.toml (provider base_url=$CODEX_BASE_URL, model=$CODEX_MODEL)"
}
gen_config "Codex" "$CODEX_HOME/config.toml" "${CODEX_BASE_URL:-}" "${CODEX_API_KEY:-}" gen_codex CODEX_BASE_URL CODEX_API_KEY
# 未走网关时，若设置了 OPENAI_API_KEY 则提示一次性登录方式
if [ -z "${CODEX_BASE_URL:-}${CODEX_API_KEY:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
  log "  Codex: OPENAI_API_KEY 已设置。首次使用请执行：docker exec -it -u devbox <container> bash -c 'printenv OPENAI_API_KEY | codex login --with-api-key'"
fi

# 1.6) Grok —— 生成 ~/.grok/config.toml（env_key 方式）
#      官方 xAI 端点只需 XAI_API_KEY（grok 原生读取）。api_backend 默认 chat_completions
#      （中转站最通用），也可设 responses / messages。
GROK_HOME="${HOME}/.grok"
gen_grok() {
  printf '%s\n' \
    '[model.custom]' \
    "model = \"${GROK_MODEL:-grok-4.5}\"" \
    "base_url = \"$GROK_BASE_URL\"" \
    "api_backend = \"${GROK_API_BACKEND:-chat_completions}\"" \
    'env_key = "GROK_API_KEY"' \
    >"$GROK_HOME/config.toml"
  log "Grok: generated $GROK_HOME/config.toml (base_url=$GROK_BASE_URL, model=${GROK_MODEL:-grok-4.5}, api_backend=${GROK_API_BACKEND:-chat_completions})"
}
gen_config "Grok" "$GROK_HOME/config.toml" "${GROK_BASE_URL:-}" "${GROK_API_KEY:-}" gen_grok GROK_BASE_URL GROK_API_KEY

# 1.7) Pi —— 生成 ~/.pi/agent/models.json。Pi 纯第三方、无官方后端，必须配置 provider。
#      apiKey 写 $PI_API_KEY 环境变量插值（密钥不落盘，Pi 运行时从环境读取）。PI_API 默认 openai-completions。
PI_HOME="${HOME}/.pi/agent"
gen_pi() {
  # shellcheck disable=SC2016  # $PI_API_KEY 故意写为字面量（运行时环境变量插值，密钥不落盘）
  printf '%s\n' \
    '{' \
    '  "providers": {' \
    '    "custom": {' \
    '      "baseUrl": "'"$PI_BASE_URL"'",' \
    '      "api": "'"${PI_API:-openai-completions}"'",' \
    '      "apiKey": "$PI_API_KEY",' \
    '      "models": [' \
    '        {' \
    '          "id": "'"${PI_MODEL:-gpt-4o-mini}"'",' \
    '          "name": "'"${PI_MODEL:-gpt-4o-mini}"'",' \
    '          "contextWindow": 128000,' \
    '          "maxTokens": 16384,' \
    '          "reasoning": false' \
    '        }' \
    '      ]' \
    '    }' \
    '  }' \
    '}' \
    >"$PI_HOME/models.json"
  log "Pi: generated $PI_HOME/models.json (base_url=$PI_BASE_URL, model=${PI_MODEL:-gpt-4o-mini}, api=${PI_API:-openai-completions}; apiKey 用环境变量插值，不落盘)"
}
gen_config "Pi" "$PI_HOME/models.json" "${PI_BASE_URL:-}" "${PI_API_KEY:-}" gen_pi PI_BASE_URL PI_API_KEY

# 1.8) OpenCode —— 生成 ~/.config/opencode/opencode.json
#      apiKey 用 {env:OPENCODE_API_KEY} 插值，密钥不落盘。
OPENCODE_HOME="${HOME}/.config/opencode"
gen_opencode() {
  # shellcheck disable=SC2016  # $schema 里的 $ 是 JSON 字段名，故意不展开
  printf '%s\n' \
    '{' \
    '  "$schema": "https://opencode.ai/config.json",' \
    '  "model": "custom/'"${OPENCODE_MODEL:-gpt-4o-mini}"'",' \
    '  "provider": {' \
    '    "custom": {' \
    '      "npm": "@ai-sdk/openai-compatible",' \
    '      "name": "Custom Gateway",' \
    '      "options": {' \
    '        "baseURL": "'"$OPENCODE_BASE_URL"'",' \
    '        "apiKey": "{env:OPENCODE_API_KEY}"' \
    '      },' \
    '      "models": {' \
    '        "'"${OPENCODE_MODEL:-gpt-4o-mini}"'": {' \
    '          "name": "'"${OPENCODE_MODEL:-gpt-4o-mini}"'"' \
    '        }' \
    '      }' \
    '    }' \
    '  }' \
    '}' \
    >"$OPENCODE_HOME/opencode.json"
  log "OpenCode: generated $OPENCODE_HOME/opencode.json (base_url=$OPENCODE_BASE_URL, model=${OPENCODE_MODEL:-gpt-4o-mini}; apiKey 用 {env:OPENCODE_API_KEY} 插值，不落盘)"
}
gen_config "OpenCode" "$OPENCODE_HOME/opencode.json" "${OPENCODE_BASE_URL:-}" "${OPENCODE_API_KEY:-}" gen_opencode OPENCODE_BASE_URL OPENCODE_API_KEY

# ---------------------------------------------------------------------------
# 2) HAPI hub —— 通道选择
#    HAPI_NO_RELAY 显式设置时听用户的；未设置时智能默认（基于 Tailscale 是否真的连上）：
#      连接成功 → 走 Tailscale（关闭官方公共中继，流量只在你的 tailnet 内）
#      连接失败/未配置 → 走官方公共中继 relay.hapi.run（保底可用，端到端加密）
# ---------------------------------------------------------------------------
if [ -z "${HAPI_NO_RELAY:-}" ]; then
  if [ "$TS_CONNECTED" = "1" ]; then
    HAPI_NO_RELAY=true
  else
    HAPI_NO_RELAY=false
  fi
fi

HUB_ARGS=(hub)
if [ "$HAPI_NO_RELAY" = "true" ]; then
  HUB_ARGS+=(--no-relay)
  if [ "$TS_CONNECTED" != "1" ]; then
    log "WARNING: HAPI_NO_RELAY=true 但 Tailscale 未连接 —— hub 将只监听 127.0.0.1，无法从远程访问！"
    log "         请检查 TS_AUTHKEY/网络，或把 HAPI_NO_RELAY 设为 false 使用官方公共中继。"
  else
    log "HAPI 通道：Tailscale（官方公共中继已关闭，流量只在你的 tailnet 内）"
  fi
else
  HUB_ARGS+=(--relay)
  log "HAPI 通道：官方公共中继 relay.hapi.run（WireGuard+TLS 端到端加密）"
fi

log "Starting HAPI hub: hapi ${HUB_ARGS[*]} (listen ${HAPI_LISTEN_HOST}:${HAPI_PORT})"
nohup hapi "${HUB_ARGS[@]}" >"$LOG_DIR/hub.log" 2>&1 &
HUB_PID=$!

# 等待 hub 端口就绪（最长 60s）
for _ in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/127.0.0.1/${HAPI_PORT}") 2>/dev/null; then
    exec 3>&- 2>/dev/null || true
    exec 3<&- 2>/dev/null || true
    break
  fi
  sleep 1
done
log "HAPI hub is up (port ${HAPI_PORT})."

# ---------------------------------------------------------------------------
# 3) HAPI runner —— 支持从手机/浏览器远程新建会话
# ---------------------------------------------------------------------------
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
RUNNER_ARGS=(runner start --workspace-root "$WORKSPACE_ROOT")
if [ -n "${RUNNER_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  RUNNER_ARGS+=($RUNNER_EXTRA_ARGS)
fi

log "Starting HAPI runner: hapi ${RUNNER_ARGS[*]}"
nohup hapi "${RUNNER_ARGS[@]}" >"$LOG_DIR/runner.log" 2>&1 &

# ---------------------------------------------------------------------------
# 4) 保持容器存活，并把 hub 日志流到 stdout
# ---------------------------------------------------------------------------
cleanup() {
  log "Shutting down..."
  kill "$HUB_PID" "$TAIL_PID" 2>/dev/null || true
  hapi runner stop >/dev/null 2>&1 || true
}
trap cleanup TERM INT

log "Container ready."
log "  - agent（AGENT=$AGENTS）：在 hapi Web UI 新建会话时选择用哪个 CLI。"
log "    CLI 方式：docker exec -it -u devbox <container> bash -c 'cd /workspace && hapi'（claude）或 'hapi codex'（codex）"
# hapi 仅在公共中继模式（--relay）打印 token；直连模式（--no-relay）下从这里读取并输出
HAPI_TOKEN="$(sed -n 's/.*"cliApiToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${HAPI_HOME:-$HOME/.hapi}/settings.json" 2>/dev/null | head -1 || true)"
if [ "$HAPI_NO_RELAY" = "true" ] && [ "$TS_CONNECTED" = "1" ]; then
  log "  - 访问入口（Tailscale）：手机装 Tailscale App 登录同一 tailnet，浏览器打开 http://<tailnet-IP>:3006"
  log "    tailnet IP：docker exec -u devbox <container> tailscale ip -4"
  [ -n "$HAPI_TOKEN" ] && log "    token（cliApiToken）：$HAPI_TOKEN"
  log "    （token 也可用：docker exec -u devbox <container> cat /home/devbox/.hapi/settings.json）"
else
  log "  - 访问入口（公共中继）：docker logs -f <container>（首行即 URL + 二维码），或访问 https://app.hapi.run 用 token 登录"
  [ -n "$HAPI_TOKEN" ] && log "    token（cliApiToken）：$HAPI_TOKEN"
fi
log "  - hub 日志：$LOG_DIR/hub.log（已流式输出到 stdout）"
log "  - runner 日志：$LOG_DIR/runner.log"

# 后台 tail 日志流，保持 trap 生效（exec 会替换 shell 导致无法优雅退出）
tail -F "$LOG_DIR/hub.log" &
TAIL_PID=$!
wait "$TAIL_PID" || true
