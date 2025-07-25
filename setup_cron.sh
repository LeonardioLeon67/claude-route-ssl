#!/bin/bash

# 设置定时任务的脚本

echo "设置定时清理过期账户的cron任务..."

# 添加到crontab，每天中国时间凌晨3点执行清理
(crontab -l 2>/dev/null; echo "0 3 * * * TZ=Asia/Shanghai /root/claude-route/claude-route-ssl/cleanup_expired.sh") | crontab -

echo "定时任务已设置，每天中国时间凌晨3点自动清理过期账户"
echo "查看当前crontab:"
crontab -l