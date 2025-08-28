#!/bin/bash

# Redis数据恢复脚本
# 用于恢复Claude Route SSL项目的Redis备份数据

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
REDIS_PORT=6380
REDIS_DIR="/var/lib/redis"
REDIS_DBFILE="dump.rdb"

# 显示使用方法
show_usage() {
    echo -e "${YELLOW}使用方法:${NC}"
    echo -e "  $0 <备份路径>"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo -e "  $0 ~/claude-route-ssl-backup/redis-backup-20250827_120000"
    echo -e "  $0 ~/claude-route-ssl-backup/latest"
    echo ""
    echo -e "${YELLOW}备份路径应包含以下文件:${NC}"
    echo -e "  - *.rdb (RDB备份文件)"
    echo -e "  - *.json (JSON数据备份)"
    echo -e "  - *-project.tar.gz (项目文件备份)"
    exit 1
}

# 检查参数
if [ $# -ne 1 ]; then
    show_usage
fi

BACKUP_PATH="$1"

# 检查备份文件
check_backup_files() {
    echo -e "${BLUE}检查备份文件...${NC}"
    
    # 如果是符号链接，获取实际路径
    if [ -L "$BACKUP_PATH" ]; then
        BACKUP_PATH=$(readlink -f "$BACKUP_PATH")
    fi
    
    # 检查RDB文件
    RDB_FILE="$BACKUP_PATH.rdb"
    if [ ! -f "$RDB_FILE" ]; then
        echo -e "${RED}✗ 找不到RDB备份文件: $RDB_FILE${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ 找到RDB文件: $RDB_FILE${NC}"
    
    # 检查JSON文件
    JSON_FILE="$BACKUP_PATH.json"
    if [ -f "$JSON_FILE" ]; then
        echo -e "${GREEN}✓ 找到JSON文件: $JSON_FILE${NC}"
    else
        echo -e "${YELLOW}⚠ 未找到JSON文件: $JSON_FILE${NC}"
    fi
    
    # 检查项目文件
    PROJECT_FILE="$BACKUP_PATH-project.tar.gz"
    if [ -f "$PROJECT_FILE" ]; then
        echo -e "${GREEN}✓ 找到项目文件: $PROJECT_FILE${NC}"
    else
        echo -e "${YELLOW}⚠ 未找到项目文件: $PROJECT_FILE${NC}"
    fi
    
    # 检查统计文件
    STATS_FILE="$BACKUP_PATH-stats.txt"
    if [ -f "$STATS_FILE" ]; then
        echo -e "${GREEN}✓ 找到统计文件: $STATS_FILE${NC}"
        echo ""
        echo -e "${BLUE}备份统计信息:${NC}"
        grep -E "(备份时间|client_keys|_products|_pool)" "$STATS_FILE"
        echo ""
    fi
}

# 备份当前Redis数据
backup_current_redis() {
    echo -e "${BLUE}备份当前Redis数据...${NC}"
    
    # 获取当前key数量
    CURRENT_KEYS=$(redis-cli -p $REDIS_PORT DBSIZE | awk '{print $1}')
    
    if [ "$CURRENT_KEYS" -gt 0 ]; then
        echo -e "${YELLOW}当前Redis有 $CURRENT_KEYS 个keys${NC}"
        read -p "是否备份当前数据？(y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 触发备份
            redis-cli -p $REDIS_PORT BGSAVE
            sleep 2
            
            # 备份当前RDB文件
            BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
            sudo cp "$REDIS_DIR/$REDIS_DBFILE" "$HOME/redis-before-restore-$BACKUP_TIME.rdb"
            echo -e "${GREEN}✓ 当前数据已备份到: $HOME/redis-before-restore-$BACKUP_TIME.rdb${NC}"
        fi
    else
        echo -e "${BLUE}当前Redis为空，无需备份${NC}"
    fi
}

# 恢复RDB文件
restore_rdb() {
    echo -e "${BLUE}恢复RDB文件...${NC}"
    
    read -p "确认要恢复RDB文件吗？这将替换当前所有Redis数据 (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过RDB恢复${NC}"
        return
    fi
    
    # 停止Redis
    echo -e "${YELLOW}停止Redis服务...${NC}"
    sudo systemctl stop redis
    
    # 备份原RDB文件
    if [ -f "$REDIS_DIR/$REDIS_DBFILE" ]; then
        sudo mv "$REDIS_DIR/$REDIS_DBFILE" "$REDIS_DIR/$REDIS_DBFILE.bak"
    fi
    
    # 复制新RDB文件
    sudo cp "$RDB_FILE" "$REDIS_DIR/$REDIS_DBFILE"
    sudo chown redis:redis "$REDIS_DIR/$REDIS_DBFILE"
    
    # 启动Redis
    echo -e "${YELLOW}启动Redis服务...${NC}"
    sudo systemctl start redis
    
    # 等待Redis启动
    sleep 2
    
    # 检查恢复结果
    redis-cli -p $REDIS_PORT ping > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Redis服务已启动${NC}"
        NEW_KEYS=$(redis-cli -p $REDIS_PORT DBSIZE | awk '{print $1}')
        echo -e "${GREEN}✓ 恢复成功！当前有 $NEW_KEYS 个keys${NC}"
    else
        echo -e "${RED}✗ Redis启动失败，请检查日志${NC}"
        exit 1
    fi
}

# 恢复JSON数据
restore_json() {
    if [ ! -f "$JSON_FILE" ]; then
        return
    fi
    
    echo -e "${BLUE}从JSON恢复数据...${NC}"
    
    read -p "是否从JSON文件恢复数据？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过JSON恢复${NC}"
        return
    fi
    
    python3 - <<EOF
import redis
import json
import sys

try:
    # 连接Redis
    r = redis.Redis(host='localhost', port=$REDIS_PORT, decode_responses=True)
    r.ping()
    
    # 读取JSON文件
    with open('$JSON_FILE', 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # 恢复数据
    restored = 0
    for key, info in data['keys'].items():
        key_type = info['type']
        value = info['value']
        ttl = info.get('ttl', -1)
        
        if key_type == 'string':
            r.set(key, value)
        elif key_type == 'hash':
            if value:  # 只有当hash非空时才设置
                r.hset(key, mapping=value)
        elif key_type == 'list':
            if value:
                r.rpush(key, *value)
        elif key_type == 'set':
            if value:
                r.sadd(key, *value)
        elif key_type == 'zset':
            if value:
                r.zadd(key, dict(value))
        
        # 设置TTL
        if ttl > 0:
            r.expire(key, ttl)
        
        restored += 1
    
    print(f"✓ 成功恢复 {restored} 个keys")
    
except Exception as e:
    print(f"✗ 恢复失败: {e}")
    sys.exit(1)
EOF
}

# 恢复项目文件
restore_project_files() {
    if [ ! -f "$PROJECT_FILE" ]; then
        return
    fi
    
    echo -e "${BLUE}恢复项目文件...${NC}"
    
    read -p "是否恢复项目文件 (account/和product/目录)？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过项目文件恢复${NC}"
        return
    fi
    
    # 项目根目录（脚本在redis-migrate子目录中）
    PROJECT_DIR="$(dirname "$0")/.."
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    
    # 备份当前目录
    if [ -d "$PROJECT_DIR/account" ] || [ -d "$PROJECT_DIR/product" ]; then
        BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
        tar -czf "$HOME/project-before-restore-$BACKUP_TIME.tar.gz" \
            -C "$PROJECT_DIR" \
            account/ product/ 2>/dev/null
        echo -e "${GREEN}✓ 当前项目文件已备份到: $HOME/project-before-restore-$BACKUP_TIME.tar.gz${NC}"
    fi
    
    # 解压恢复
    tar -xzf "$PROJECT_FILE" -C "$PROJECT_DIR"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 项目文件恢复成功${NC}"
    else
        echo -e "${RED}✗ 项目文件恢复失败${NC}"
    fi
}

# 验证恢复结果
verify_restore() {
    echo ""
    echo -e "${BLUE}验证恢复结果...${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 显示统计信息
    echo -e "${YELLOW}数据库统计:${NC}"
    echo "  总Key数量: $(redis-cli -p $REDIS_PORT DBSIZE | awk '{print $1}')"
    echo ""
    
    echo -e "${YELLOW}Key分类统计:${NC}"
    echo "  client_keys: $(redis-cli -p $REDIS_PORT --scan --pattern "client_keys:*" | wc -l)"
    echo "  trial_products: $(redis-cli -p $REDIS_PORT --scan --pattern "trial_products:*" | wc -l)"
    echo "  medium_products: $(redis-cli -p $REDIS_PORT --scan --pattern "medium_products:*" | wc -l)"
    echo "  high_products: $(redis-cli -p $REDIS_PORT --scan --pattern "high_products:*" | wc -l)"
    echo "  supreme_products: $(redis-cli -p $REDIS_PORT --scan --pattern "supreme_products:*" | wc -l)"
    echo ""
    
    echo -e "${YELLOW}池统计:${NC}"
    echo "  trial_pool: $(redis-cli -p $REDIS_PORT --scan --pattern "trial_pool:*" | wc -l)"
    echo "  medium_pool: $(redis-cli -p $REDIS_PORT --scan --pattern "medium_pool:*" | wc -l)"
    echo "  high_pool: $(redis-cli -p $REDIS_PORT --scan --pattern "high_pool:*" | wc -l)"
    echo "  supreme_pool: $(redis-cli -p $REDIS_PORT --scan --pattern "supreme_pool:*" | wc -l)"
    echo ""
    
    # 测试一个具体的key
    TEST_KEY=$(redis-cli -p $REDIS_PORT --scan --pattern "client_keys:*" | head -1)
    if [ ! -z "$TEST_KEY" ]; then
        echo -e "${YELLOW}示例Key验证:${NC}"
        echo "  Key: $TEST_KEY"
        redis-cli -p $REDIS_PORT hget "$TEST_KEY" "tier" | xargs echo "  Tier:"
        redis-cli -p $REDIS_PORT hget "$TEST_KEY" "status" | xargs echo "  Status:"
    fi
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 主函数
main() {
    echo -e "${GREEN}=== Claude Route SSL Redis恢复工具 ===${NC}"
    echo ""
    
    # 检查Redis连接
    redis-cli -p $REDIS_PORT ping > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 无法连接到Redis端口 $REDIS_PORT${NC}"
        echo -e "${YELLOW}请确保Redis服务正在运行${NC}"
        exit 1
    fi
    
    # 执行恢复步骤
    check_backup_files
    backup_current_redis
    restore_rdb
    restore_json
    restore_project_files
    verify_restore
    
    echo ""
    echo -e "${GREEN}✓ 恢复完成！${NC}"
    echo ""
    echo -e "${BLUE}后续步骤:${NC}"
    echo "1. 检查服务状态: direct status"
    echo "2. 重启服务: direct restart"
    echo "3. 查看池状态: direct pool"
    echo "4. 监控日志: direct logs"
}

# 运行主函数
main