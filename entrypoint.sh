#!/usr/bin/env bash
# =============================================================================
# devbox container entrypoint
# devbox 容器入口脚本
#
#  0. Runtime dirs & permissions (root bootstrap: mkdir+chown the bind mounts, then
#     drop to devbox/uid 1000)
#     运行时目录与权限（root 引导：mkdir+chown bind mount 后降权到 devbox/uid 1000 运行）
#  0.5 Install agents on demand (controlled by AGENT: claude/codex/opencode/grok/cursor/
#     kimi/copilot/agy/pi; NPM_REGISTRY can point at a mirror)
#     按需安装 agent（AGENT 变量控制：claude/codex/opencode/grok/cursor/kimi/copilot/agy/pi，
#     NPM_REGISTRY 可配镜像）
#  1. (Optional) start Tailscale when TS_AUTHKEY is set (userspace mode, no privileges)
#     （可选）TS_AUTHKEY 存在时启动 Tailscale（userspace 模式，无需特权）
#  1.5-1.8 Generate per-agent custom endpoint configs from CODEX_* / GROK_* / PI_* /
#     OPENCODE_* env vars
#     按 CODEX_* / GROK_* / PI_* / OPENCODE_* 环境变量生成各 agent 的自定义端点配置
#  2. Start the control layer — CONTROL=hapi (default) or mindfs, mutually exclusive:
#     hapi  : HAPI hub — smart channel: --no-relay when Tailscale is up, else --relay.
#     mindfs: MindFS service (single binary) — same smart channel: private tailnet when
#             Tailscale is up, else allow the a9gent relay.
#     启动控制层 —— CONTROL=hapi（默认）或 mindfs，二者互斥，由环境变量选择：
#     hapi  : HAPI hub —— 智能通道：Tailscale 连接成功时默认 --no-relay，否则 --relay。
#     mindfs: MindFS 服务（单二进制）—— 同样智能通道：有 Tailscale 走私网，否则允许 a9gent 中继。
#  3. (HAPI only) start the HAPI runner to create sessions remotely
#     （仅 HAPI）启动 HAPI runner，支持从手机/浏览器远程新建会话
#  4. Forward service logs to stdout (docker logs shows the access entry / token)
#     将服务日志转发到 stdout（docker logs 可看到访问入口 / token）
# =============================================================================
set -euo pipefail

HAPI_PORT="${HAPI_LISTEN_PORT:-3006}"
MINDFS_PORT="${MINDFS_LISTEN_PORT:-7331}"

log() { echo "[entrypoint] $*"; }

# Control-layer selection: hapi (default, HAPI hub + runner) or mindfs (MindFS single
# binary); the two are mutually exclusive
# 控制层选择：hapi（默认，HAPI hub + runner）或 mindfs（MindFS 单二进制服务），二者互斥
CONTROL="$(echo "${CONTROL:-hapi}" | tr '[:upper:]' '[:lower:]')"
case "$CONTROL" in
  hapi|mindfs) ;;
  *) echo "[entrypoint] FATAL: unknown CONTROL='$CONTROL' (supported: hapi, mindfs)"; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# 0) Runtime dirs & permissions — root bootstrap: grant the bind mounts, then drop to
