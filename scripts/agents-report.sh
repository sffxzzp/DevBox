#!/usr/bin/env bash
# =============================================================================
# agents-report.sh — 一键体检 claude-remote 容器内的 agent 状态
#
# 用法：
#   ./scripts/agents-report.sh                 # 容器名默认 claude-remote
#   CONTAINER=my-container ./scripts/agents-report.sh
#
# 输出：各 agent 安装/版本、配置文件、API 环境变量（key 打码）、认证状态、安装日志
# =============================================================================
set -euo pipefail

CONTAINER="${CONTAINER:-claude-remote}"

# ---- 检查容器是否在运行 -------------------------------------------------------
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
  echo "ERROR: container '$CONTAINER' 未在运行（先 docker compose up -d）。" >&2
  exit 1
fi

echo "=== claude-remote agent 体检报告（容器: $CONTAINER） ==="
echo

# ---- 容器内检查逻辑（通过 stdin 传给 docker exec）-------------------------------
docker exec -i "$CONTAINER" bash -s <<'REPORT'
set -uo pipefail

# 名称 / bin / 版本命令
# timeout 来自 coreutils（Debian slim 自带）；万一缺失则降级为直接调用
TIMEOUT=""
command -v timeout >/dev/null 2>&1 && TIMEOUT="timeout 5"
declare -A BIN=(
  [claude]="claude" [codex]="codex" [opencode]="opencode" [grok]="grok"
  [cursor]="agent"  [kimi]="kimi"   [copilot]="copilot" [agy]="agy" [pi]="pi"
)
version_of() {
  case "$1" in
    claude)  $TIMEOUT claude --version  2>/dev/null | head -1 ;;
    codex)   $TIMEOUT codex --version   2>/dev/null | head -1 ;;
    opencode) $TIMEOUT opencode --version 2>/dev/null | head -1 ;;
    grok)    $TIMEOUT grok version      2>/dev/null | head -1 ;;
    cursor)  $TIMEOUT agent --version   2>/dev/null | head -1 ;;
    kimi)    $TIMEOUT kimi --version    2>/dev/null | head -1 ;;
    copilot) $TIMEOUT copilot --version 2>/dev/null | head -1 ;;
    agy)     $TIMEOUT agy --version     2>/dev/null | head -1 ;;
    pi)      $TIMEOUT pi --version      2>/dev/null | head -1 ;;
    *) echo "N/A" ;;
  esac
}

# ---- 1. agent 安装状态 ---------------------------------------------------------
echo "── 1. Agent 安装状态（AGENT=${AGENT:-未设置}） ──────────────────────────"
printf "%-9s %-10s %-9s %s\n" "agent" "bin" "状态" "版本"
for name in claude codex opencode grok cursor kimi copilot agy pi; do
  bin="${BIN[$name]}"
  if command -v "$bin" >/dev/null 2>&1; then
    printf "%-9s %-10s %-9s %s\n" "$name" "$bin" "✅ 已装" "$(version_of "$name")"
  else
    printf "%-9s %-10s %-9s %s\n" "$name" "$bin" "❌ 未装" "-"
  fi
done

# ---- 2. 配置文件 ---------------------------------------------------------------
echo
echo "── 2. 配置文件 ─────────────────────────────────────────────────────────"
check_file() { # 描述 路径 [提取行]
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    local extra=""
    if [ -n "${3:-}" ]; then
      extra=$(grep -E "$3" "$path" 2>/dev/null | head -1 | sed -E 's/.*"(https?[^"]*)".*/base_url=\1/' | sed -E 's#(https?://[^/]+).*#\1#')
      [ -n "$extra" ] && extra="（$extra）"
    fi
    printf "%-28s %-6s %s\n" "$desc" "✅" "$path$extra"
  else
    printf "%-28s %-6s %s\n" "$desc" "❌" "$path（未生成/未挂载）"
  fi
}
check_file "claude settings"        "$HOME/.claude/settings.json"
check_file "codex config"           "$HOME/.codex/config.toml"    'base_url'
check_file "grok config"            "$HOME/.grok/config.toml"     'base_url'
check_file "opencode config"        "$HOME/.config/opencode/opencode.json"
check_file "pi models"              "$HOME/.pi/agent/models.json"

