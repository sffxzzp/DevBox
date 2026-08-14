# devbox: Remote AI coding assistants on your VPS (mobile/browser)

> English is the default. 中文请见下方「中文版」。

A Docker image that lets you run **9 AI coding assistants** on your VPS (**Claude Code, Codex, OpenCode, Grok, Cursor, Kimi, Copilot, Antigravity, Pi**) and operate them remotely from your **phone or browser** without opening public ports.

- 📱 **Mobile/browser ready**: hapi Web UI (PWA-capable), remote chat, tool-approval, remote session creation
- 🔒 **Tailscale direct access (recommended)**: end-to-end encrypted private tunnel
- 🧩 **Install agents on demand**: no preinstalled CLIs, smaller image size
- 💾 **Persistent data**: auth, config, and code are stored on host volumes

---

## Quick Start

### 1) Prepare config

```bash
cp .env.example .env
```

Edit `.env` and configure at least one agent key, for example Claude Code:

```env
ANTHROPIC_BASE_URL=https://your-api-gateway
ANTHROPIC_API_KEY=sk-xxx
```

Recommended (direct phone-to-VPS access via Tailscale):

```env
TS_AUTHKEY=tskey-auth-xxxx
TS_HOSTNAME=devbox-vps
```

If needed in mainland China, also set:

```env
NPM_REGISTRY=https://registry.npmmirror.com
```

### 2) Start

```bash
docker compose up -d --build
```

First boot automatically installs selected agent CLIs (`AGENT=claude` by default) and initializes data directories.

Check logs:

```bash
docker compose logs -f
```

### 3) Access

**Option A: Tailscale (recommended)**

Open:

```text
http://<tailnet-ip>:3006
```

Find tailnet IP:

```bash
docker compose logs | grep 'Tailscale connected'
# or
docker exec -u devbox devbox tailscale ip -4
```

**Option B: Public relay** (default when `TS_AUTHKEY` is empty; can be forced with `HAPI_NO_RELAY=false`)

> Note: If you set `HAPI_NO_RELAY=true`, you must have a working Tailscale connection, otherwise the hub will only listen on `127.0.0.1` and you won’t be able to access it remotely.

    docker compose logs -f

Or open <https://app.hapi.run> and log in with the token from logs.

### 4) First web login

Use the token shown in logs. You can check it later:

```bash
docker exec -u devbox devbox cat /home/devbox/.hapi/settings.json
```

### 5) First-time agent auth (once per agent)

```bash
docker exec -it -u devbox devbox bash
cd /workspace && claude
```

---

## Supported agents and config

Set `AGENT` in `.env` (comma-separated, e.g. `AGENT=claude,codex`).

| Agent | Required variables | One-time auth |
|---|---|---|
| Claude Code | `ANTHROPIC_BASE_URL` + `ANTHROPIC_API_KEY` | Run `claude` once |
| Codex | `OPENAI_API_KEY` or `CODEX_BASE_URL` + `CODEX_API_KEY` | `codex login --with-api-key` (or auto via gateway) |
| OpenCode | `OPENAI_API_KEY` or `OPENCODE_BASE_URL` + `OPENCODE_API_KEY` | Auto / `opencode auth login` |
| Grok | `XAI_API_KEY` or `GROK_BASE_URL` + `GROK_API_KEY` | Auto |
| Kimi Code | `KIMI_API_KEY` | Auto |
| Copilot | GitHub account | `copilot login` |
| Cursor | Cursor account/subscription | `agent login` |
| Antigravity | Google account | `agy` |
| Pi | `PI_BASE_URL` + `PI_API_KEY` | Auto |

---

## Daily usage

- In Web UI: create session, select agent, chat, approve tools, remote takeover.
- CLI (optional):

```bash
docker exec -it -u devbox devbox bash
cd /workspace && hapi
cd /workspace && hapi codex
```

After changing `AGENT`, rebuild with `docker compose up -d --build`.

---

## Data persistence

| Host path | Container path | Content |
|---|---|---|
| `./data` | `/home/devbox` | Agent auth/config, hapi token/data, install cache |
| `./tailscale` | `/var/lib/tailscale` | Tailscale state |
| `./workspace` | `/workspace` | Your code workspace |

---

## Security notes

- Do not commit `.env` (already ignored by `.gitignore`).
- `devbox` has passwordless sudo by default; remove `/etc/sudoers.d/devbox` if you do not need it.
- With Tailscale, traffic stays in your private tailnet.
- Public relay mode still uses encrypted transport.
- Rotate API keys and hapi token (`cliApiToken`) regularly.

