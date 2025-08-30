#!/bin/bash

# Redis Backup Script for Claude Route SSL Project
# 备份Redis 6380端口的所有数据
# 作者: Claude
# 日期: 2025-08-29

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Redis配置
REDIS_PORT=6380
REDIS_HOST="localhost"

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 项目根目录（claude-route-ssl）
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 备份目录（使用相对路径概念，但实际是基于项目根目录的绝对路径）
BACKUP_DIR="$PROJECT_ROOT/redis-migrate/redis-backup-file"

# 创建带时间戳的备份文件名
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="redis_backup_${TIMESTAMP}.rdb"
BACKUP_INFO="backup_info_${TIMESTAMP}.json"
BACKUP_KEYS="backup_keys_${TIMESTAMP}.txt"

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}     Redis Backup Script for Claude Route SSL${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# 检查Redis连接
echo -e "${YELLOW}[1/6] 检查Redis连接...${NC}"
if ! redis-cli -p $REDIS_PORT ping > /dev/null 2>&1; then
    echo -e "${RED}❌ 错误: 无法连接到Redis端口 $REDIS_PORT${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Redis连接成功 (端口: $REDIS_PORT)${NC}"

# 创建备份目录
echo -e "${YELLOW}[2/6] 创建备份目录...${NC}"
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo -e "${GREEN}✅ 备份目录已创建: $BACKUP_DIR${NC}"
else
    echo -e "${GREEN}✅ 备份目录已存在: $BACKUP_DIR${NC}"
fi

# 获取Redis统计信息
echo -e "${YELLOW}[3/6] 收集Redis统计信息...${NC}"
KEY_COUNT=$(redis-cli -p $REDIS_PORT DBSIZE | awk '{print $1}')
MEMORY_USED=$(redis-cli -p $REDIS_PORT INFO memory | grep used_memory_human: | cut -d: -f2 | tr -d '\r')

echo -e "  📊 键总数: ${GREEN}$KEY_COUNT${NC}"
echo -e "  💾 内存使用: ${GREEN}$MEMORY_USED${NC}"

# 保存所有键名列表
echo -e "${YELLOW}[4/6] 导出所有键名列表...${NC}"
redis-cli -p $REDIS_PORT --scan > "$BACKUP_DIR/$BACKUP_KEYS"
EXPORTED_KEYS=$(wc -l < "$BACKUP_DIR/$BACKUP_KEYS")
echo -e "${GREEN}✅ 已导出 $EXPORTED_KEYS 个键名到 $BACKUP_KEYS${NC}"

# 分类统计键
echo -e "${YELLOW}[5/6] 分析键类型统计...${NC}"
echo -e "  分析中..."

# 统计各类键的数量
CLIENT_KEYS=$(redis-cli -p $REDIS_PORT --scan --pattern "client_keys:*" 2>/dev/null | wc -l)
MEDIUM_PRODUCTS=$(redis-cli -p $REDIS_PORT --scan --pattern "medium_products:*" 2>/dev/null | wc -l)
HIGH_PRODUCTS=$(redis-cli -p $REDIS_PORT --scan --pattern "high_products:*" 2>/dev/null | wc -l)
SUPREME_PRODUCTS=$(redis-cli -p $REDIS_PORT --scan --pattern "supreme_products:*" 2>/dev/null | wc -l)
TRIAL_PRODUCTS=$(redis-cli -p $REDIS_PORT --scan --pattern "trial_products:*" 2>/dev/null | wc -l)
MEDIUM_SLOTS=$(redis-cli -p $REDIS_PORT --scan --pattern "medium_pool:slots:*" 2>/dev/null | wc -l)
HIGH_SLOTS=$(redis-cli -p $REDIS_PORT --scan --pattern "high_pool:slots:*" 2>/dev/null | wc -l)
SUPREME_SLOTS=$(redis-cli -p $REDIS_PORT --scan --pattern "supreme_pool:slots:*" 2>/dev/null | wc -l)
TRIAL_SLOTS=$(redis-cli -p $REDIS_PORT --scan --pattern "trial_pool:slots:*" 2>/dev/null | wc -l)
BLACKLIST_KEYS=$(redis-cli -p $REDIS_PORT --scan --pattern "account_blacklist:*" 2>/dev/null | wc -l)
REFRESH_KEYS=$(redis-cli -p $REDIS_PORT --scan --pattern "refresh_*" 2>/dev/null | wc -l)
BINDING_KEYS=$(redis-cli -p $REDIS_PORT --scan --pattern "permanent_binding:*" 2>/dev/null | wc -l)

echo -e "  📋 键类型统计:"
echo -e "     客户端密钥: ${GREEN}$CLIENT_KEYS${NC}"
echo -e "     Trial产品: ${GREEN}$TRIAL_PRODUCTS${NC}"
echo -e "     Medium产品: ${GREEN}$MEDIUM_PRODUCTS${NC}"
echo -e "     High产品: ${GREEN}$HIGH_PRODUCTS${NC}"
echo -e "     Supreme产品: ${GREEN}$SUPREME_PRODUCTS${NC}"
echo -e "     Trial Slots: ${GREEN}$TRIAL_SLOTS${NC}"
echo -e "     Medium Slots: ${GREEN}$MEDIUM_SLOTS${NC}"
echo -e "     High Slots: ${GREEN}$HIGH_SLOTS${NC}"
echo -e "     Supreme Slots: ${GREEN}$SUPREME_SLOTS${NC}"
echo -e "     黑名单记录: ${GREEN}$BLACKLIST_KEYS${NC}"
echo -e "     刷新相关: ${GREEN}$REFRESH_KEYS${NC}"
echo -e "     永久绑定: ${GREEN}$BINDING_KEYS${NC}"

# 执行BGSAVE命令创建RDB快照
echo -e "${YELLOW}[6/6] 创建RDB备份快照...${NC}"
redis-cli -p $REDIS_PORT BGSAVE > /dev/null

# 等待BGSAVE完成
echo -n "  等待备份完成"
while [ "$(redis-cli -p $REDIS_PORT INFO persistence | grep rdb_bgsave_in_progress:1)" ]; do
    echo -n "."
    sleep 1
done
echo ""

# 找到Redis的RDB文件位置
RDB_PATH=$(redis-cli -p $REDIS_PORT CONFIG GET dir | tail -1)
RDB_FILE=$(redis-cli -p $REDIS_PORT CONFIG GET dbfilename | tail -1)
SOURCE_RDB="$RDB_PATH/$RDB_FILE"

# 复制RDB文件到备份目录
if [ -f "$SOURCE_RDB" ]; then
    cp "$SOURCE_RDB" "$BACKUP_DIR/$BACKUP_FILE"
    echo -e "${GREEN}✅ RDB文件已备份到: $BACKUP_FILE${NC}"
    
    # 获取文件大小
    FILE_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
    echo -e "  📦 备份文件大小: ${GREEN}$FILE_SIZE${NC}"
else
    echo -e "${RED}❌ 错误: 无法找到RDB文件${NC}"
    exit 1
fi

# 创建备份信息JSON文件
cat > "$BACKUP_DIR/$BACKUP_INFO" << EOF
{
  "backup_time": "$(date '+%Y-%m-%d %H:%M:%S')",
  "backup_timestamp": "$TIMESTAMP",
  "redis_port": $REDIS_PORT,
  "redis_host": "$REDIS_HOST",
  "backup_file": "$BACKUP_FILE",
  "keys_file": "$BACKUP_KEYS",
  "project_root": "$PROJECT_ROOT",
  "statistics": {
    "total_keys": $KEY_COUNT,
    "memory_used": "$MEMORY_USED",
    "client_keys": $CLIENT_KEYS,
    "trial_products": $TRIAL_PRODUCTS,
    "medium_products": $MEDIUM_PRODUCTS,
    "high_products": $HIGH_PRODUCTS,
    "supreme_products": $SUPREME_PRODUCTS,
    "trial_slots": $TRIAL_SLOTS,
    "medium_slots": $MEDIUM_SLOTS,
    "high_slots": $HIGH_SLOTS,
    "supreme_slots": $SUPREME_SLOTS,
    "blacklist_keys": $BLACKLIST_KEYS,
    "refresh_keys": $REFRESH_KEYS,
    "binding_keys": $BINDING_KEYS
  },
  "file_size": "$FILE_SIZE",
  "backup_command": "redis-cli -p $REDIS_PORT BGSAVE"
}
EOF

echo -e "${GREEN}✅ 备份信息已保存到: $BACKUP_INFO${NC}"

# 显示备份完成信息
echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}        🎉 备份完成！${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "  📂 备份目录: ${BLUE}$BACKUP_DIR${NC}"
echo -e "  📦 RDB备份: ${BLUE}$BACKUP_FILE${NC}"
echo -e "  📄 键名列表: ${BLUE}$BACKUP_KEYS${NC}"
echo -e "  📊 备份信息: ${BLUE}$BACKUP_INFO${NC}"
echo ""
echo -e "${YELLOW}提示:${NC}"
echo -e "  1. 备份文件使用相对路径存储在: redis-migrate/redis-backup-file/"
echo -e "  2. 传输到其他机器时，请保持目录结构不变"
echo -e "  3. 使用 redis-restore.sh 脚本恢复数据"
echo ""

# 显示最近的5个备份
echo -e "${BLUE}最近的备份文件:${NC}"
ls -lht "$BACKUP_DIR"/*.rdb 2>/dev/null | head -5 | while read line; do
    echo "  $line"
done

# 清理旧备份（保留最近10个）
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.rdb 2>/dev/null | wc -l)
if [ $BACKUP_COUNT -gt 10 ]; then
    echo ""
    echo -e "${YELLOW}清理旧备份文件（保留最近10个）...${NC}"
    ls -1t "$BACKUP_DIR"/*.rdb | tail -n +11 | while read old_file; do
        rm -f "$old_file"
        base_name=$(basename "$old_file" .rdb)
        rm -f "$BACKUP_DIR/backup_info_${base_name#redis_backup_}.json"
        rm -f "$BACKUP_DIR/backup_keys_${base_name#redis_backup_}.txt"
        echo -e "  删除: $(basename "$old_file")"
    done
fi

exit 0