# devbox: Remote AI coding assistants on your VPS (mobile/browser)

> English is the default. 中文请见下方「中文版」。

A Docker image that lets you run **9 AI coding assistants** on your VPS (**Claude Code, Codex, OpenCode, Grok, Cursor, Kimi, Copilot, Antigravity, Pi**) and operate them remotely from your **phone or browser** without opening public ports.

- 📱 **Mobile/browser ready**: hapi Web UI (PWA-capable), remote chat, tool-approval, remote session creation
- 🔀 **Selectable control layer**: `CONTROL=hapi` (default) or `CONTROL=mindfs` — HAPI supports all 9 agents, MindFS supports 7
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

> Run login/auth commands as the `devbox` user: `docker exec -it -u devbox devbox bash`, then run them.
> Codex / OpenCode / Grok / Pi support third-party gateways: set `*_BASE_URL` + `*_API_KEY` and the config is generated at startup, no manual file edits; a manually mounted config file takes precedence (examples in `examples/`).

---

## Control layer: HAPI or MindFS

The image ships two interchangeable control layers. Pick one with `CONTROL` in `.env` — they are mutually exclusive, only one runs:

| | `CONTROL=hapi` (default) | `CONTROL=mindfs` |
|---|---|---|
| Service | HAPI hub + runner | MindFS single binary |
| Port | 3006 | 7331 |
| Agents | all 9 | 7 (Claude, Codex, OpenCode, Grok, Cursor, Kimi, Copilot) |
| Remote access | Tailscale, or HAPI public relay (fully automatic) | Tailscale, or a9gent relay (one-time manual pairing) |
| Extras | Telegram Mini App, seamless local↔remote handoff | Task board, file browser, plugins, session import/sync |

Switch by editing `.env` and recreating the container (no image rebuild needed):

```bash
# .env
CONTROL=mindfs

docker compose up -d --force-recreate
```

**MindFS notes**

- Via Tailscale it works fully automatically, same as HAPI. Without Tailscale, MindFS falls back to the a9gent.com relay, which needs a **one-time manual pairing**: open the local UI (`http://127.0.0.1:7331` on the host, or via Tailscale), click the bind button in the bottom-left corner, and log in to a9gent.com. Unlike HAPI's relay, this cannot be fully automated.
- MindFS only drives **7 agents**. `Pi` and `Antigravity` are not supported even if installed via `AGENT=`.
- If you use a third-party gateway (custom `*_BASE_URL`), verify it once under MindFS: Claude/Codex are driven through native SDK paths rather than plain CLI wrapping.
- Related variables: `MINDFS_LISTEN_PORT` (7331), `MINDFS_NO_RELAYER` (empty = auto), `MINDFS_E2EE` (false).

---

## Daily usage

- In Web UI: create session, select agent, chat, approve tools, remote takeover.
- CLI (optional):

```bash
docker exec -it -u devbox devbox bash
cd /workspace && hapi
cd /workspace && hapi codex
```

After changing `AGENT`, recreate the container so the updated `.env` is applied (no image rebuild needed):

    docker compose up -d --force-recreate
---

## Data persistence

| Host path | Container path | Content |
|---|---|---|
| `./data` | `/home/devbox` | Agent auth/config, HAPI token/data, MindFS config (`~/.config/mindfs`, `~/.local/share/mindfs`), install cache |
| `./tailscale` | `/var/lib/tailscale` | Tailscale state |
| `./workspace` | `/workspace` | Your code workspace (MindFS session data lives in `.mindfs/`) |

---

## FAQ

**Q: The container won't start, or there's a FATAL in the logs?**
A: The first boot initializes the data dirs and their permissions automatically. If you see "cannot create the config dirs under /home/devbox", you are most likely forcing a non-root start with `--user 1000` or compose's `user:` — remove it and restart; the default path needs no manual steps.

**Q: I don't see the access URL / QR code?**
A: Wait a few seconds and refresh `docker compose logs -f`; the public relay takes a moment on first connect. Make sure you followed step 3: with `TS_AUTHKEY` set use option A, otherwise option B.

**Q: Downloads are slow / agents fail to install in mainland China?**
A: Set `NPM_REGISTRY=https://registry.npmmirror.com` in `.env` and restart the container. grok / cursor / kimi / agy use official install scripts and may need a proxy or manual install (logs: `/tmp/install-<agent>.log`).

