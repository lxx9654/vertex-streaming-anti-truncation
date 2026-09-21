# Zeabur 部署说明（直连版：不经过 NewAPI）

**架构**：SillyTavern（宿舍电脑 / 公司电脑）→ `https://<你的域名>/v1` → 本网关 → Vertex AI
NewAPI 不参与这条链路；原 NewAPI 和 Vertex 渠道保持原样不动。

**两个端口都要保留、都要能从公网访问**：

| 端口 | 用途 | 谁访问 |
|---|---|---|
| 4781 | API（酒馆连这里） | SillyTavern |
| 4780 | 控制台（配模型、看日志） | 你 |

---

## 一、上游项目的 3 处改动（已在 `zeabur-deploy` 分支）

| 文件 | 改动 | 原因 |
|---|---|---|
| `bin/start.mjs` | `server.listen(port, process.env.HOST \|\| "127.0.0.1")` | 原来写死回环，容器外访问不到 |
| `src/console-server.mjs` | `server.listen(port, process.env.GUI_HOST \|\| "127.0.0.1")` | 同上（控制台端口） |
| `package.json` | `gateway` 脚本改用 `--env-file-if-exists=.env` | 容器里没有 `.env` 不再启动失败 |

另有 `Dockerfile`（node:22-slim，内置 `HOST=0.0.0.0` / `GUI_HOST=0.0.0.0`）、`docker-entrypoint.sh`（自动把 base64 服务账号解码落盘）、`.dockerignore`。

## 二、Zeabur 建服务

1. 新建服务 → 从 GitHub 部署 → `lxx9654/vertex-streaming-anti-truncation` → **分支 `zeabur-deploy`**
2. 环境变量（见下节）
3. **持久卷挂 `/data`**（必做，否则重新部署配置全丢）
4. **端口设置**：4781 和 4780 都添加并**开启公网访问**，各绑一个域名（如 `vertex-api.你的域名` 和 `vertex-gui.你的域名`；用 Zeabur 默认提供的域名也行）
5. 部署后看日志，出现下面两行即成功：

```
[entrypoint] service-account JSON written to /data/keys/sa.json
{"event":"listening","host":"0.0.0.0","endpoint":"http://0.0.0.0:4781/v1",...}
Vertex Gateway console: http://0.0.0.0:4780/
```

## 三、环境变量（服务账号模式，整段照抄，只有两项要你填）

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
VERTEX_SERVICE_ACCOUNT_B64=<服务账号JSON的base64>      ← 改这个
```

`VERTEX_PROJECT_ID` 要与服务账号 JSON 里的 `project_id` 一致。

**生成 base64**（本机 PowerShell，改路径，跑完自动进剪贴板）：

```powershell
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\你的路径\service-account.json"))
Set-Clipboard $b64
```

容器每次启动会把 base64 解码写到 `/data/keys/sa.json`（权限 600），并把该变量从进程环境抹掉；卷还在时文件会留下。

> 换网关密钥：`node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"`

## 四、首次配置（只用一次，在控制台里做）

1. 浏览器打开 `https://<4780绑定的域名>`
2. 用 `GATEWAY_API_KEY` 登录（首次没有保存配置时会给出带设置密钥的链接，打开即进设置）
3. 连接配置 → 确认项目 ID / 服务账号（可导入覆盖）→ 服务等级 standard → 保存
4. 模型与版本 → **拉取 Model List** → 勾选需要的 Gemini → 添加三个版本：
   - `<model>` 正常
   - `<model>-antitruncation-nonstream` 非流式抗截断
   - `<model>-antitruncation-stream` **流式抗截断 ← 酒馆主要用这个**
5. 保存全部配置 → 总览页确认网关 running

> 不进控制台也能跑：纯环境变量模式只暴露一个默认模型 `gemini-3.7-flash-antitruncation`。要多模型必须走这一步。

## 五、SillyTavern 直连（两端电脑都这么配）

聊天补全 → 连接选 **自定义（兼容 OpenAI）**：

| 设置 | 值 |
|---|---|
| API URL | `https://<4781绑定的域名>/v1` |
| API Key | `GATEWAY_API_KEY` 的值 |
| 模型 | 刷新列表后选 `<model>-antitruncation-stream` |
| 流式传输 | 开启 |

预设里如果已有同类抗截断脚本，只保留一处包装，别双重包装。

## 六、验证

```bash
# 健康（无需鉴权）
curl https://<api域名>/healthz
# 模型列表
curl -H "Authorization: Bearer <GATEWAY_API_KEY>" https://<api域名>/v1/models
# 真实短请求（会计费，最多 512 tokens）
curl -N -H "Authorization: Bearer <GATEWAY_API_KEY>" -H "Content-Type: application/json" \
  -d '{"model":"<model>-antitruncation-stream","stream":true,"messages":[{"role":"user","content":"ping"}]}' \
  https://<api域名>/v1/chat/completions
```

成功的抗截断流式请求，控制台日志应有：

```json
{"antiTruncation":{"transport":"tool-transport-native-streaming","restored":true,"finishReason":"stop","streamDone":true}}
```

## 七、公网暴露的安全注意（这版两个端口都在公网上，务必看）

1. `GATEWAY_API_KEY` 就是 API 和控制台的共同口令——用足 32 字节随机值，别复用别的地方的密码
2. 控制台里存着服务账号私钥，**域名别外传**；不需要时可在 Zeabur 把 4780 的公网关掉，改用 `ssh -L 4780:127.0.0.1:4780` 进去配
3. 服务账号 JSON 以 base64 存在 Zeabur 环境变量里；确认卷里 `/data/keys/sa.json` 落稳后，可以删掉 `VERTEX_SERVICE_ACCOUNT_B64`（文件会留在卷里继续用）
4. Zeabur 面板对 4781/4780 的访问日志定期看一眼，异常请求集中在 `/admin/events`（只保留最近 200 条）

## 八、已知限制

- 只支持 **Gemini on Vertex**；Claude on Vertex、embedding 管不了（这些继续走 NewAPI 原渠道）
- 抗截断只在纯文本流式 + Vertex 原生 `partialArgs`（Preview）可用时生效；带 tools / JSON schema 的请求会跳过包装
- 不支持远程图片 URL、旧式 `functions`、`parallel_tool_calls`、严格 schema、logprobs，撞上返回 `400 unsupported_native_fields`
- 无多账号调度、无重试切档位；流中断会报错，不自动续写
- 上游是实验版（v0.3.0），跟进上游更新时需要重新应用这三处改动