---

## Environment variables (reference)

See `.env.example` and the Chinese section below for complete descriptions.

---

## Related links

- HAPI: <https://github.com/tiann/hapi>
- Claude Code devcontainer docs: <https://code.claude.com/docs/en/devcontainer>
- Tailscale Docker docs: <https://tailscale.com/kb/1282/docker>

---

## 中文版

# devbox：手机 / 浏览器远程操作 VPS 上的 AI 编程助手

一个 Docker 镜像，把 **Claude Code、Codex、OpenCode、Grok、Cursor、Kimi、Copilot、Antigravity、Pi** 等 9 个 AI 编程助手装进你的 VPS，让你**在任何地方用手机或浏览器远程操作它们**，全程不需要开放任何公网端口。

- 📱 **手机 / 浏览器即用**：hapi Web UI（可加为手机主屏 PWA），远程聊天、审批工具权限、远程新建会话
- 🔒 **Tailscale 直连（推荐）**：端到端加密的私有隧道，流量不经过任何第三方服务器
- 🧩 **9 种 agent 自由搭配**：镜像里不预装，启动时按需安装，镜像体积小
- 💾 **数据持久化**：认证、配置、代码都落在宿主机目录，重启 / 重装不丢

---

## 快速开始

### 1. 准备配置

```bash
cp .env.example .env
```

编辑 `.env`，**必填**一份 agent 的 API 配置，比如 Claude Code（国内常用中转站）：

```env
ANTHROPIC_BASE_URL=https://你的API网关地址
ANTHROPIC_API_KEY=sk-xxx
```

**推荐**再配一下 Tailscale（手机直连 VPS、不经过任何第三方）：

```env
TS_AUTHKEY=tskey-auth-xxxx        # 在 https://login.tailscale.com/admin/settings/keys 生成
TS_HOSTNAME=devbox-vps
```

