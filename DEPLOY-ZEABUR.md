# Zeabur 部署说明（服务器版改造）

上游项目定位是「本机 GUI 网关」，为了让它在 Zeabur / Docker 里能跑，本 fork 做了 3 处最小改动：

| 文件 | 改动 | 原因 |
|---|---|---|
| `bin/start.mjs` | `server.listen(port, process.env.HOST \|\| "127.0.0.1")` | 原来写死回环，容器外访问不到 |
| `src/console-server.mjs` | `server.listen(port, process.env.GUI_HOST \|\| "127.0.0.1")` | 同上（GUI 端口） |
| `package.json` | `gateway` 脚本改用 `--env-file-if-exists=.env` | 原来 `--env-file=.env`，容器里没有 `.env` 会直接启动失败 |

另外新增：`Dockerfile`（node:22-slim，默认 `HOST=0.0.0.0`、`GUI_HOST=0.0.0.0`）、`.dockerignore`。

---

## 一、Zeabur 新建服务

**方式 A：从 GitHub 部署（推荐，改代码后自动重新构建）**
新建服务 → 从 GitHub 部署 → 选你的 fork → 分支 `codex/initial-release` → 其余自动识别（有 Dockerfile 会走 Docker 构建）

**方式 B：Docker 部署**
新建服务 → Docker → 镜像源选「Git 仓库」或本地构建均可

构建完确认日志里出现：
```
{"event":"listening","host":"0.0.0.0","endpoint":"http://0.0.0.0:4781/v1",...}
```

## 二、服务账号模式：一屏抄完的环境变量（推荐方案）

```
HOST=0.0.0.0
GUI_HOST=0.0.0.0
PORT=4781
GUI_PORT=4780
GATEWAY_STATE_DIR=/data/state
UPSTREAM_TIMEOUT_MS=600000
ANTI_TRUNCATION=true
VERTEX_SERVICE_TIER=standard
VERTEX_LOCATION=global
VERTEX_PROJECT_ID=你的GCP项目ID
GOOGLE_APPLICATION_CREDENTIALS=/data/keys/sa.json
GATEWAY_API_KEY=18b3a4017dc4edf49023e307fd687b5f9e6bf1e368bebfdeff0ce74365388875
```

### 服务账号 JSON 怎么进容器（两种方式，选一个）

**方式 1：base64 塞进环境变量（推荐，不用传文件）**

在你电脑上用 PowerShell 把 JSON 转成一行 base64（自动进剪贴板）：

```powershell
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\你的路径\service-account.json"))
Set-Clipboard $b64
```

然后在 Zeabur 加一条环境变量：

```
VERTEX_SERVICE_ACCOUNT_B64=<粘贴那一长串>
```

容器启动时 `docker-entrypoint.sh` 会自动解码写到 `/data/keys/sa.json`（权限 600），并把该变量从进程环境里抹掉。

> 卷还在的话文件会留下，之后即使删掉这个环境变量也能跑；换 JSON 时重新部署即可覆盖。

**方式 2：直接传文件到持久卷**

```bash
scp -P <端口> C:/你的路径/service-account.json root@<VPS>:/tmp/sa.json
# 再 SSH 进 VPS，找到卷对应的 PVC 目录后：
mkdir -p <卷路径>/keys && mv /tmp/sa.json <卷路径>/keys/sa.json && chmod 600 <卷路径>/keys/sa.json
```

卷路径一般在 `/var/lib/rancher/k3s/storage/pvc-*<服务名>*`，可用
`find /var/lib/rancher/k3s/storage -maxdepth 2 -iname "*vertex*"` 找。

---

## 二·补、环境变量（通用说明，含其他鉴权方式）

```
HOST=0.0.0.0
GUI_HOST=0.0.0.0
PORT=4781
GUI_PORT=4780
GATEWAY_STATE_DIR=/data/state
UPSTREAM_TIMEOUT_MS=600000
ANTI_TRUNCATION=true
VERTEX_SERVICE_TIER=standard
VERTEX_LOCATION=global

# ⚠️ 改成你自己的（下面这串是现成的，直接用也行）
GATEWAY_API_KEY=18b3a4017dc4edf49023e307fd687b5f9e6bf1e368bebfdeff0ce74365388875

# ⚠️ 三选一，只能填一个
VERTEX_PROJECT_ID=你的GCP项目ID          # 服务账号模式时必填
GOOGLE_APPLICATION_CREDENTIALS=/data/keys/sa.json
# VERTEX_API_KEY=xxxxx                    # Express 快速模式（不用挂文件，但拉不了模型列表）
# VERTEX_ACCESS_TOKEN=xxxxx               # 短期 OAuth token（约 1 小时过期，不适合常驻）
```