# ---- 3. API 环境变量（key 打码）-------------------------------------------------
echo
echo "── 3. API 环境变量（密钥已打码） ────────────────────────────────────────"
mask() { # 环境变量名
  local v="${!1:-}"
  if [ -n "$v" ]; then
    if [ "${#v}" -ge 8 ]; then echo "✅ ${1:0:24} = ${v:0:4}…${v: -4}"
    else echo "✅ ${1:0:24} = ****"; fi
  else
    echo "❌ ${1:0:24} = （未设置）"
  fi
}
url_or_mask() { # 环境变量名（URL 不打码，key 打码）
  local v="${!1:-}"
  if [ -n "$v" ]; then echo "✅ $1 = $v"; else echo "❌ $1 = （未设置）"; fi
}
url_or_mask ANTHROPIC_BASE_URL
mask        ANTHROPIC_API_KEY
mask        OPENAI_API_KEY
mask        XAI_API_KEY
mask        KIMI_API_KEY
url_or_mask CODEX_BASE_URL
url_or_mask GROK_BASE_URL
url_or_mask OPENCODE_BASE_URL
mask        OPENCODE_API_KEY
url_or_mask PI_BASE_URL
mask        PI_API_KEY

# ---- 4. 认证状态 ---------------------------------------------------------------
echo
echo "── 4. 认证状态 ─────────────────────────────────────────────────────────"
[ -f "$HOME/.codex/auth.json" ]       && echo "✅ codex auth（~/.codex/auth.json）" || echo "❌ codex 未认证（或用 env_key 方式）"
if [ -n "${COPILOT_GITHUB_TOKEN:-}${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
  echo "✅ copilot 使用环境变量 token（COPILOT_GITHUB_TOKEN / GH_TOKEN / GITHUB_TOKEN）"
elif [ -f "$HOME/.copilot/config.json" ] && grep -q 'loggedInUsers' "$HOME/.copilot/config.json" 2>/dev/null; then
  echo "✅ copilot 已登录（~/.copilot/config.json；token 优先存系统 keychain，无 keychain 时回退此文件）"
else
  echo "❌ copilot 未登录（docker exec -it claude-remote copilot login）"
fi
[ -n "${ANTHROPIC_API_KEY:-}" ]       && echo "✅ claude 使用环境变量 key"        || echo "❌ claude 未配置 key（或用 settings.json）"
[ -n "${XAI_API_KEY:-}" ]             && echo "✅ grok 使用环境变量 key"          || echo "❌ grok 未配置 key（或走官方登录）"
[ -n "${KIMI_API_KEY:-}" ]            && echo "✅ kimi 使用环境变量 key"          || echo "❌ kimi 未配置 key"
[ -n "${PI_API_KEY:-}" ]               && echo "✅ pi 使用环境变量 key（models.json 插值）" || echo "❌ pi 未配置 key（或手动配置 models.json）"

# ---- 5. 安装日志线索 ------------------------------------------------------------
echo
echo "── 5. 安装日志（/tmp/install-*.log） ────────────────────────────────────"
logs=$(ls /tmp/install-*.log 2>/dev/null || true)
if [ -n "$logs" ]; then
  echo "$logs"
  # 标记最近一次失败
  for f in $logs; do
    if grep -qiE 'error|failed|E403|ENOTFOUND|ETIMEDOUT' "$f" 2>/dev/null; then
      echo "  ⚠️  $f 中有错误/失败关键字，请查看详情"
    fi
  done
else
  echo "（无安装日志 —— 容器首次启动未触发安装，或未安装任何 agent）"
fi

echo
echo "=== 体检完成。提示：hapi doctor 可看 hapi 自身状态 ==="
REPORT