> 想用 Codex / OpenCode / Grok 等其他 agent？见[「支持的 agent 与配置」](#支持的-agent-与配置)。
> 国内网络建议再加一行 `NPM_REGISTRY=https://registry.npmmirror.com`，加速 agent 下载安装。

### 2. 启动

```bash
docker compose up -d --build
```

首次启动会自动完成两件事：**安装**你指定的 agent CLI（`AGENT=claude` 默认只装 Claude Code）和**初始化数据目录**——全程无需手动操作。想跳过安装，设 `AGENT=none`。

看启动进度：

```bash
docker compose logs -f
```

### 3. 找到远程入口

**方式一：Tailscale（推荐）**

手机 / 电脑装 [Tailscale App](https://tailscale.com/download)，登录**与 VPS 同一个账号**，然后浏览器打开：

```
http://<容器tailnet-IP>:3006
```

tailnet IP 在哪看：

```bash
docker compose logs | grep 'Tailscale connected'
# 或
docker exec -u devbox devbox tailscale ip -4
```

> 启用 Tailscale 后，也可以直接 `ssh devbox@devbox-vps` 登录容器（Tailscale SSH）；在管理后台为该节点开启 HTTPS 证书后，还能用 `https://devbox-vps.<你的tailnet>.ts.net` 访问。

**方式二：公共中继（没配 `TS_AUTHKEY` 时自动启用）**

```bash
docker compose logs -f     # 首行就是访问 URL + 二维码 + token
```

也可以直接打开 <https://app.hapi.run>，用日志里的 token 登录。

### 4. 登录 Web UI（一次）

首次打开 Web UI 时输入日志里的 **token**。token 会持久化保存，重启不丢；忘了随时查看：

```bash
docker exec -u devbox devbox cat /home/devbox/.hapi/settings.json   # 找 cliApiToken
```

### 5. 首次使用 agent（每个 agent 一次）

agent 首次使用前要认领你的 key 或完成登录。以 Claude Code 为例：

```bash
docker exec -it -u devbox devbox bash
cd /workspace && claude      # 按提示确认使用环境变量中的 key
```

确认一次后凭证会保存下来，之后在手机 / 浏览器上直接可用。其他 agent 的认证方式见下节。

---

## 支持的 agent 与配置

镜像支持 9 种 agent，`.env` 里的 `AGENT` 变量决定装哪些（逗号分隔，如 `AGENT=claude,codex`）。各自的 key 和认证方式：

| Agent | 需要设置的变量 | 认证方式（一次性） |
|---|---|---|
| **Claude Code** | `ANTHROPIC_BASE_URL` + `ANTHROPIC_API_KEY` | 首次 `claude` 确认一次 |
| **Codex** | `OPENAI_API_KEY`，或中转 `CODEX_BASE_URL` + `CODEX_API_KEY` | `codex login --with-api-key`；配网关则自动生效 |
| **OpenCode** | `OPENAI_API_KEY`，或中转 `OPENCODE_BASE_URL` + `OPENCODE_API_KEY` | 自动；或 `opencode auth login` |
| **Grok** | `XAI_API_KEY`（官方），或中转 `GROK_BASE_URL` + `GROK_API_KEY` | 自动 |
| **Kimi Code** | `KIMI_API_KEY` | 自动 |
| **Copilot** | GitHub 账号 | `copilot login` |
| **Cursor** | Cursor 账号 / 订阅 | `agent login` |
| **Antigravity** | Google 账号 | `agy` |
| **Pi** | `PI_BASE_URL` + `PI_API_KEY`（纯第三方，必须自配 provider） | 自动 |

> 登录 / 认证类命令请在 devbox 用户下执行：`docker exec -it -u devbox devbox bash` 后运行。
> Codex / OpenCode / Grok / Pi 支持第三方中转站（网关）：设好 `*_BASE_URL` + `*_API_KEY` 后，启动时自动生成配置，无需手动改文件；手动挂载的配置文件优先级更高（示例见 `examples/` 目录）。

---

## 日常使用

- **手机 / 浏览器**：打开 Web UI（建议"添加到主屏幕"用 PWA），新建会话时选择 agent，聊天、审批权限、远程接管都在这里。
- **命令行**（偶尔用）：
  ```bash
  docker exec -it -u devbox devbox bash
  cd /workspace && hapi            # 默认 Claude Code
  cd /workspace && hapi codex      # 或 hapi grok / hapi opencode ...
  ```
改了 `AGENT` 后，`docker compose up -d --build` 重建生效。

---

## 数据存放（重启 / 重装不丢）

| 宿主机目录 | 容器内路径 | 内容 |
|---|---|---|
| `./data` | `/home/devbox` | 所有 agent 的认证与配置、hapi 数据与 token、agent 安装缓存 |
| `./tailscale` | `/var/lib/tailscale` | Tailscale 登录状态（重启不重新认证） |
| `./workspace` | `/workspace` | 代码工作区（建议用 git 管理） |

---

## 常见问题

**Q: 容器起不来，日志里有 FATAL？**
A: 首次启动会自动初始化数据目录与权限。如果看到「无法创建 /home/devbox 下的配置目录」，多半是用了 `--user 1000` 或 compose 的 `user:` 强制非 root 启动——去掉后重启即可，默认方式无需任何手动操作。

**Q: 没看到访问 URL / 二维码？**
A: 稍等几秒再刷新 `docker compose logs -f`，公共中继首次接入需要时间。确认已按第 3 步操作：配了 `TS_AUTHKEY` 用方式一，没配用方式二。

**Q: 国内下载 agent 慢 / 装不上？**
A: 在 `.env` 里设 `NPM_REGISTRY=https://registry.npmmirror.com` 后重启容器。grok / cursor / kimi / agy 走官方脚本，可能需要代理或手动安装（安装日志在 `/tmp/install-<agent>.log`）。

**Q: Tailscale 没连上？**
A: `docker exec -u devbox devbox cat /tmp/tailscale-up.log` 查看原因；确认 `TS_AUTHKEY` 有效、管理后台已批准节点。

**Q: 想更新某个 agent？**
A: 改 `.env` 里对应版本变量（如 `CLAUDE_VERSION=2.x.x`）后 `docker compose up -d --build`；旧版本需先手动删除（`docker exec -u devbox devbox bash` 后 `rm -rf ~/.local/lib/node_modules/<包名> ~/.local/bin/<命令>`）。

**Q: 怎么让 agent 自己装系统包（apt）？**
A: devbox 用户自带**免密 sudo**——在会话里让 Claude Code 等 agent 装系统依赖时用 `sudo`（如 `sudo apt-get install -y build-essential`），你在手机上审批一下即可，agent 能自己完成安装。语言级依赖（npm / pip / venv 等）不需要 sudo，直接装。

注意：装进容器可写层，`docker compose down` 或重建后会丢失；需要长期保留的依赖，建议写进 Dockerfile 扩展镜像（`FROM devbox:latest` 后 `RUN apt-get install -y ...`）。

---

## 安全提示

- 不要把 `.env` 提交到 git（已在 `.gitignore` 中忽略）；密钥只存在于运行时环境变量和卷中
- devbox 用户配置了免密 sudo（等同 root 权限，便于 agent 自行安装系统依赖）；不需要的话可删除镜像里的 `/etc/sudoers.d/devbox` 或改用更受限的 sudoers 规则
- 走 Tailscale 时，手机与 VPS 之间是端到端加密的私有隧道，**不经过任何第三方**；公共中继模式的流量会经过 hapi 官方中继（同样加密）
- VPS 防火墙不需要放行 3006 端口
- 定期轮换 API key 与 hapi 访问 token（`/home/devbox/.hapi/settings.json` 中的 `cliApiToken`）

---

## 附录：环境变量参考

所有变量在 `.env` 中设置：

| 类别 | 变量 | 默认 | 说明 |
|------|------|------|------|
| **Agent 安装** | `AGENT` | `claude` | 启动时安装哪些 CLI（逗号分隔） |
| | `NPM_REGISTRY` | `https://registry.npmjs.org` | npm 镜像，国内建议 npmmirror |
| | `CLAUDE_VERSION` / `CODEX_VERSION` / `OPENCODE_VERSION` / `COPILOT_VERSION` / `PI_VERSION` | `latest` | 版本锁定 |
| **Claude Code** | `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` | API 端点 / 网关 |
| | `ANTHROPIC_API_KEY` | - | 密钥（x-api-key） |
| | `ANTHROPIC_AUTH_TOKEN` | - | 备选 Bearer token |
| **Codex** | `OPENAI_API_KEY` | - | 官方 key（一次性登录） |
| | `CODEX_BASE_URL` / `CODEX_API_KEY` / `CODEX_MODEL` | - | 第三方网关自动生成配置 |
| **OpenCode** | `OPENAI_API_KEY` | - | 标准 provider env |
| | `OPENCODE_BASE_URL` / `OPENCODE_API_KEY` / `OPENCODE_MODEL` | - | 第三方网关自动生成配置 |
| **Grok** | `XAI_API_KEY` | - | 官方 xAI 端点 |
| | `GROK_BASE_URL` / `GROK_API_KEY` / `GROK_MODEL` | - | 第三方中转自动生成配置 |
| | `GROK_API_BACKEND` | `chat_completions` | `chat_completions` / `responses` / `messages` |
| **Kimi** | `KIMI_API_KEY` | - | Moonshot 官方端点 |
| **Pi** | `PI_BASE_URL` / `PI_API_KEY` / `PI_MODEL` | - | 第三方 provider（必须配置） |
| | `PI_API` | `openai-completions` | `openai-completions` / `openai-responses` / `anthropic-messages` / `google-generative-ai` |
| **HAPI** | `HAPI_NO_RELAY` | 自动 | 留空=自动（有 Tailscale 走私网、无则公共中继）；`true` / `false` 强制指定 |
| | `HAPI_LISTEN_HOST` / `HAPI_LISTEN_PORT` | `127.0.0.1` / `3006` | hub 监听地址 / 端口 |
| | `HAPI_RELAY_FORCE_TCP` | `false` | 公共中继 UDP 不通时强制 TCP |
| | `TELEGRAM_BOT_TOKEN` / `SERVERCHAN_SENDKEY` | - | 可选：权限审批推送通知 |
| **Tailscale** | `TS_AUTHKEY` | 空 | 留空=不启用 Tailscale |
| | `TS_HOSTNAME` | `devbox-vps` | tailnet 节点名 |
| | `TS_SSH` | `true` | `true`=启用 Tailscale SSH / `false`=关闭 |
| | `TS_EXTRA_ARGS` | - | 额外 `tailscale up` 参数 |

> 高级用法（如 `CORS_ORIGINS`、`HAPI_PUBLIC_URL`）参考 [hapi 官方文档](https://github.com/tiann/hapi/blob/main/docs/guide/installation.md)。

---

## 相关链接

- HAPI 仓库：<https://github.com/tiann/hapi>
- Claude Code 开发容器文档：<https://code.claude.com/docs/en/devcontainer>
- Tailscale Docker 文档：<https://tailscale.com/kb/1282/docker>
