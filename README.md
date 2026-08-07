# claude-remote：VPS 上的 AI 编程助手远程控制方案

一个 Docker 镜像搞定四件事（**agent CLI 按需安装，镜像本体很小**）：

| 组件 | 作用 |
|------|------|
| **Claude Code** | Anthropic 官方 CLI 编程助手（`AGENT=claude` 时启动自动安装；API 端点和密钥可用环境变量或映射文件配置） |
| **Codex** | OpenAI 官方 CLI 编程助手（`AGENT=codex` 时启动自动安装；与 Claude Code 二选一或并存，新建会话时自由选择） |
| **OpenCode** | 开源 AI 编程助手，自定义 OpenAI 兼容端点最灵活（`AGENT=opencode`；国内网关友好） |
| **Grok Build** | xAI 官方 CLI，`XAI_API_KEY` 即用（`AGENT=grok`） |
| **Cursor Agent** | Cursor 官方 CLI，需 Cursor 账号（`AGENT=cursor`） |
| **Kimi Code** | Moonshot 官方 CLI（已取代 kimi-cli），国内直连快（`AGENT=kimi`） |
| **GitHub Copilot** | GitHub 官方 CLI，官方端点为主（`AGENT=copilot`） |
| **Antigravity** | Google 官方 CLI（agy），需 Google 账号（`AGENT=agy`） |
| **Pi** | Pi coding agent，开源可高度定制（`AGENT=pi`） |
| **[HAPI](https://github.com/tiann/hapi)** | 手机 / 浏览器（PWA）/ Telegram 远程控制 AI 助手：聊天、审批工具权限、远程新建会话、网页终端 |
| **Tailscale** | **主要的远程通道**：WireGuard 加密隧道直连手机和 VPS（不经过第三方）+ Tailscale SSH |

最终效果：**在任何地方用手机或浏览器，就能操作 VPS 上 Docker 里跑的 Claude Code / Codex 等各 AI 编程助手**，无需开放任何公网端口。

---

## 架构

```
                         ┌────────────────────────────────────────┐
                         │  VPS 上的 Docker 容器 (claude-remote)   │
 手机/浏览器(PWA) ───────►│                                        │
   Tailscale App          │  ┌──────────┐  ┌──────────┐            │
   http://100.x.x.x:3006  │  │ HAPI hub │◄►│ HAPI     │            │
   (WireGuard 隧道，      │  │ +SQLite  │  │ runner   │            │
    不经第三方)            │  └────┬─────┘  └────┬─────┘            │
      ▼                   │       │ spawn       │                  │
  ┌──────────────┐        │  ┌────▼─────┐      │                  │
  │ Tailscale     │───────►│  │ Claude / │◄─────┘  (runner 远程    │
  │ SSH 直连      │        │  │ Codex    │          新建会话)       │
  │ (备用通道)     │        │  └──────────┘                        │
  └──────────────┘        │                                        │
                          └────────────────────────────────────────┘
```

- **HAPI hub**：协调中心。Tailscale 连接成功后自动以 `--no-relay` 启动（远程访问完全走你的 tailnet）；未配置或连接失败时自动退回官方公共中继（`relay.hapi.run`，WireGuard + TLS 端到端加密）。首次启动打印 token，用 token 登录 Web UI。
- **HAPI runner**：后台服务，让你**在手机/浏览器上直接新建 Claude Code / Codex 会话**（不需要在服务器上开终端，新建时选 agent）。
- **Tailscale**：**主要的远程通道**。手机/电脑装 Tailscale App 登录同一 tailnet，浏览器打开 `http://<tailnet-IP>:3006` 即可控制 Claude Code。流量是设备间端到端加密的 WireGuard 隧道，**不经过第三方服务器**；无法 P2P 直连时才会由 Tailscale 的 DERP 中继转发（同样加密，看不到内容）。

> 备选：不启用 Tailscale 时自动退回 hapi 官方公共中继（也能用，但流量经过第三方服务器）。想两者同时启用，可显式设 `HAPI_NO_RELAY=false`。

---

## 快速开始

### 1. 准备 .env

```bash
cp .env.example .env
vim .env
```

要安装哪些 agent（决定镜像首次启动时装什么，**国内用户务必设 `NPM_REGISTRY`**）：

```env
AGENT=claude                     # claude/codex/opencode/grok/cursor/kimi/copilot/agy/pi 任意组合 / none
NPM_REGISTRY=https://registry.npmjs.org   # 国内建议 https://registry.npmmirror.com
```

必填项（Claude Code 的 API 配置）：

```env
ANTHROPIC_BASE_URL=https://你的API网关地址        # 第三方端点必填
ANTHROPIC_API_KEY=sk-xxx                          # 你的密钥
```

推荐：Tailscale auth key（**推荐配置**，在 <https://login.tailscale.com/admin/settings/keys> 生成；不配置则自动退回 hapi 官方公共中继，也能用，但流量经过第三方服务器）

```env
TS_AUTHKEY=tskey-auth-xxxx
TS_HOSTNAME=claude-vps
```

### 2. 构建并启动

```bash
# 重要：workspace 目录要让容器内的 claude 用户（uid 1000）可写
mkdir -p workspace && sudo chown -R 1000:1000 workspace

docker compose up -d --build
```

> 容器以非 root 用户（uid 1000）运行。如果 `./workspace` 是 root 创建的，Claude Code 将无法写入——务必先执行上面的 chown。
> **首次启动**会按 `AGENT` 设置安装对应 CLI（日志里能看到安装进度，安装到 `~/.local/bin`）。想跳过下载用 `AGENT=none`。

### 3. 拿到访问入口（Tailscale 方式）

**手机/电脑上安装 Tailscale App**（<https://tailscale.com/download>），登录**与 VPS 同一个 tailnet 账号**。然后浏览器打开：

```
http://<容器tailnet-IP>:3006
```

tailnet IP 在哪看：

```bash
docker compose logs | grep 'Tailscale connected'    # 容器日志里有
# 或
docker exec claude-remote tailscale ip -4
```

首次打开 Web UI 时用日志里的 **token** 登录（token 已持久化在 `hapi-config` 卷中，重启不丢）。之后就能看到你的 VPS 机器，新建/管理各 agent 会话了。

> 把 Web 应用添加到手机主屏幕（PWA），体验接近原生 App。
> 提示：在 Tailscale 管理后台为该节点启用 **HTTPS 证书** 后，还可通过 `https://claude-vps.<你的tailnet>.ts.net` 访问（自动 HTTPS）。

**token 忘了？**

```bash
docker exec claude-remote cat /home/claude/.hapi/settings.json   # 找 cliApiToken
```

> **没配置 `TS_AUTHKEY`？**（走公共中继模式）`docker compose logs -f` 里会打印 **URL + 二维码 + token**，扫码/打开 URL 输入 token 登录即可，或直接访问 <https://app.hapi.run>。

### 4. 首次使用 Claude Code（一次性）

容器内的 Claude Code 需要先认领你的 API Key（首次会确认一次）。在 VPS 上执行：

```bash
# 进入容器
docker exec -it claude-remote bash

# 手动跑一次 claude，按提示确认使用环境变量中的 key（或完成登录）
cd /workspace && claude

# 验证
claude --version
exit
```

确认一次后，凭证会持久化在 `claude-config` 卷（`/home/claude/.claude`）里，之后从手机发起的会话不会再问。**此后日常使用完全不用再碰服务器终端。**（若你用的主要是其他 agent，其首次认证见下文"各 agent 认证速查"。）

### 5. 选择用哪个 CLI

镜像按 `AGENT` 设置安装所需 CLI（claude / codex / opencode / grok / cursor / kimi / copilot / agy / pi），两种方式任选：

- **手机/浏览器**：在 hapi Web UI 的"新建会话"（New session）页面选择 agent，之后照样聊天、审批权限、远程接管。
- **命令行**（在 VPS 上）：

```bash
docker exec -it claude-remote bash
cd /workspace && hapi          # 默认 Claude Code
cd /workspace && hapi codex    # 指定 agent，如 hapi grok / hapi opencode ...
```

> 各 agent 的会话都会出现在同一个 hapi Web UI 里，互不影响。各 agent 首次使用前需完成各自认证（见下文"各 agent 认证速查"）。

### 6. 一键体检

想确认容器里 agent 装好没、版本多少、配置/认证是否就绪：

```bash
./scripts/agents-report.sh               # 容器名默认 claude-remote
CONTAINER=my-container ./scripts/agents-report.sh
```

输出 5 部分：① 各 agent 安装状态 + 版本 ② 配置文件（codex/grok/opencode/claude）③ API 环境变量（密钥打码）④ 认证状态 ⑤ 安装失败日志线索。

---

## 配置详解

### 全部环境变量一览

所有变量在 `.env` 中设置（复制自 `.env.example`），下面按类别汇总为索引；**完整默认值与详细说明以 `.env.example` 为准**，各变量详情见对应小节。

| 类别 | 变量 | 默认 | 说明（详见） |
|------|------|------|------|
| **Agent 安装** | `AGENT` | `claude` | 启动时安装哪些 CLI（见「Agent 安装」） |
| | `NPM_REGISTRY` | `https://registry.npmjs.org` | npm 镜像，国内建议 npmmirror |
| | `CLAUDE_VERSION` / `CODEX_VERSION` / `OPENCODE_VERSION` / `COPILOT_VERSION` / `PI_VERSION` | `latest` | 版本锁定（仅 npm 安装的 agent） |
| **Claude Code** | `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` | API 端点/网关 |
| | `ANTHROPIC_API_KEY` | - | 密钥（x-api-key） |
| | `ANTHROPIC_AUTH_TOKEN` | - | 备选 Bearer token（见「Claude Code API 端点」） |
| **Codex** | `OPENAI_API_KEY` | - | 官方 key（一次性登录） |
| | `CODEX_BASE_URL` / `CODEX_API_KEY` / `CODEX_MODEL` | - | 第三方网关自动生成 config.toml（见「Codex 配置」） |
| **OpenCode** | `OPENAI_API_KEY` | - | 标准 provider env |
| | `OPENCODE_BASE_URL` / `OPENCODE_API_KEY` / `OPENCODE_MODEL` | - | 第三方网关自动生成 opencode.json（见「OpenCode / Pi 第三方网关」） |
| **Grok** | `XAI_API_KEY` | - | 官方 xAI 端点 |
| | `GROK_BASE_URL` / `GROK_API_KEY` / `GROK_MODEL` | - | 第三方中转自动生成 config.toml（见「Grok 第三方中转」） |
| | `GROK_API_BACKEND` | `chat_completions` | `chat_completions`（默认，最通用）/ `responses` / `messages` |
| **Kimi** | `KIMI_API_KEY` | - | Moonshot 官方端点 |
| **Pi** | `PI_BASE_URL` / `PI_API_KEY` / `PI_MODEL` | - | 第三方网关自动生成 `~/.pi/agent/models.json`（见「OpenCode / Pi 第三方网关」） |
| | `PI_API` | `openai-completions` | `openai-completions`（默认）/ `openai-responses` / `anthropic-messages` / `google-generative-ai` |
| **HAPI** | `HAPI_NO_RELAY` | 留空 | 留空=自动（有 Tailscale 走私网、无则公共中继）；`true`=仅 Tailscale；`false`=强制公共中继 |
| | `HAPI_LISTEN_HOST` / `HAPI_LISTEN_PORT` | `127.0.0.1` / `3006` | hub 监听地址/端口（见「HAPI 配置」） |
| | `HAPI_RELAY_FORCE_TCP` | `false` | `false`（默认）/ `true`（公共中继 UDP 不通时强制 TCP） |
| | `TELEGRAM_BOT_TOKEN` / `SERVERCHAN_SENDKEY` | - | 可选：权限审批推送通知 |
| **Tailscale** | `TS_AUTHKEY` | 空 | 留空=不启用 Tailscale |
| | `TS_HOSTNAME` | `claude-vps` | tailnet 节点名 |
| | `TS_SSH` | `true` | `true`（默认，启用 Tailscale SSH）/ `false`（关闭） |
| | `TS_EXTRA_ARGS` | - | 额外 `tailscale up` 参数（空格分隔） |

### Grok 第三方中转

Grok Build 支持自定义端点（`~/.grok/config.toml` 的 `[model.*]` 块），中转站可用。设置以下变量，启动时自动生成配置（与 Codex 的 `CODEX_*` 同理，不覆盖已挂载的 config.toml）：

```env
GROK_BASE_URL=https://your-gateway.com/v1
GROK_API_KEY=sk-...
GROK_MODEL=grok-4.5            # 中转站实际的模型名
GROK_API_BACKEND=chat_completions   # chat_completions / responses / messages
```

> 生成的配置等价于 `[model.custom]`：`model` / `base_url` / `api_backend` / `env_key = "GROK_API_KEY"`。
> **重要**：中转配置只在**显式选择 `custom` 模型**时生效——hapi Web UI 新建会话时选 `custom`（若模型目录里没显示，用命令行 `docker exec -it claude-remote bash -c 'cd /workspace && grok -m custom'` 验证）；不选则仍走 xAI 官方端点（需要 `XAI_API_KEY`）。官方端点无需以上变量，`XAI_API_KEY` 即可。

### OpenCode / Pi 第三方网关（环境变量自动生成）

OpenCode 和 Pi 都支持环境变量自动生成配置（与 Codex 的 `CODEX_*` / Grok 的 `GROK_*` 同理：不覆盖已挂载的配置文件，apiKey 用环境变量插值**不落盘**）：

```env
# OpenCode：生成 ~/.config/opencode/opencode.json（provider 名 custom，npm @ai-sdk/openai-compatible）
OPENCODE_BASE_URL=https://your-gateway.com/v1
OPENCODE_API_KEY=sk-...
OPENCODE_MODEL=gpt-4o-mini

# Pi：生成 ~/.pi/agent/models.json（provider 名 custom）
PI_BASE_URL=https://your-gateway.com/v1
PI_API_KEY=sk-...
PI_MODEL=gpt-4o-mini
PI_API=openai-completions      # 可选：openai-completions(默认) / openai-responses / anthropic-messages / google-generative-ai
```

> OpenCode 生成的 opencode.json 里 `apiKey` 写 `{env:OPENCODE_API_KEY}`，Pi 生成的 models.json 里 `apiKey` 写 `$PI_API_KEY`——密钥都只在运行时从环境变量读取。只设置其中一个变量（如只设 BASE_URL 不设 KEY）会打警告且不生成；手动挂载的配置文件优先，不会被覆盖。手动配置示例：OpenCode 见 [`examples/opencode.example.json`](examples/opencode.example.json)，Pi 见 [`examples/pi.models.example.json`](examples/pi.models.example.json)。
>
> 两个注意点：① OpenCode 的 `{env:...}` 插值在个别版本/网关组合下可能解析失败——若生成的配置认证报错，改用 `docker exec -it claude-remote opencode auth login` 或挂载含内联 key 的 opencode.json；② Pi 生成的 models.json 默认 `reasoning: false`，如果 `PI_MODEL` 用的是推理模型（如 deepseek-r1），需手动把该字段改为 `true`。

### 自定义端点/中转支持一览

| CLI | 自定义端点 | 说明 |
|-----|:---:|------|
| Claude Code | ✅ | `ANTHROPIC_BASE_URL` + `ANTHROPIC_API_KEY` |
| Codex | ✅ | `CODEX_BASE_URL` + `CODEX_API_KEY`（网关需支持 Responses API） |
| OpenCode | ✅ | `OPENCODE_BASE_URL` + `OPENCODE_API_KEY` 自动生成 opencode.json（或手动挂载） |
| Grok Build | ✅ | `GROK_BASE_URL` + `GROK_API_KEY`（api_backend 可切 chat_completions/responses/messages） |
| Kimi Code | ❌ | 官方端点为主（`KIMI_API_KEY`），不提供自定义 baseUrl 配置 |
| Copilot | ❌ | 官方端点为主（GitHub 登录），不提供 BYOK 配置 |
| Pi | ✅ | 纯第三方 provider（无官方后端）；`PI_BASE_URL` + `PI_API_KEY` 自动生成 models.json |
| Cursor Agent | ❌ | **官方限定**：CLI 流量全部走 Cursor 后端，需 Cursor 账号/订阅，API key 必须是 Cursor Dashboard 签发 |
| Antigravity | ❌ | 锁 Google OAuth/Vertex AI，不支持自定义端点 |

> 主力 agent（Claude Code / Codex / OpenCode / Grok）都建议接第三方中转站（OneAPI/NewAPI 等）；Copilot / Kimi 以官方端点为主（不提供 BYOK/自定义端点配置——非 CLI 能力限制，只是本项目不折腾）；Pi 本来就是纯第三方 provider（无官方后端，必须自己配 models.json）。Cursor 和 Antigravity 因闭源商业设计无法绕开。

### Agent 安装（AGENT / NPM_REGISTRY）

镜像里只预装 hapi 和 Tailscale，**各 agent CLI 在容器启动时按需安装**（用户级 npm prefix，无需 root），因此镜像体积很小，且国内用户可用镜像加速。

| 变量 | 默认 | 说明 |
|------|------|------|
| `AGENT` | `claude` | 逗号分隔组合：`claude` / `codex` / `opencode` / `grok` / `cursor` / `kimi` / `copilot` / `agy` / `pi` / `none` |
| `NPM_REGISTRY` | `https://registry.npmjs.org` | npm 镜像。国内建议 `https://registry.npmmirror.com` |
| `CLAUDE_VERSION` / `CODEX_VERSION` / `OPENCODE_VERSION` / `COPILOT_VERSION` / `PI_VERSION` | `latest` | 版本锁定（仅对 npm 安装的 agent 生效） |

> 注：`kimi` / `agy` 走上游 curl 安装脚本（`code.kimi.com` / `antigravity.google`），URL 若变更会安装失败（日志见 `/tmp/install-<agent>.log`），可 `docker exec -it claude-remote bash` 手动安装；`pi` 的 npm 包若安装失败可换 `@mariozechner/pi-coding-agent`。

> grok / cursor 走官方 curl 安装脚本（不走 npm registry，国内下载可能较慢）；安装脚本以非 root 用户运行，若脚本需要 root（如装到 /usr/local/bin）会失败——此时可先 `docker exec -it claude-remote bash` 手动安装，或把安装结果所在的 `~/.local` 挂为卷缓存。装完需各自完成认证（见下）。

### 各 agent 认证速查

| Agent | 认证方式 | 说明 |
|-------|---------|------|
| Claude Code | `ANTHROPIC_BASE_URL` + `ANTHROPIC_API_KEY` | 首次 `claude` 确认一次，缓存于 `claude-config` 卷 |
| Codex | `OPENAI_API_KEY`（`codex login --with-api-key`）或 `CODEX_BASE_URL`/`CODEX_API_KEY`（自动生成 config.toml） | 需网关支持 Responses API |
| OpenCode | 标准 provider env（如 `OPENAI_API_KEY`），或 `OPENCODE_BASE_URL` + `OPENCODE_API_KEY`（自动生成 opencode.json） | 自定义 provider 的 key 用 `{env:...}` 插值或 `opencode auth` 提供；手动配置示例见 [`examples/opencode.example.json`](examples/opencode.example.json)，详见 [opencode.ai](https://opencode.ai/docs) |
| Grok | `XAI_API_KEY=xai-...`（官方端点）或 `GROK_BASE_URL` + `GROK_API_KEY`（第三方中转，自动生成 `~/.grok/config.toml`） | 中转的 `api_backend` 默认 `chat_completions`（最通用），也可 `responses` / `messages` |
| Cursor | Cursor 账号 OAuth（或 Cursor Dashboard 签发的 API key） | 首次执行 `docker exec -it claude-remote agent login`；**锁死 Cursor 官方后端，不支持自定义端点/中转** |
| Kimi Code | `KIMI_API_KEY`（Moonshot 控制台） | 官方端点 |
| Copilot | GitHub 登录（`copilot login`） | 官方端点；首次 `docker exec -it claude-remote copilot login` |
| Antigravity | Google OAuth | 需 `docker exec -it claude-remote agy` 完成登录；不支持自定义端点 |
| Pi | `PI_BASE_URL` + `PI_API_KEY`（自动生成 models.json），或手动配 `~/.pi/agent/models.json` | 纯第三方、无官方后端，必须配 provider；无本地 TUI（remote-only），`apiKey` 支持 `$ENV_VAR` 插值；手动配置示例见 [`examples/pi.models.example.json`](examples/pi.models.example.json) |

> 已安装的 agent 会检测到并跳过安装（`command -v`）。把 `~/.local` 挂成卷（`agent-bin`，见 docker-compose 注释）可让重启不重新下载。
> 改了 `AGENT` 后需 `docker compose up -d` 重建容器生效（改 `NPM_REGISTRY` 同理）。
> **构建时也用镜像**（hapi 是构建时装进镜像的）：国内构建 `docker build --build-arg NPM_REGISTRY=https://registry.npmmirror.com .`，或直接改 `docker-compose.yml` 里 `build.args`。⚠️ 注意：hapi 官方建议用官方 registry（**镜像源同步平台二进制包可能不及时**），若换源后构建失败（hapi 安装报错），请回退官方 registry 构建，agent 的镜像加速不受影响（agent 是运行时按 `NPM_REGISTRY` 装的）。

### Claude Code API 端点 / 密钥（两种方式，二选一）

**方式一：环境变量**（推荐，改 `.env` 后 `docker compose up -d` 重启即可）

| 变量 | 说明 |
|------|------|
| `ANTHROPIC_BASE_URL` | 第三方/代理 API 端点，如 OneAPI / NewAPI / DeepSeek 等兼容网关 |
| `ANTHROPIC_API_KEY` | 你的 API Key（以 `x-api-key` 头发送） |
| `ANTHROPIC_AUTH_TOKEN` | 备选：以 `Authorization: Bearer` 发送的 token（某些网关用） |

**方式二：映射文件**：把配置写到容器内 `/home/claude/.claude/settings.json`，参考 [`examples/claude-settings.example.json`](examples/claude-settings.example.json)。可在 docker-compose 中加一行卷映射：

```yaml
    volumes:
      - ./examples/claude-settings.example.json:/home/claude/.claude/settings.json:ro
```

环境变量优先级高于 settings.json，同时设置时以环境变量为准。

### Codex 配置（可选）

`AGENT` 里包含 `codex` 时启动会自动安装 CLI，三种配置方式任选：

**方式 A：OpenAI 官方 API key**（.env 里设 `OPENAI_API_KEY`，一次性登录）：

```bash
docker exec -it claude-remote bash -c 'printenv OPENAI_API_KEY | codex login --with-api-key'
```

登录缓存保存在 `codex-config` 卷（`/home/claude/.codex/auth.json`），重启不丢。

**方式 B：第三方/代理网关**（.env 里设置，启动时自动生成 `~/.codex/config.toml`，无需登录）：

```env
CODEX_BASE_URL=https://your-gateway.com/v1
CODEX_API_KEY=sk-...
CODEX_MODEL=gpt-5.1     # 可选，默认 gpt-5.1
```

生成的配置等价于：

```toml
model_provider = "custom"
model = "gpt-5.1"

[model_providers.custom]
name = "custom gateway"
base_url = "https://your-gateway.com/v1"
env_key = "CODEX_API_KEY"
wire_api = "responses"
```

> ⚠️ **注意**：Codex 的 `wire_api` 目前**只支持 `responses`**（OpenAI Responses API）。很多中转站/网关只实现 `/v1/chat/completions`，与 Codex 不兼容，选网关时先确认其支持 `/v1/responses`。

**方式 C：挂载自定义配置文件**（文件方式，优先级最高，不会被启动脚本覆盖）：

```yaml
    volumes:
      - ./codex-config.toml:/home/claude/.codex/config.toml:ro
```

> 想用 ChatGPT 账号（Plus/Pro）登录？headless 环境下跑 `docker exec -it claude-remote bash -c 'codex login --device-auth'`，按提示在浏览器完成设备码认证。

### HAPI 配置

| 变量 | 默认 | 说明 |
|------|------|------|
| `HAPI_NO_RELAY` | 智能 | 留空 = 自动（有 Tailscale 走私网、无则走公共中继）；`true` 强制关公共中继；`false` 强制用公共中继 |
| `HAPI_LISTEN_HOST` | `127.0.0.1` | 设置了 `TS_AUTHKEY` 时自动改为 `0.0.0.0` 以便 tailnet 直连 |
| `HAPI_LISTEN_PORT` | `3006` | hub 端口 |
| `HAPI_RELAY_FORCE_TCP` | `false` | `false`（默认）/ `true`：仅公共中继模式下 UDP 不通（公司网络等）时强制走 TCP |
| `TELEGRAM_BOT_TOKEN` / `SERVERCHAN_SENDKEY` | - | 可选：权限审批的推送通知 |

其他高级项（`CORS_ORIGINS`、`HAPI_PUBLIC_URL` 等）参考 [hapi 官方文档](https://github.com/tiann/hapi/blob/main/docs/guide/installation.md)。

### Tailscale 配置

| 变量 | 默认 | 说明 |
|------|------|------|
| `TS_AUTHKEY` | 空 | 留空则不启用 Tailscale |
| `TS_HOSTNAME` | `claude-vps` | tailnet 中的节点名 |
| `TS_SSH` | `true` | `true`（默认）启用 Tailscale SSH / `false` 关闭（启用时需在管理后台勾选该节点的 SSH） |
| `TS_EXTRA_ARGS` | - | 额外的 `tailscale up` 参数，如 `--accept-routes` |

启用后（Tailscale 是默认的主通道）：

- **远程控制 Claude Code**：手机/电脑装 Tailscale App → 浏览器打开 `http://<tailnet-IP>:3006`（hapi Web UI）。
- **SSH 直连**：任意已登录 tailnet 的设备 `ssh claude@claude-vps`（Tailscale SSH 基于你的 tailnet 身份认证，无需管理密钥）。

> **关于"中继"**：Tailscale 优先建立设备间点对点（P2P）WireGuard 隧道；只有无法直连（如严格 NAT）时才经官方 DERP 中继服务器转发——转发同样端到端加密，中继看不到内容。对保密要求极高可自建 DERP 服务器。

---

## 持久化与数据

| 卷 | 容器路径 | 内容 |
|----|----------|------|
| `./workspace`（bind） | `/workspace` | 代码工作区，宿主机直接可见 |
| `claude-config` | `/home/claude/.claude` | Claude Code 认证、settings、会话历史 |
| `agent-bin`（可选，注释中） | `/home/claude/.local` | 按需安装的 agent 二进制缓存（重启不重装） |
| `codex-config` | `/home/claude/.codex` | Codex 配置（config.toml）、登录缓存（auth.json） |
| `grok-config` | `/home/claude/.grok` | Grok 配置（config.toml）、登录缓存（auth.json） |
| `pi-config` | `/home/claude/.pi` | Pi 配置（models.json） |
| `opencode-config` | `/home/claude/.config/opencode` | OpenCode 配置（opencode.json） |
| `hapi-config` | `/home/claude/.hapi` | HAPI hub 数据库、token、日志 |
| `tailscale-state` | `/var/lib/tailscale` | Tailscale 状态（重启容器不会重新认证） |

日常维护建议：把 `./workspace` 挂载到 VPS 上一个目录，并建议对 workspace 做 git 管理。

---

## 安全建议

- **不要**把 `.env` 提交到 git（已在 `.gitignore` 中忽略）；API key 只存在于运行时环境变量和卷中，不会打进镜像。
- HAPI 默认绑定 `127.0.0.1`；启用 Tailscale 后自动绑定 `0.0.0.0`（仅 tailnet 私网可达，公网不通）。
- 走 Tailscale 通道时，手机与 VPS 之间是端到端加密的 WireGuard 隧道，**不经过任何第三方服务器**（DERP 中继仅在你无法 P2P 直连时介入，且同样加密）。
- 若 VPS 有公网 IP 且开启了防火墙（ufw），不需要放行 3006 端口——远程访问全部走 relay 或 tailnet。
- 定期轮换 `ANTHROPIC_API_KEY` 与 hapi 的访问 token（`/home/claude/.hapi/settings.json` 中的 `cliApiToken`）。
- 在 Tailscale 管理后台为新节点**关闭 key 过期**（Disable key expiry），避免节点到期掉线。

---

## 常见问题

**Q: `docker compose logs` 里没看到 URL / 二维码？**
A: 稍等几秒再刷新日志；relay 首次接入需要时间。若一直失败，试 `HAPI_RELAY_FORCE_TCP=true`。也可进容器跑 `hapi doctor` 看诊断。

**Q: 想直接命令行跑一个会话而不是用手机？**
A: `docker exec -it claude-remote bash`，然后 `cd /workspace && claude`（或 `hapi codex`）。这个会话同样会被 HAPI 接管，手机上可以随时接管（hapi 的 seamless handoff）。

**Q: hapi Web UI 新建会话时怎么选 agent？**
A: 新建会话页面的 agent 选择器里选择即可（runner 会注册 `AGENT` 里安装的所有 agent：claude / codex / opencode / grok / cursor / kimi / copilot / agy / pi）。首次使用前先完成对应认证（见上文"各 agent 认证速查"）。

**Q: 用了第三方网关但 Codex 报错/不兼容？**
A: 检查网关是否支持 OpenAI **Responses API**（`/v1/responses`）。Codex 的 `wire_api` 只支持 `responses`；只提供 `/v1/chat/completions` 的网关建议改用 Claude Code。

**Q: 如何更新某个 agent？**
A: 改 `.env` 里的版本变量（`CLAUDE_VERSION` / `CODEX_VERSION` / `OPENCODE_VERSION` / `COPILOT_VERSION` / `PI_VERSION`）后 `docker compose up -d`。已安装的旧版本会阻止重装（跳过检测），先手动删除：`docker exec claude-remote bash -c 'rm -rf ~/.local/lib/node_modules/<包名> ~/.local/bin/<命令>'`（如 claude：`@anthropic-ai` + `claude`；codex：`@openai` + `codex`；opencode：`opencode-ai` + `opencode`；copilot：`@github` + `copilot`；pi：`@earendil-works` + `pi`）。

**Q: 镜像为什么这么小？agent 装在哪？**
A: 镜像只含 hapi + Tailscale（约 1GB 级系统依赖）；各 agent CLI 二进制（claude/codex 等各数百 MB）在容器首次启动时按 `AGENT` 装到 `~/.local/bin`。想彻底不装可设 `AGENT=none`；想持久化到重启不重装可挂载 `agent-bin` 卷。

**Q: 国内安装慢 / 装不上？**
A: npm 安装的 agent（claude/codex/opencode/copilot/pi）在 `.env` 里设 `NPM_REGISTRY=https://registry.npmmirror.com` 后重启容器。grok/cursor/kimi/agy 走官方 curl 脚本（x.ai / cursor.com / code.kimi.com / antigravity.google），国内可能需代理或手动在容器内安装。安装日志在 `/tmp/install-<agent>.log`。**hapi 是构建时装进镜像的**（不走运行时 `NPM_REGISTRY`）：官方建议用官方 registry，镜像源同步其平台二进制包可能滞后——若 `docker compose build` 时 hapi 安装失败，用官方 registry 构建即可（`docker build --build-arg NPM_REGISTRY=https://registry.npmjs.org .`）。

**Q: Tailscale 没起来？**
A: `docker exec claude-remote cat /tmp/tailscale-up.log` 查看原因。确认 `TS_AUTHKEY` 有效、管理后台已批准节点（ephemeral key 或 reuseable key）。

**Q: 想彻底不用 hapi 官方公共中继（relay.hapi.run）？**
A: 配置 `TS_AUTHKEY` 即可——entrypoint 会自动用 `--no-relay` 启动 hub，远程访问完全走 Tailscale。也可参考 hapi 文档配置 Cloudflare Tunnel 等自托管隧道。

**Q: 明明走 Tailscale，为什么日志里还提到公共服务器？**
A: 那是 Tailscale 自身的 DERP 中继：无法 P2P 直连时它才介入，且只做加密转发、看不到内容。介意的话可以自建 DERP，或确认手机与 VPS 网络允许 UDP 直连。

---

## 相关链接

- HAPI 仓库：<https://github.com/tiann/hapi>
- HAPI 安装/部署文档：<https://github.com/tiann/hapi/blob/main/docs/guide/installation.md>
- Claude Code 开发容器文档：<https://code.claude.com/docs/en/devcontainer>
- Tailscale Docker 文档：<https://tailscale.com/kb/1282/docker>
