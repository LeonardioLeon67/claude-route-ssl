#!/bin/bash

# 自动清理过期账户的脚本
SCRIPT_DIR="/root/claude-route/claude-route-ssl"
LOG_FILE="$SCRIPT_DIR/logs/cleanup.log"

# 确保日志目录存在
mkdir -p "$SCRIPT_DIR/logs"

# 记录日志的函数
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_message "开始清理过期账户..."

# 执行清理
cd "$SCRIPT_DIR"
lua account_manager.lua cleanup >> "$LOG_FILE" 2>&1

log_message "清理任务完成"

# 可选：重启nginx以确保配置生效
# systemctl reload nginx