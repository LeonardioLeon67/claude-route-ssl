#!/bin/bash

# Redis Restore Script for Claude Route SSL Project
# 恢复Redis 6380端口的所有数据
# 作者: Claude
# 日期: 2025-08-29

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}     Redis Restore Script for Claude Route SSL${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# 检查备份目录是否存在
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}❌ 错误: 备份目录不存在: $BACKUP_DIR${NC}"
    echo -e "${YELLOW}请确保已经复制备份文件到正确的位置${NC}"
    exit 1
fi

# 列出可用的备份文件
echo -e "${CYAN}可用的备份文件:${NC}"
echo ""

# 获取所有备份文件并编号
BACKUPS=($(ls -1t "$BACKUP_DIR"/*.rdb 2>/dev/null))

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo -e "${RED}❌ 错误: 没有找到任何备份文件${NC}"
    echo -e "${YELLOW}请先运行 redis-backup.sh 创建备份${NC}"
    exit 1
fi

# 显示备份列表
for i in "${!BACKUPS[@]}"; do
    BACKUP_FILE="${BACKUPS[$i]}"
    BACKUP_NAME=$(basename "$BACKUP_FILE")
    TIMESTAMP="${BACKUP_NAME#redis_backup_}"
    TIMESTAMP="${TIMESTAMP%.rdb}"
    
    # 尝试读取对应的info文件
    INFO_FILE="$BACKUP_DIR/backup_info_${TIMESTAMP}.json"
    if [ -f "$INFO_FILE" ]; then
        BACKUP_TIME=$(grep '"backup_time"' "$INFO_FILE" | cut -d'"' -f4)
        TOTAL_KEYS=$(grep '"total_keys"' "$INFO_FILE" | cut -d':' -f2 | tr -d ', ')
        FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    else
        BACKUP_TIME="未知"
        TOTAL_KEYS="未知"
        FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    fi
    
    printf "  ${GREEN}[%2d]${NC} %s\n" "$((i+1))" "$BACKUP_NAME"
    printf "       时间: %s | 键数: %s | 大小: %s\n" "$BACKUP_TIME" "$TOTAL_KEYS" "$FILE_SIZE"
    echo ""
done

# 让用户选择要恢复的备份
echo -e "${YELLOW}请选择要恢复的备份文件编号 (1-${#BACKUPS[@]}):${NC}"
read -p "> " CHOICE

# 验证用户输入
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#BACKUPS[@]} ]; then
    echo -e "${RED}❌ 错误: 无效的选择${NC}"
    exit 1
fi

# 获取选中的备份文件
SELECTED_BACKUP="${BACKUPS[$((CHOICE-1))]}"
BACKUP_NAME=$(basename "$SELECTED_BACKUP")
TIMESTAMP="${BACKUP_NAME#redis_backup_}"
TIMESTAMP="${TIMESTAMP%.rdb}"

echo ""
echo -e "${BLUE}已选择备份文件: $BACKUP_NAME${NC}"
echo ""

# 显示备份详细信息
INFO_FILE="$BACKUP_DIR/backup_info_${TIMESTAMP}.json"
if [ -f "$INFO_FILE" ]; then
    echo -e "${CYAN}备份详细信息:${NC}"
    echo -e "  创建时间: $(grep '"backup_time"' "$INFO_FILE" | cut -d'"' -f4)"
    echo -e "  总键数: $(grep '"total_keys"' "$INFO_FILE" | cut -d':' -f2 | tr -d ', ')"
    echo -e "  内存使用: $(grep '"memory_used"' "$INFO_FILE" | cut -d'"' -f4)"
    echo -e "  文件大小: $(grep '"file_size"' "$INFO_FILE" | cut -d'"' -f4)"
    echo ""
fi

# 警告信息
echo -e "${RED}⚠️  警告: 恢复操作将会清空当前Redis (端口 $REDIS_PORT) 的所有数据！${NC}"
echo -e "${YELLOW}是否继续? (yes/no):${NC}"
read -p "> " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}操作已取消${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}[1/6] 检查Redis服务状态...${NC}"

# 检查Redis是否在运行
REDIS_RUNNING=false
if redis-cli -p $REDIS_PORT ping > /dev/null 2>&1; then
    REDIS_RUNNING=true
    echo -e "${GREEN}✅ Redis正在运行 (端口: $REDIS_PORT)${NC}"
    
    # 备份当前数据（安全起见）
    echo -e "${YELLOW}[2/6] 备份当前数据（安全备份）...${NC}"
    SAFETY_BACKUP="$BACKUP_DIR/safety_backup_$(date +%Y%m%d_%H%M%S).rdb"
    redis-cli -p $REDIS_PORT BGSAVE > /dev/null
    
    # 等待备份完成
    echo -n "  等待安全备份完成"
    while [ "$(redis-cli -p $REDIS_PORT INFO persistence | grep rdb_bgsave_in_progress:1)" ]; do
        echo -n "."
        sleep 1
    done
    echo ""
    
    # 复制当前RDB文件作为安全备份
    RDB_PATH=$(redis-cli -p $REDIS_PORT CONFIG GET dir | tail -1)
    RDB_FILE=$(redis-cli -p $REDIS_PORT CONFIG GET dbfilename | tail -1)
    SOURCE_RDB="$RDB_PATH/$RDB_FILE"
    
    if [ -f "$SOURCE_RDB" ]; then
        cp "$SOURCE_RDB" "$SAFETY_BACKUP"
        echo -e "${GREEN}✅ 当前数据已备份到: $(basename $SAFETY_BACKUP)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Redis未运行，尝试启动...${NC}"
    
    # 尝试启动Redis
    redis-server --port $REDIS_PORT --daemonize yes --dir /tmp --dbfilename dump_$REDIS_PORT.rdb
    sleep 2
    
    if redis-cli -p $REDIS_PORT ping > /dev/null 2>&1; then
        REDIS_RUNNING=true
        echo -e "${GREEN}✅ Redis已启动 (端口: $REDIS_PORT)${NC}"
    else
        echo -e "${RED}❌ 错误: 无法启动Redis服务${NC}"
        echo -e "${YELLOW}请手动启动Redis后重试${NC}"
        echo -e "${YELLOW}启动命令: redis-server --port $REDIS_PORT --daemonize yes${NC}"
        exit 1
    fi
    echo -e "${YELLOW}[2/6] 跳过安全备份（Redis刚启动，无数据）${NC}"
fi

# 清空当前数据库
echo -e "${YELLOW}[3/6] 清空当前数据库...${NC}"
redis-cli -p $REDIS_PORT FLUSHALL > /dev/null
echo -e "${GREEN}✅ 数据库已清空${NC}"

# 获取Redis的工作目录和文件名配置
echo -e "${YELLOW}[4/6] 配置Redis恢复参数...${NC}"
RDB_PATH=$(redis-cli -p $REDIS_PORT CONFIG GET dir | tail -1)
RDB_FILE=$(redis-cli -p $REDIS_PORT CONFIG GET dbfilename | tail -1)
TARGET_RDB="$RDB_PATH/$RDB_FILE"

echo -e "  Redis工作目录: $RDB_PATH"
echo -e "  RDB文件名: $RDB_FILE"

# 复制备份文件到Redis工作目录
echo -e "${YELLOW}[5/6] 复制备份文件...${NC}"
cp "$SELECTED_BACKUP" "$TARGET_RDB"
echo -e "${GREEN}✅ 备份文件已复制到: $TARGET_RDB${NC}"

# 重启Redis以加载新的RDB文件
echo -e "${YELLOW}[6/6] 重启Redis服务以加载数据...${NC}"

# 停止Redis
redis-cli -p $REDIS_PORT SHUTDOWN NOSAVE > /dev/null 2>&1
sleep 2

# 重新启动Redis
redis-server --port $REDIS_PORT --daemonize yes --dir "$RDB_PATH" --dbfilename "$RDB_FILE"
sleep 3

# 验证恢复结果
echo ""
echo -e "${CYAN}验证恢复结果...${NC}"

if ! redis-cli -p $REDIS_PORT ping > /dev/null 2>&1; then
    echo -e "${RED}❌ 错误: Redis服务启动失败${NC}"
    exit 1
fi

# 获取恢复后的统计信息
RESTORED_KEYS=$(redis-cli -p $REDIS_PORT DBSIZE | awk '{print $1}')
MEMORY_USED=$(redis-cli -p $REDIS_PORT INFO memory | grep used_memory_human: | cut -d: -f2 | tr -d '\r')

echo -e "  📊 恢复的键总数: ${GREEN}$RESTORED_KEYS${NC}"
echo -e "  💾 内存使用: ${GREEN}$MEMORY_USED${NC}"

# 显示各类键的统计
echo ""
echo -e "${CYAN}恢复的数据统计:${NC}"

CLIENT_KEYS=$(redis-cli -p $REDIS_PORT --scan --pattern "client_keys:*" 2>/dev/null | wc -l)
MEDIUM_PRODUCTS=$(redis-cli -p $REDIS_PORT --scan --pattern "medium_products:*" 2>/dev/null | wc -l)
HIGH_PRODUCTS=$(redis-cli -p $REDIS_PORT --scan --pattern "high_products:*" 2>/dev/null | wc -l)
SUPREME_PRODUCTS=$(redis-cli -p $REDIS_PORT --scan --pattern "supreme_products:*" 2>/dev/null | wc -l)
TRIAL_PRODUCTS=$(redis-cli -p $REDIS_PORT --scan --pattern "trial_products:*" 2>/dev/null | wc -l)
MEDIUM_SLOTS=$(redis-cli -p $REDIS_PORT --scan --pattern "medium_pool:slots:*" 2>/dev/null | wc -l)
HIGH_SLOTS=$(redis-cli -p $REDIS_PORT --scan --pattern "high_pool:slots:*" 2>/dev/null | wc -l)
SUPREME_SLOTS=$(redis-cli -p $REDIS_PORT --scan --pattern "supreme_pool:slots:*" 2>/dev/null | wc -l)
TRIAL_SLOTS=$(redis-cli -p $REDIS_PORT --scan --pattern "trial_pool:slots:*" 2>/dev/null | wc -l)

echo -e "  客户端密钥: ${GREEN}$CLIENT_KEYS${NC}"
echo -e "  Trial产品: ${GREEN}$TRIAL_PRODUCTS${NC}"
echo -e "  Medium产品: ${GREEN}$MEDIUM_PRODUCTS${NC}"
echo -e "  High产品: ${GREEN}$HIGH_PRODUCTS${NC}"
echo -e "  Supreme产品: ${GREEN}$SUPREME_PRODUCTS${NC}"
echo -e "  Trial Slots: ${GREEN}$TRIAL_SLOTS${NC}"
echo -e "  Medium Slots: ${GREEN}$MEDIUM_SLOTS${NC}"
echo -e "  High Slots: ${GREEN}$HIGH_SLOTS${NC}"
echo -e "  Supreme Slots: ${GREEN}$SUPREME_SLOTS${NC}"

# 验证一些关键数据
echo ""
echo -e "${CYAN}验证关键数据完整性:${NC}"

# 检查永久绑定数据
BINDING_EXISTS=false
for tier in trial medium high supreme; do
    if redis-cli -p $REDIS_PORT exists "permanent_binding:$tier" > /dev/null 2>&1; then
        if [ "$(redis-cli -p $REDIS_PORT exists "permanent_binding:$tier")" = "1" ]; then
            BINDING_COUNT=$(redis-cli -p $REDIS_PORT hlen "permanent_binding:$tier")
            if [ "$BINDING_COUNT" -gt 0 ]; then
                echo -e "  ✅ $tier 永久绑定数据: ${GREEN}$BINDING_COUNT 条${NC}"
                BINDING_EXISTS=true
            fi
        fi
    fi
done

if [ "$BINDING_EXISTS" = false ]; then
    echo -e "  ⚠️  未找到永久绑定数据（可能是新系统）"
fi

# 完成
echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}        🎉 数据恢复完成！${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "  📦 恢复的备份: ${BLUE}$BACKUP_NAME${NC}"
echo -e "  📊 恢复的键数: ${BLUE}$RESTORED_KEYS${NC}"
echo -e "  💾 内存使用: ${BLUE}$MEMORY_USED${NC}"
echo ""

# 提示重启应用
echo -e "${YELLOW}提示:${NC}"
echo -e "  1. Redis数据已成功恢复"
echo -e "  2. 建议重启Claude Route SSL应用以确保数据同步"
echo -e "  3. 重启命令: ${CYAN}direct restart${NC} 或 ${CYAN}cd $PROJECT_ROOT/shell && ./restart.sh${NC}"
echo ""

# 询问是否重启应用
echo -e "${YELLOW}是否现在重启Claude Route SSL应用? (yes/no):${NC}"
read -p "> " RESTART_APP

if [ "$RESTART_APP" = "yes" ]; then
    echo -e "${YELLOW}正在重启应用...${NC}"
    if [ -f "$PROJECT_ROOT/shell/restart.sh" ]; then
        bash "$PROJECT_ROOT/shell/restart.sh"
    elif command -v direct &> /dev/null; then
        direct restart
    else
        echo -e "${YELLOW}请手动重启应用${NC}"
    fi
fi

exit 0