**Q: Tailscale isn't connecting?**
A: Run `docker exec -u devbox devbox cat /tmp/tailscale-up.log` to see why; verify `TS_AUTHKEY` is valid and the node is approved in the admin console.

**Q: How do I update an agent?**
A: Change the matching version variable in `.env` (e.g. `CLAUDE_VERSION=2.x.x`) and run `docker compose up -d --build`; to change versions you must remove the old install first (`docker exec -u devbox devbox bash` then `rm -rf ~/.local/lib/node_modules/<pkg> ~/.local/bin/<cmd>`).

**Q: How do I let an agent install OS packages (apt)?**
A: The `devbox` user has **passwordless sudo** — ask Claude Code etc. to use `sudo` when installing system dependencies (e.g. `sudo apt-get install -y build-essential`), approve it on your phone, and the agent completes the install itself. Language-level dependencies (npm / pip / venv) need no sudo; install them directly.

Note: packages land in the container's writable layer and are lost on `docker compose down` or a rebuild. For long-lived dependencies, bake them into a derived image (`FROM devbox:latest` then `RUN apt-get install -y ...`).

---

## Security notes

- Do not commit `.env` (already ignored by `.gitignore`); secrets live only in the runtime environment and the volumes.
- `devbox` has passwordless sudo by default (equivalent to root, so agents can install system deps); remove `/etc/sudoers.d/devbox` or use a stricter sudoers rule if you do not need it.
- With Tailscale, phone↔VPS traffic stays in an end-to-end-encrypted private tunnel, **with no third party involved**; public relay mode still uses encrypted transport.
- No firewall port needs to be opened on the VPS (3006/7331 are not published by default).
- Rotate API keys and the hapi token (`cliApiToken` in `/home/devbox/.hapi/settings.json`) regularly.

---

## Environment variables (reference)

All variables are set in `.env`:

| Category | Variable | Default | Description |
|---|---|---|---|
| **Control layer** | `CONTROL` | `hapi` | `hapi` or `mindfs` (mutually exclusive) |
| **Agent install** | `AGENT` | `claude` | Which CLIs to install at startup (comma-separated) |
| | `NPM_REGISTRY` | `https://registry.npmjs.org` | npm registry; npmmirror recommended in mainland China |
| | `CLAUDE_VERSION` / `CODEX_VERSION` / `OPENCODE_VERSION` / `COPILOT_VERSION` / `PI_VERSION` | `latest` | Version pinning |
| **Claude Code** | `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` | API endpoint / gateway |
| | `ANTHROPIC_API_KEY` | - | Key (x-api-key) |
| | `ANTHROPIC_AUTH_TOKEN` | - | Alternative Bearer token |
| **Codex** | `OPENAI_API_KEY` | - | Official key (one-time login) |
| | `CODEX_BASE_URL` / `CODEX_API_KEY` / `CODEX_MODEL` | - | Third-party gateway; config generated automatically |
| **OpenCode** | `OPENAI_API_KEY` | - | Standard provider env |
| | `OPENCODE_BASE_URL` / `OPENCODE_API_KEY` / `OPENCODE_MODEL` | - | Third-party gateway; config generated automatically |
| **Grok** | `XAI_API_KEY` | - | Official xAI endpoint |
| | `GROK_BASE_URL` / `GROK_API_KEY` / `GROK_MODEL` | - | Third-party relay; config generated automatically |
| | `GROK_API_BACKEND` | `chat_completions` | `chat_completions` / `responses` / `messages` |
| **Kimi** | `KIMI_API_KEY` | - | Moonshot official endpoint |
| **Pi** | `PI_BASE_URL` / `PI_API_KEY` / `PI_MODEL` | - | Third-party provider (required) |
| | `PI_API` | `openai-completions` | `openai-completions` / `openai-responses` / `anthropic-messages` / `google-generative-ai` |
| **HAPI** | `HAPI_NO_RELAY` | auto | Empty = auto (tailnet if Tailscale is up, else public relay); `true` / `false` to force |
| | `HAPI_LISTEN_HOST` / `HAPI_LISTEN_PORT` | `127.0.0.1` / `3006` | Hub listen address / port |
| | `HAPI_RELAY_FORCE_TCP` | `false` | Force TCP when the relay's UDP is blocked |
| | `TELEGRAM_BOT_TOKEN` / `SERVERCHAN_SENDKEY` | - | Optional: permission-approval push notifications |
| **MindFS** | `MINDFS_LISTEN_PORT` | `7331` | Service port |
| | `MINDFS_NO_RELAYER` | auto | Empty = auto (tailnet if Tailscale is up, else a9gent relay); `true` / `false` to force |
| | `MINDFS_E2EE` | `false` | `true` = end-to-end encryption (pairing secret printed on first start) |
| **Tailscale** | `TS_AUTHKEY` | empty | Empty = Tailscale disabled |
| | `TS_HOSTNAME` | `devbox-vps` | tailnet node name |
| | `TS_SSH` | `true` | `true` = enable Tailscale SSH / `false` = disable |
| | `TS_EXTRA_ARGS` | - | Extra `tailscale up` args |

