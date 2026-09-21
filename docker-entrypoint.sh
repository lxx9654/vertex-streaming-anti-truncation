#!/bin/sh
# 容器启动前置脚本：
# 1) 若设置了 VERTEX_SERVICE_ACCOUNT_B64，把它解码成服务账号 JSON 文件
#    （省去手动往持久卷里传文件的麻烦）
# 2) 其余情况原样执行 CMD
set -e

if [ -n "${VERTEX_SERVICE_ACCOUNT_B64:-}" ]; then
  target="${GOOGLE_APPLICATION_CREDENTIALS:-/data/keys/sa.json}"
  mkdir -p "$(dirname "$target")"
  printf '%s' "$VERTEX_SERVICE_ACCOUNT_B64" | base64 -d > "$target"
  chmod 600 "$target"
  echo "[entrypoint] service-account JSON written to $target"
  unset VERTEX_SERVICE_ACCOUNT_B64
fi

exec "$@"