#    devbox (uid 1000).
#    The bind mounts (./data -> /home/devbox, ./tailscale -> /var/lib/tailscale,
#    ./workspace) are auto-created by Docker as root on first run, so uid 1000 inside the
#    container can neither write to nor chown them.
#    So this script starts as root by default: it mkdir + chowns those three dirs to
#    devbox, then re-execs itself as devbox via setpriv; all processes then run as uid
#    1000 (equivalent to --user 1000), with no manual chown on the host.
#    If forced to start as non-root (docker run --user 1000 / compose user:), the grant is
#    skipped and the FATAL below explains what to do.
# 0) 运行时目录与权限 —— root 引导：自动授权 bind mount 后降权到 devbox (uid 1000)
#    bind mount（./data → /home/devbox、./tailscale → /var/lib/tailscale、./workspace）
#    由 Docker 首次自动创建时属主是 root，容器内 uid 1000 无法写入也无法 chown。
#    因此默认以 root 启动本脚本：统一 mkdir + chown 这三个目录归 devbox，再用 setpriv
#    降权为 devbox 重新执行脚本，此后所有进程都以 uid 1000 运行（等效 --user 1000）。
#    宿主侧无需任何手动 chown。若被强制以非 root 启动（docker run --user 1000 /
#    compose user:），则跳过授权，由下面的 FATAL 给出提示。
# ---------------------------------------------------------------------------
if [ "$(id -u)" = "0" ]; then
  log "Root bootstrap: granting /home/devbox, /var/lib/tailscale, /workspace, /var/run/tailscale, then dropping to devbox (uid 1000)... | 以 root 引导：自动授权 /home/devbox、/var/lib/tailscale、/workspace、/var/run/tailscale，然后降权到 devbox (uid 1000)..."
  mkdir -p /home/devbox /var/lib/tailscale /workspace
  # Only chown when the owner is not devbox (uid 1000) — triggers once on first creation
  # or when the host pre-seeded root-owned content; skipped on later restarts to avoid
  # repeatedly rewriting ownership of files in the host dirs.
  # 仅当目录属主不是 devbox(uid 1000) 时才 chown（首次创建或宿主预置了 root 内容时触发一次；
  # 之后每次重启跳过，避免反复改写宿主目录内文件的属主）
  if [ "$(stat -c %u /home/devbox)" != "1000" ] \
     || [ "$(stat -c %u /var/lib/tailscale)" != "1000" ] \
     || [ "$(stat -c %u /workspace)" != "1000" ]; then
    chown -R devbox:devbox /home/devbox /var/lib/tailscale /workspace 2>/dev/null || true
  fi
  # The tailscale CLI connects to /var/run/tailscale/tailscaled.sock by default: create it
  # during bootstrap and grant it to devbox.
  # tailscale CLI 默认连接 /var/run/tailscale/tailscaled.sock：引导时创建并授权给 devbox
  mkdir -p /var/run/tailscale
  chown devbox:devbox /var/run/tailscale 2>/dev/null || true
  export HOME=/home/devbox
  exec setpriv --reuid=1000 --regid=1000 --init-groups /usr/local/bin/entrypoint.sh "$@"
fi
LOG_DIR="${HAPI_HOME:-$HOME/.hapi}/logs"
if ! mkdir -p "$HOME/.claude" "$HOME/.hapi/logs" "$HOME/.codex" "$HOME/.grok" \
         "$HOME/.pi/agent" "$HOME/.config/opencode" "$LOG_DIR"; then
  log "FATAL: cannot create the config dirs under $HOME — ./data is not writable. | FATAL: 无法创建 $HOME 下的配置目录 —— ./data 不可写。"
  log "       Started as non-root the container cannot auto-grant ownership; start with the default user (drop --user / user:) | 容器以非 root 启动时无法自动授权；请用默认用户启动（去掉 --user / user: 配置），"
  log "       or run on the host: sudo chown -R 1000:1000 data tailscale | 或在宿主机执行：sudo chown -R 1000:1000 data tailscale"
  exit 1
fi

HUB_PID=""
TAIL_PID=""
TS_CONNECTED=0        # Whether `tailscale up` actually succeeded / tailscale up 是否真的成功

# ---------------------------------------------------------------------------
# 0.5) Install agents on demand — not baked into the image; installed at startup to keep it small
#    AGENT          : comma-separated, e.g. claude / codex / opencode / grok / cursor / kimi / copilot / agy / pi / none
#    NPM_REGISTRY   : npm registry, use https://registry.npmmirror.com in mainland China
#    CLAUDE_VERSION / CODEX_VERSION / OPENCODE_VERSION / COPILOT_VERSION / PI_VERSION : pin versions (default latest)
#    Runs as non-root: npm installs use a user-level prefix into ~/.local/bin; curl installers likewise
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
    log "Agent '$bin' already available: $(command -v "$bin") (to lock a version with ${bin^^}_VERSION, remove the old install first) | 已就绪（设了 ${bin^^}_VERSION 锁版本需先手动删除旧安装）"
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