> 想换自己的网关密钥：本地跑 `node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"`

## 三、持久化卷（必做，否则每次重新部署配置全丢）

| 挂载路径 | 存什么 |
|---|---|
| `/data/state` | GUI 保存的 `settings.json`（模型版本、凭据） |
| `/data/keys` | 服务账号 JSON（仅服务账号模式需要） |

Zeabur：服务 → 存储/卷 → 新增卷 → 挂载到 `/data`。
首次把服务账号 JSON 传上去：`docker cp` 或在容器里 `mkdir -p /data/keys` 后粘进去；**别放仓库里**。

## 四、端口与公网暴露

| 端口 | 用途 | 建议 |
|---|---|---|
| 4781 | API（NewAPI 接它） | **不公开**，用 Zeabur 内网服务名互访 |
| 4780 | GUI 控制台 | **绝对不要公开**，需要时 SSH 端口转发 |

GUI 有设置密钥登录，但仍不建议挂在公网：里面有你的服务账号私钥。

## 五、首次配置（只用做一次）

1. SSH 转发 GUI：`ssh -L 4780:127.0.0.1:4780 <你的VPS>`，浏览器开 `http://127.0.0.1:4780`
2. 连接配置 → 填项目 ID / 导入服务账号 → 服务等级 standard → 保存
3. 模型与版本 → 拉取 Model List → 勾选需要的 Gemini → 添加三个版本：
   - `<model>` 正常
   - `<model>-antitruncation-nonstream` 非流式抗截断
   - `<model>-antitruncation-stream` 流式抗截断 ← **SillyTavern 主要用这个**
4. 保存全部配置 → 总览页确认网关 running

> 不配 GUI 也能跑：纯环境变量模式下只暴露一个默认模型 `gemini-3.7-flash-antitruncation`。要多模型必须走 GUI + 持久卷。

## 六、NewAPI 接入（取代 Vertex 渠道的正确姿势）

不是删掉原渠道，是**新增一条 OpenAI 兼容渠道，只让 Gemini 流量绕道**：

| 字段 | 值 |
|---|---|
| 类型 | OpenAI（自定义 / OpenAI 兼容） |
| Base URL | `http://<网关服务名>:4781/v1`（Zeabur 同项目内网直连） |
| 密钥 | `GATEWAY_API_KEY` 的值 |
| 模型 | 手动填：`<model>`、`<model>-antitruncation-nonstream`、`<model>-antitruncation-stream` |

原 Vertex 渠道保留给 Claude on Vertex / embedding 等它管不了的模型。

## 七、验证

```bash
# 容器内健康检查（不需要鉴权）
curl http://127.0.0.1:4781/healthz

# 模型列表
curl -H "Authorization: Bearer $GATEWAY_API_KEY" http://127.0.0.1:4781/v1/models

# 一次真实短请求（会产生计费，最多 512 tokens）
curl -N -H "Authorization: Bearer $GATEWAY_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"gemini-3.7-flash-antitruncation-stream","stream":true,"messages":[{"role":"user","content":"ping"}]}' \
  http://127.0.0.1:4781/v1/chat/completions
```

成功的抗截断流式请求，日志里应有：
```json
{"antiTruncation":{"transport":"tool-transport-native-streaming","restored":true,"finishReason":"stop","streamDone":true}}
```

## 八、已知限制（部署前看清楚）

- 只支持 **Gemini on Vertex**；Claude on Vertex、embedding 管不了
- 抗截断只在纯文本流式 + Vertex 原生 `partialArgs`（Preview）可用时生效；带 tools / JSON schema / 严格参数的请求会跳过包装
- 不支持远程图片 URL、旧式 `functions`、`parallel_tool_calls`、严格 schema、logprobs，撞上返回 `400 unsupported_native_fields`
- 无多账号调度、无重试切档位——这部分继续交给 NewAPI
- 服务账号 JSON 是明文存卷里的，卷权限收好
- 上游是实验版（v0.3.0），跟进上游更新时要重新应用这三处改动