> Advanced options (e.g. `CORS_ORIGINS`, `HAPI_PUBLIC_URL`) are documented in the [HAPI docs](https://github.com/tiann/hapi/blob/main/docs/guide/installation.md).

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
- 🔀 **控制层可选**：`CONTROL=hapi`（默认）或 `CONTROL=mindfs`；HAPI 支持全部 9 种 agent，MindFS 支持 7 种
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

## 控制层：HAPI 或 MindFS

镜像内置两个可互换的控制层，用 `.env` 里的 `CONTROL` 二选一（互斥，同时只运行一个）：

| | `CONTROL=hapi`（默认） | `CONTROL=mindfs` |
|---|---|---|
| 服务 | HAPI hub + runner | MindFS 单二进制 |
| 端口 | 3006 | 7331 |
| agent | 全部 9 种 | 7 种（Claude / Codex / OpenCode / Grok / Cursor / Kimi / Copilot） |
| 远程接入 | Tailscale，或 HAPI 公共中继（全自动） | Tailscale，或 a9gent 中继（首次需手动配对） |
| 额外能力 | Telegram Mini App、本地↔手机无缝接力 | 任务看板、文件浏览、插件、会话导入/同步 |

改 `.env` 后重建容器即可（无需重新 build）：

```bash
# .env
CONTROL=mindfs

docker compose up -d --force-recreate
```

**MindFS 提示**

- 走 Tailscale 时全自动，与 HAPI 一致。没有 Tailscale 时会回落到 a9gent.com 中继，**首次需手动配对一次**：打开本地 UI（宿主 `http://127.0.0.1:7331`，或经 Tailscale），点左下角绑定按钮登录 a9gent.com 完成绑定。这点和 HAPI 的自动中继不同，无法完全无人值守。
- MindFS 只驱动 **7 种 agent**；`Pi` 和 `Antigravity` 即便用 `AGENT=` 装了也不会出现。
- 若使用第三方网关（自配 `*_BASE_URL`），请在 MindFS 下实测一次：Claude / Codex 走的是原生 SDK 路径，而非普通 CLI 包装。
- 相关变量：`MINDFS_LISTEN_PORT`（7331）、`MINDFS_NO_RELAYER`（留空=自动）、`MINDFS_E2EE`（false）。

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
| `./data` | `/home/devbox` | 所有 agent 的认证与配置、HAPI 数据与 token、MindFS 配置（`~/.config/mindfs`、`~/.local/share/mindfs`）、agent 安装缓存 |
| `./tailscale` | `/var/lib/tailscale` | Tailscale 登录状态（重启不重新认证） |
| `./workspace` | `/workspace` | 代码工作区（建议用 git 管理；MindFS 会话数据在 `.mindfs/`） |

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
| **控制层** | `CONTROL` | `hapi` | `hapi` 或 `mindfs`（二选一，互斥） |
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
| **MindFS** | `MINDFS_LISTEN_PORT` | `7331` | 服务端口 |
| | `MINDFS_NO_RELAYER` | 自动 | 留空=自动（有 Tailscale 走私网、无则允许 a9gent 中继）；`true` / `false` 强制指定 |
| | `MINDFS_E2EE` | `false` | `true`=启用端到端加密（首次启动打印配对密钥） |
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
