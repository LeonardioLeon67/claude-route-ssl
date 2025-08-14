#!/bin/bash

# 密钥备份脚本 - 创建产品文件的定期备份
# 用于防止Redis持久化失败时的数据丢失

echo "🔐 开始备份密钥数据..."
echo "========================="

PROJECT_DIR="/home/leon/claude-route-ssl/claude-route-ssl"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 创建备份目录
mkdir -p "$BACKUP_DIR"

cd "$PROJECT_DIR"

# 备份产品文件
echo "📋 备份产品文件..."
if [ -f "product/medium.json" ]; then
    cp "product/medium.json" "$BACKUP_DIR/medium_${TIMESTAMP}.json"
    echo "✅ Medium产品文件已备份: medium_${TIMESTAMP}.json"
else
    echo "⚠️  Medium产品文件不存在"
fi

if [ -f "product/high.json" ]; then
    cp "product/high.json" "$BACKUP_DIR/high_${TIMESTAMP}.json"
    echo "✅ High产品文件已备份: high_${TIMESTAMP}.json"
else
    echo "⚠️  High产品文件不存在"
fi

# 备份账户文件
echo "📋 备份账户文件..."
if [ -d "account" ] && [ "$(ls -A account)" ]; then
    cp -r account "$BACKUP_DIR/account_${TIMESTAMP}"
    echo "✅ 账户文件已备份: account_${TIMESTAMP}/"
else
    echo "⚠️  账户文件目录为空或不存在"
fi

# 手动触发Redis保存
echo "📋 触发Redis数据保存..."
redis-cli -p 6380 BGSAVE > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Redis数据已保存"
else
    echo "⚠️  Redis保存失败或无法连接"
fi

# 统计备份文件
echo ""
echo "📊 备份统计:"
echo "   备份目录: $BACKUP_DIR"
echo "   备份时间: $TIMESTAMP"
echo "   文件列表:"
ls -la "$BACKUP_DIR" | grep "$TIMESTAMP" | awk '{print "     " $9 " (" $5 " bytes)"}'

# 清理旧备份 (保留最近7天)
echo ""
echo "🧹 清理旧备份文件..."
find "$BACKUP_DIR" -name "*_*" -type f -mtime +7 -delete 2>/dev/null
find "$BACKUP_DIR" -name "account_*" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
echo "✅ 已清理7天前的备份文件"

echo ""
echo "🎉 密钥备份完成!"
echo "========================="
echo "💡 建议定期运行此脚本进行备份"
echo "💡 或添加到crontab中自动执行"