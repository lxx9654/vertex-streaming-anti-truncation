# Vertex Streaming Anti-Truncation —— 容器化部署（Zeabur / Docker 均可用）
#
# 基于上游 0.8.0+ 官方 Dockerfile，保留三处 Zeabur 适配：
#   1) ENTRYPOINT 走 docker-entrypoint.sh（解码 VERTEX_SERVICE_ACCOUNT_B64 → 持久卷）
#   2) 上游 .dockerignore 用白名单，需显式 COPY scripts/（健康检查等脚本）
#   3) GATEWAY_STATE_DIR 指向持久卷子目录，与 keys/ 分开
FROM node:24-bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/lxx9654/vertex-streaming-anti-truncation" \
      org.opencontainers.image.title="Vertex Streaming Anti-Truncation (Zeabur fork)" \
      org.opencontainers.image.description="Vertex Gemini gateway with a web console and streaming text restoration" \
      org.opencontainers.image.licenses="MIT"

ENV NODE_ENV=production \
    LISTEN_HOST=0.0.0.0 \
    GUI_PORT=4780 \
    PORT=4781 \
    GATEWAY_STATE_DIR=/data/state \
    UPSTREAM_TIMEOUT_MS=600000
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY bin/ ./bin/
COPY src/ ./src/
COPY public/ ./public/
COPY scripts/ ./scripts/
COPY assets/ ./assets/
COPY LICENSE NOTICE.md NOTICE.zh-CN.md ./
COPY LICENSES/ ./LICENSES/
COPY docker-entrypoint.sh /app/docker-entrypoint.sh

RUN chmod +x /app/docker-entrypoint.sh \
 && mkdir -p /data/state && chown -R node:node /data /app
USER node
EXPOSE 4780 4781
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["node", "bin/healthcheck.mjs"]

ENTRYPOINT ["/app/docker-entrypoint.sh"]
# 带 GUI 启动：控制台会读取已保存配置并自动拉起网关；首次用它配置模型
CMD ["node", "bin/gui.mjs"]
