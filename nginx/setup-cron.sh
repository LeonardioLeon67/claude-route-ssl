#!/bin/bash

# 设置证书自动续签的cron任务（使用用户crontab）
RENEW_SCRIPT="/home/leon/claude-route-ssl/claude-route-ssl/nginx/renew-cert.sh"
LOG_FILE="/home/leon/claude-route-ssl/claude-route-ssl/nginx/ssl/renew.log"
CRON_ENTRY="30 2,14 * * * $RENEW_SCRIPT >> $LOG_FILE 2>&1"

# 检查是否已存在该cron任务
if crontab -l 2>/dev/null | grep -q "$RENEW_SCRIPT"; then
    echo "⚠️  Cron任务已存在，跳过添加"
else
    # 添加到用户crontab
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    echo "✅ Cron任务已添加到用户crontab"
fi

echo ""
echo "📋 当前cron任务配置："
echo "- 执行时间：每天凌晨2:30和下午2:30"
echo "- 续签脚本：$RENEW_SCRIPT"
echo "- 日志文件：$LOG_FILE"
echo ""
echo "🔍 查看当前用户的cron任务："
crontab -l | grep "$RENEW_SCRIPT"
echo ""
echo "📝 查看续签日志："
echo "  tail -f $LOG_FILE"
echo ""
echo "🧪 手动测试续签："
echo "  $RENEW_SCRIPT"