# Agents installed via their official curl script (not via npm registry; may be slow in China)
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
    log "WARNING: failed to install $bin — see /tmp/install-${bin}.log (network / proxy issue; consider installing manually in China) | 安装失败 —— 见日志（网络可达性/代理问题，国内可考虑手动安装）"
  fi
}

AGENTS="${AGENT:-claude}"
IFS=',' read -r -a AGENT_LIST <<< "$AGENTS"
for a in "${AGENT_LIST[@]}"; do
  a="$(echo "$a" | xargs)"   # Trim spaces (common in .env: "claude, codex") / 去空格（.env 里 "claude, codex" 常见）
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
# 1) Tailscale (optional: enabled only when TS_AUTHKEY is set)
# 1) Tailscale（可选：仅在设置了 TS_AUTHKEY 时启用）
# ---------------------------------------------------------------------------
TS_AUTHKEY="$(echo "${TS_AUTHKEY:-}" | xargs)"   # Trim spaces to avoid trailing-space failures from .env / 去空格，避免 .env 里尾随空格导致失败
if [ -n "$TS_AUTHKEY" ]; then
  log "Starting tailscaled (userspace networking, no privileged caps required)..."
  # Use the default socket path /var/run/tailscale/tailscaled.sock (created and granted to
  # devbox during root bootstrap) so the tailscale CLI connects without --socket; state is
  # persisted in the ./tailscale bind mount.
  # 使用默认 socket 路径 /var/run/tailscale/tailscaled.sock（root 引导时已创建并授权给
  # devbox），这样 tailscale CLI 无需 --socket 即可连接；state 存 ./tailscale bind 里持久化
  mkdir -p /var/lib/tailscale 2>/dev/null \
    || log "WARNING: cannot write /var/lib/tailscale — check ./tailscale mount permissions | 无法写入 /var/lib/tailscale —— 检查 ./tailscale 挂载权限"
  rm -f /var/run/tailscale/tailscaled.sock
  tailscaled \
    --tun=userspace-networking \
    --state=/var/lib/tailscale/tailscaled.state \
    >/tmp/tailscaled.log 2>&1 &

  # Wait for the unix socket to be ready / 等待 unix socket 就绪
  for _ in $(seq 1 30); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
  done

  TS_UP=(up --authkey="$TS_AUTHKEY" --hostname="${TS_HOSTNAME:-devbox-vps}")
  if [ "${TS_SSH:-true}" = "true" ]; then
    TS_UP+=(--ssh)          # Enable Tailscale SSH so any device can ssh in / 启用 Tailscale SSH，可从任意设备 ssh 进容器
  fi
  if [ -n "${TS_EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    TS_UP+=($TS_EXTRA_ARGS)
  fi

  if tailscale "${TS_UP[@]}" >/tmp/tailscale-up.log 2>&1; then
    TS_CONNECTED=1
    log "Tailscale connected: $(tailscale ip -4 2>/dev/null | tr '\n' ' ')"
    # With Tailscale up, bind the hub to all interfaces by default for direct tailnet IP:3006 access
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
# 1.5-1.8) Per-agent custom endpoint configs (optional) — generated from env vars
#      Shared guard gen_config: when both required vars are set and the target file does not
#      exist -> mkdir + call the generator; when only one is set -> warn. Each generator
#      writes the file (printf avoids expanding special chars) and logs details.
#      Existing config files are never overwritten (a mounted file takes precedence).
# 1.5-1.8) 各 agent 自定义端点配置（可选）—— 按环境变量自动生成
#      通用守卫 gen_config：两个必填变量都设置且目标文件不存在 → mkdir + 调用生成函数；
#      只设置其中一个 → 打警告。各生成函数负责写文件（printf 避免特殊字符展开）与详细日志。
#      已存在的配置文件不会被覆盖（优先用挂载的文件方式配置）。
# ---------------------------------------------------------------------------
gen_config() { # desc path v1 v2 gen n1 n2 / 描述 目标路径 值1 值2 生成函数 变量1名 变量2名
  local desc="$1" path="$2" v1="$3" v2="$4" gen="$5" n1="$6" n2="${7:-}"
  if [ -n "$v1" ] && [ -n "$v2" ] && [ ! -f "$path" ]; then
    mkdir -p "$(dirname "$path")"
    "$gen"
  elif [ -n "$v1" ] || [ -n "$v2" ]; then
    log "WARNING: incomplete $desc config — set both $n1 and $n2 to generate $(basename "$path") | $desc 配置不完整 —— 需要同时设置 $n1 和 $n2 才会生成 $(basename "$path")"
  fi
}

# 1.5) Codex — generate ~/.codex/config.toml (env_key style, no interactive login)
#      NOTE: Codex's wire_api currently only supports "responses", so the gateway must be
#      compatible with the OpenAI Responses API.
# 1.5) Codex —— 生成 ~/.codex/config.toml（env_key 方式，无需交互登录）
#      注意：Codex 的 wire_api 目前只支持 "responses"，网关需兼容 OpenAI Responses API。
CODEX_HOME="${HOME}/.codex"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.1}"
gen_codex() {
  # Write config with printf to avoid heredoc shell-expanding values containing $, backticks, etc.
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
# When not using a gateway, hint at the one-time login if OPENAI_API_KEY is set
# 未走网关时，若设置了 OPENAI_API_KEY 则提示一次性登录方式
if [ -z "${CODEX_BASE_URL:-}${CODEX_API_KEY:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
  log "  Codex: OPENAI_API_KEY is set. On first use, run: docker exec -it -u devbox <container> bash -c 'printenv OPENAI_API_KEY | codex login --with-api-key' | Codex：OPENAI_API_KEY 已设置，首次使用请执行上面这条命令"
fi

# 1.6) Grok — generate ~/.grok/config.toml (env_key style)
#      The official xAI endpoint only needs XAI_API_KEY (read natively by grok). api_backend
#      defaults to chat_completions (most compatible with relays); can also be responses / messages.
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

# 1.7) Pi — generate ~/.pi/agent/models.json. Pi is third-party only with no official
#      backend, so a provider must be configured.
#      apiKey uses $PI_API_KEY env interpolation (no secret on disk; Pi reads it at runtime).
#      PI_API defaults to openai-completions.
# 1.7) Pi —— 生成 ~/.pi/agent/models.json。Pi 纯第三方、无官方后端，必须配置 provider。
#      apiKey 写 $PI_API_KEY 环境变量插值（密钥不落盘，Pi 运行时从环境读取）。PI_API 默认 openai-completions。
PI_HOME="${HOME}/.pi/agent"
gen_pi() {
  # shellcheck disable=SC2016  # $PI_API_KEY 故意写为字面量（密钥不落盘）/ intentionally literal (runtime env interpolation; no secret on disk)
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
  log "Pi: generated $PI_HOME/models.json (base_url=$PI_BASE_URL, model=${PI_MODEL:-gpt-4o-mini}, api=${PI_API:-openai-completions}; apiKey from env interpolation, not stored on disk) | Pi：已生成（apiKey 用环境变量插值，不落盘）"
}
gen_config "Pi" "$PI_HOME/models.json" "${PI_BASE_URL:-}" "${PI_API_KEY:-}" gen_pi PI_BASE_URL PI_API_KEY

# 1.8) OpenCode — generate ~/.config/opencode/opencode.json
#      apiKey uses {env:OPENCODE_API_KEY} interpolation, so no secret is stored on disk.
# 1.8) OpenCode —— 生成 ~/.config/opencode/opencode.json
#      apiKey 用 {env:OPENCODE_API_KEY} 插值，密钥不落盘。
OPENCODE_HOME="${HOME}/.config/opencode"
gen_opencode() {
  # shellcheck disable=SC2016  # $schema 里的 $ 是 JSON 字段名，故意不展开 / the $ in $schema is a JSON key name, not expanded
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
  log "OpenCode: generated $OPENCODE_HOME/opencode.json (base_url=$OPENCODE_BASE_URL, model=${OPENCODE_MODEL:-gpt-4o-mini}; apiKey via {env:OPENCODE_API_KEY}, not stored on disk) | OpenCode：已生成（apiKey 用 {env:OPENCODE_API_KEY} 插值，不落盘）"
}
gen_config "OpenCode" "$OPENCODE_HOME/opencode.json" "${OPENCODE_BASE_URL:-}" "${OPENCODE_API_KEY:-}" gen_opencode OPENCODE_BASE_URL OPENCODE_API_KEY

# ---------------------------------------------------------------------------
# 2) Start the control layer (CONTROL=hapi|mindfs, mutually exclusive)
#    Channel selection (same logic for both):
#      Tailscale connected -> private tailnet, third-party relay off (traffic stays in your tailnet)
#      Failed/not configured -> allow the third-party relay as a fallback
#        (HAPI: relay.hapi.run, automatic; MindFS: a9gent.com, one-time manual pairing)
#    HAPI_NO_RELAY / MINDFS_NO_RELAYER can override explicitly.
# 2) 启动控制层（CONTROL=hapi|mindfs，二者互斥）
#    通道选择（两者逻辑一致）：
#      Tailscale 连接成功 → 走私网，关闭第三方中继（流量只在你的 tailnet 内）
#      连接失败/未配置 → 允许第三方中继兜底
#        （HAPI: relay.hapi.run 自动接入；MindFS: a9gent.com，首次需手动绑定一次）
#    可用 HAPI_NO_RELAY / MINDFS_NO_RELAYER 显式覆盖。
# ---------------------------------------------------------------------------
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
LOG_TAIL_FILE=""

if [ "$CONTROL" = "mindfs" ]; then
  # ---- MindFS: single binary service, default port 7331 / 单二进制服务，默认端口 7331 ----
  if [ -z "${MINDFS_NO_RELAYER:-}" ]; then
    if [ "$TS_CONNECTED" = "1" ]; then
      MINDFS_NO_RELAYER=true
    else
      MINDFS_NO_RELAYER=false
    fi
  fi

  if [ "$MINDFS_NO_RELAYER" = "true" ]; then
    if [ "$TS_CONNECTED" = "1" ]; then
      # With Tailscale: bind all interfaces, connect via tailnet IP, disable third-party relay
      # 有 Tailscale：绑定所有网卡，走 tailnet IP 直连，关闭第三方中继
      MIND_ARGS=(-foreground -addr "0.0.0.0:${MINDFS_PORT}" -no-relayer)
      log "MindFS channel: Tailscale (third-party relay off; traffic stays in your tailnet) | MindFS 通道：Tailscale（第三方中继已关闭，流量只在你的 tailnet 内）"
    else
      MIND_ARGS=(-foreground -addr "127.0.0.1:${MINDFS_PORT}" -no-relayer)
      log "WARNING: MINDFS_NO_RELAYER=true but Tailscale is not connected — the service only listens on 127.0.0.1 and cannot be reached remotely! | WARNING: MINDFS_NO_RELAYER=true 但 Tailscale 未连接 —— 服务只监听 127.0.0.1，无法从远程访问！"
      log "         Check TS_AUTHKEY / network, or set MINDFS_NO_RELAYER=false to use the a9gent public relay. | 请检查 TS_AUTHKEY/网络，或把 MINDFS_NO_RELAYER 设为 false 使用 a9gent 公共中继。"
    fi
  else
    # No Tailscale: fall back to the a9gent relay (first time needs a manual UI pairing)
    # 无 Tailscale：允许 a9gent 中继兜底（首次需在本地 UI 点绑定按钮完成配对）
    MIND_ARGS=(-foreground -addr "127.0.0.1:${MINDFS_PORT}")
    log "MindFS channel: a9gent public relay (first time needs a one-time pairing via the bind button in the local UI) | MindFS 通道：a9gent 公共中继（首次需在本地 UI 绑定按钮登录 a9gent.com 完成配对）"
  fi
  if [ "${MINDFS_E2EE:-false}" = "true" ]; then
    MIND_ARGS+=(-e2ee)
    log "MindFS: end-to-end encryption enabled (-e2ee); the pairing secret is printed on first start. | MindFS：已启用端到端加密（-e2ee），首次启动会在日志里打印配对密钥。"
  fi
  MIND_ARGS+=("$WORKSPACE_ROOT")

  log "Starting MindFS: mindfs ${MIND_ARGS[*]} (listen ${MINDFS_PORT})"
  nohup mindfs "${MIND_ARGS[@]}" >"$LOG_DIR/mindfs.log" 2>&1 &
  HUB_PID=$!

  # Wait for the service port to be ready (up to 60s) / 等待服务端口就绪（最长 60s）
  for _ in $(seq 1 60); do
    if (exec 3<> "/dev/tcp/127.0.0.1/${MINDFS_PORT}") 2>/dev/null; then
      exec 3>&- 2>/dev/null || true
      exec 3<&- 2>/dev/null || true
      break
    fi
    sleep 1
  done
  log "MindFS is up (port ${MINDFS_PORT})."
  LOG_TAIL_FILE="$LOG_DIR/mindfs.log"
else
  # ---- HAPI: hub + runner / HAPI：hub + runner ----
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
      log "WARNING: HAPI_NO_RELAY=true but Tailscale is not connected — the hub will only listen on 127.0.0.1 and cannot be reached remotely! | WARNING: HAPI_NO_RELAY=true 但 Tailscale 未连接 —— hub 将只监听 127.0.0.1，无法从远程访问！"
      log "         Check TS_AUTHKEY / network, or set HAPI_NO_RELAY=false to use the official public relay. | 请检查 TS_AUTHKEY/网络，或把 HAPI_NO_RELAY 设为 false 使用官方公共中继。"
    else
      log "HAPI channel: Tailscale (official relay off; traffic stays in your tailnet) | HAPI 通道：Tailscale（官方公共中继已关闭，流量只在你的 tailnet 内）"
    fi
  else
    HUB_ARGS+=(--relay)
    log "HAPI channel: official public relay relay.hapi.run (WireGuard + TLS end-to-end encryption) | HAPI 通道：官方公共中继 relay.hapi.run（WireGuard+TLS 端到端加密）"
  fi

  log "Starting HAPI hub: hapi ${HUB_ARGS[*]} (listen ${HAPI_LISTEN_HOST}:${HAPI_PORT})"
  nohup hapi "${HUB_ARGS[@]}" >"$LOG_DIR/hub.log" 2>&1 &
  HUB_PID=$!

  # Wait for the hub port to be ready (up to 60s) / 等待 hub 端口就绪（最长 60s）
  for _ in $(seq 1 60); do
    if (exec 3<> "/dev/tcp/127.0.0.1/${HAPI_PORT}") 2>/dev/null; then
      exec 3>&- 2>/dev/null || true
      exec 3<&- 2>/dev/null || true
      break
    fi
    sleep 1
  done
  log "HAPI hub is up (port ${HAPI_PORT})."

  # -------------------------------------------------------------------------
  # 3) HAPI runner — create sessions remotely from phone/browser
  #    HAPI runner —— 支持从手机/浏览器远程新建会话
  # -------------------------------------------------------------------------
  RUNNER_ARGS=(runner start --workspace-root "$WORKSPACE_ROOT")
  if [ -n "${RUNNER_EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    RUNNER_ARGS+=($RUNNER_EXTRA_ARGS)
  fi

  log "Starting HAPI runner: hapi ${RUNNER_ARGS[*]}"
  nohup hapi "${RUNNER_ARGS[@]}" >"$LOG_DIR/runner.log" 2>&1 &
  LOG_TAIL_FILE="$LOG_DIR/hub.log"
fi

# ---------------------------------------------------------------------------
# 4) Keep the container alive and stream service logs to stdout
#    保持容器存活，并把服务日志流到 stdout
# ---------------------------------------------------------------------------
cleanup() {
  log "Shutting down..."
  kill "$HUB_PID" "$TAIL_PID" 2>/dev/null || true
  if [ "$CONTROL" = "hapi" ]; then
    hapi runner stop >/dev/null 2>&1 || true
  fi
}
trap cleanup TERM INT

log "Container ready. Control layer: $CONTROL | 容器就绪，控制层：$CONTROL"
if [ "$CONTROL" = "mindfs" ]; then
  log "  - Agents (AGENT=$AGENTS): MindFS auto-detects installed agents (~1 min) | agent（AGENT=$AGENTS）：MindFS 启动后会自动检测已安装的 agent（约 1 分钟）"
  log "    Supported: Claude / Codex / OpenCode / Grok / Cursor / Kimi / Copilot (7) | 支持：Claude / Codex / OpenCode / Grok / Cursor / Kimi / Copilot 共 7 个"
  log "    Pi and Antigravity are not supported by MindFS (they will not show up) | Pi 与 Antigravity 不在 MindFS 支持范围内（即使 AGENT 里装了也不会出现）"
  if [ "$MINDFS_NO_RELAYER" = "true" ] && [ "$TS_CONNECTED" = "1" ]; then
    log "  - Access (Tailscale): install the Tailscale app on your phone with the same tailnet, then open http://<tailnet-IP>:${MINDFS_PORT} | 访问入口（Tailscale）：手机装 Tailscale App 登录同一 tailnet，浏览器打开 http://<tailnet-IP>:${MINDFS_PORT}"
    log "    tailnet IP：docker exec -u devbox <container> tailscale ip -4"
  else
    log "  - Access (a9gent relay): first open http://127.0.0.1:${MINDFS_PORT} locally (or via Tailscale), | 访问入口（a9gent 中继）：先在本地打开 http://127.0.0.1:${MINDFS_PORT}（或经 Tailscale），"
    log "    click the bind button and log in to a9gent.com to pair; then any device can reach it | 在左下角点绑定按钮登录 a9gent.com 完成配对，之后即可从任意设备访问"
  fi
  log "  - Service log: $LOG_DIR/mindfs.log (streamed to stdout) | 服务日志：$LOG_DIR/mindfs.log（已流式输出到 stdout）"
else
  log "  - Agents (AGENT=$AGENTS): pick the CLI when creating a session in the hapi Web UI | agent（AGENT=$AGENTS）：在 hapi Web UI 新建会话时选择用哪个 CLI"
  log "    CLI: docker exec -it -u devbox <container> bash -c 'cd /workspace && hapi' (claude) or 'hapi codex' (codex) | CLI 方式：docker exec -it -u devbox <container> bash -c 'cd /workspace && hapi'（claude）或 'hapi codex'（codex）"
  # hapi only prints the token in public-relay mode (--relay); in direct mode (--no-relay)
  # read it here and print it.
  # hapi 仅在公共中继模式（--relay）打印 token；直连模式（--no-relay）下从这里读取并输出
  HAPI_TOKEN="$(sed -n 's/.*"cliApiToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${HAPI_HOME:-$HOME/.hapi}/settings.json" 2>/dev/null | head -1 || true)"
  if [ "$HAPI_NO_RELAY" = "true" ] && [ "$TS_CONNECTED" = "1" ]; then
    log "  - Access (Tailscale): install the Tailscale app on your phone with the same tailnet, then open http://<tailnet-IP>:${HAPI_PORT} | 访问入口（Tailscale）：手机装 Tailscale App 登录同一 tailnet，浏览器打开 http://<tailnet-IP>:${HAPI_PORT}"
    log "    tailnet IP：docker exec -u devbox <container> tailscale ip -4"
    [ -n "$HAPI_TOKEN" ] && log "    token（cliApiToken）：$HAPI_TOKEN"
    log "    (or read /home/devbox/.hapi/settings.json inside the container) | （token 也可在容器内查看 /home/devbox/.hapi/settings.json）"
  else
    log "  - Access (public relay): docker logs -f <container> (first line has URL + QR), or open https://app.hapi.run and log in with the token | 访问入口（公共中继）：docker logs -f <container>（首行即 URL + 二维码），或访问 https://app.hapi.run 用 token 登录"
    [ -n "$HAPI_TOKEN" ] && log "    token（cliApiToken）：$HAPI_TOKEN"
  fi
  log "  - hub log: $LOG_DIR/hub.log (streamed to stdout) | hub 日志：$LOG_DIR/hub.log（已流式输出到 stdout）"
  log "  - runner log: $LOG_DIR/runner.log | runner 日志：$LOG_DIR/runner.log"
fi

# Background tail keeps the trap in effect (exec would replace the shell, breaking graceful exit)
# 后台 tail 日志流，保持 trap 生效（exec 会替换 shell 导致无法优雅退出）
tail -F "$LOG_TAIL_FILE" &
TAIL_PID=$!
wait "$TAIL_PID" || true
