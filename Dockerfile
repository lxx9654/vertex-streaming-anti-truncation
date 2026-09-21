# Vertex Streaming Anti-Truncation —— 容器化部署（Zeabur / Docker 均可用）
# 上游项目默认只监听 127.0.0.1，这里通过 HOST / GUI_HOST 放开到容器外。
FROM node:22-slim

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    GUI_HOST=0.0.0.0 \
    PORT=4781 \
    GATEWAY_PORT=4781 \
    GUI_PORT=4780 \
    GATEWAY_STATE_DIR=/data/state \
    UPSTREAM_TIMEOUT_MS=600000

WORKDIR /app

# 无第三方运行时依赖，装依赖只是走一遍 npm ci 的完整性检查
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

COPY bin/ ./bin/
COPY src/ ./src/
COPY public/ ./public/
COPY scripts/ ./scripts/
COPY docker-entrypoint.sh /app/docker-entrypoint.sh

# 持久化目录：settings.json（GUI 保存的模型/凭据）放这里
RUN chmod +x /app/docker-entrypoint.sh \
 && mkdir -p /data/state && chown -R node:node /data /app
USER node

EXPOSE 4781 4780

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||4781)+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/app/docker-entrypoint.sh"]
# 带 GUI 启动：控制台会读取已保存配置并自动拉起网关；首次用它配置模型
CMD ["npm", "start"]
