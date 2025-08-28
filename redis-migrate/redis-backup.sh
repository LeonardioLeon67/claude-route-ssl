#!/bin/bash

# Redis数据备份脚本
# 用于备份Claude Route SSL项目的所有Redis数据

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
REDIS_PORT=6380
BACKUP_DIR="$HOME/claude-route-ssl-backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="redis-backup-$TIMESTAMP"

# 创建备份目录
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        echo -e "${GREEN}✓ 创建备份目录: $BACKUP_DIR${NC}"
    fi
}

# 备份RDB文件
backup_rdb() {
    echo -e "${BLUE}正在备份RDB文件...${NC}"
    
    # 触发RDB快照
    redis-cli -p $REDIS_PORT BGSAVE
    
    # 等待备份完成
    echo -e "${YELLOW}等待RDB快照完成...${NC}"
    while [ $(redis-cli -p $REDIS_PORT LASTSAVE) -eq $(redis-cli -p $REDIS_PORT LASTSAVE) ]; do
        sleep 1
    done
    
    # 获取RDB文件路径
    REDIS_DIR=$(redis-cli -p $REDIS_PORT CONFIG GET dir | tail -1)
    REDIS_DBFILE=$(redis-cli -p $REDIS_PORT CONFIG GET dbfilename | tail -1)
    RDB_PATH="$REDIS_DIR/$REDIS_DBFILE"
    
    # 复制RDB文件
    if [ -f "$RDB_PATH" ]; then
        cp "$RDB_PATH" "$BACKUP_DIR/$BACKUP_NAME.rdb"
        echo -e "${GREEN}✓ RDB文件已备份到: $BACKUP_DIR/$BACKUP_NAME.rdb${NC}"
    else
        echo -e "${RED}✗ 找不到RDB文件: $RDB_PATH${NC}"
        exit 1
    fi
}

# 导出所有key到JSON
export_keys_json() {
    echo -e "${BLUE}正在导出Redis数据到JSON...${NC}"
    
    # 创建Python脚本导出数据
    python3 - <<EOF
import redis
import json
import sys
from datetime import datetime

try:
    r = redis.Redis(host='localhost', port=$REDIS_PORT, decode_responses=True)
    r.ping()
    
    export_data = {
        'export_time': datetime.now().isoformat(),
        'redis_port': $REDIS_PORT,
        'keys': {}
    }
    
    # 导出所有key
    for key in r.scan_iter("*"):
        key_type = r.type(key)
        
        if key_type == 'string':
            export_data['keys'][key] = {
                'type': 'string',
                'value': r.get(key),
                'ttl': r.ttl(key)
            }
        elif key_type == 'hash':
            export_data['keys'][key] = {
                'type': 'hash',
                'value': r.hgetall(key),
                'ttl': r.ttl(key)
            }
        elif key_type == 'list':
            export_data['keys'][key] = {
                'type': 'list',
                'value': r.lrange(key, 0, -1),
                'ttl': r.ttl(key)
            }
        elif key_type == 'set':
            export_data['keys'][key] = {
                'type': 'set',
                'value': list(r.smembers(key)),
                'ttl': r.ttl(key)
            }
        elif key_type == 'zset':
            export_data['keys'][key] = {
                'type': 'zset',
                'value': r.zrange(key, 0, -1, withscores=True),
                'ttl': r.ttl(key)
            }
    
    # 保存到文件
    with open('$BACKUP_DIR/$BACKUP_NAME.json', 'w', encoding='utf-8') as f:
        json.dump(export_data, f, ensure_ascii=False, indent=2)
    
    print(f"✓ 导出 {len(export_data['keys'])} 个keys到JSON文件")
    
except Exception as e:
    print(f"✗ 导出失败: {e}")
    sys.exit(1)
EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ JSON数据已导出到: $BACKUP_DIR/$BACKUP_NAME.json${NC}"
    else
        echo -e "${RED}✗ JSON导出失败${NC}"
    fi
}

# 导出key列表
export_key_list() {
    echo -e "${BLUE}正在导出key列表...${NC}"
    
    redis-cli -p $REDIS_PORT --scan --pattern "*" > "$BACKUP_DIR/$BACKUP_NAME-keys.txt"
    
    KEY_COUNT=$(wc -l < "$BACKUP_DIR/$BACKUP_NAME-keys.txt")
    echo -e "${GREEN}✓ 导出 $KEY_COUNT 个keys到: $BACKUP_DIR/$BACKUP_NAME-keys.txt${NC}"
}

# 导出统计信息
export_stats() {
    echo -e "${BLUE}正在导出统计信息...${NC}"
    
    {
        echo "=== Redis备份统计信息 ==="
        echo "备份时间: $(date)"
        echo "Redis端口: $REDIS_PORT"
        echo ""
        echo "=== 数据库信息 ==="
        redis-cli -p $REDIS_PORT INFO keyspace
        echo ""
        echo "=== 内存信息 ==="
        redis-cli -p $REDIS_PORT INFO memory | grep "used_memory_human"
        echo ""
        echo "=== Key分类统计 ==="
        echo "client_keys: $(redis-cli -p $REDIS_PORT --scan --pattern "client_keys:*" | wc -l)"
        echo "trial_products: $(redis-cli -p $REDIS_PORT --scan --pattern "trial_products:*" | wc -l)"
        echo "medium_products: $(redis-cli -p $REDIS_PORT --scan --pattern "medium_products:*" | wc -l)"
        echo "high_products: $(redis-cli -p $REDIS_PORT --scan --pattern "high_products:*" | wc -l)"
        echo "supreme_products: $(redis-cli -p $REDIS_PORT --scan --pattern "supreme_products:*" | wc -l)"
        echo "trial_pool: $(redis-cli -p $REDIS_PORT --scan --pattern "trial_pool:*" | wc -l)"
        echo "medium_pool: $(redis-cli -p $REDIS_PORT --scan --pattern "medium_pool:*" | wc -l)"
        echo "high_pool: $(redis-cli -p $REDIS_PORT --scan --pattern "high_pool:*" | wc -l)"
        echo "supreme_pool: $(redis-cli -p $REDIS_PORT --scan --pattern "supreme_pool:*" | wc -l)"
        echo "blacklist: $(redis-cli -p $REDIS_PORT --scan --pattern "account_blacklist:*" | wc -l)"
        echo "rate_limit: $(redis-cli -p $REDIS_PORT --scan --pattern "*_rate_limit:*" | wc -l)"
    } > "$BACKUP_DIR/$BACKUP_NAME-stats.txt"
    
    echo -e "${GREEN}✓ 统计信息已导出到: $BACKUP_DIR/$BACKUP_NAME-stats.txt${NC}"
}

# 备份项目文件
backup_project_files() {
    echo -e "${BLUE}正在备份项目文件...${NC}"
    
    # 项目根目录（脚本在redis-migrate子目录中）
    PROJECT_DIR="$(dirname "$0")/.."
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    
    # 创建tar包
    tar -czf "$BACKUP_DIR/$BACKUP_NAME-project.tar.gz" \
        -C "$PROJECT_DIR" \
        account/ \
        product/ \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 项目文件已备份到: $BACKUP_DIR/$BACKUP_NAME-project.tar.gz${NC}"
    else
        echo -e "${YELLOW}⚠ 部分项目文件备份可能不完整${NC}"
    fi
}

# 创建备份信息文件
create_backup_info() {
    cat > "$BACKUP_DIR/$BACKUP_NAME-info.txt" <<EOF
Claude Route SSL Redis备份信息
================================
备份时间: $(date)
备份名称: $BACKUP_NAME
Redis端口: $REDIS_PORT
备份目录: $BACKUP_DIR

备份文件列表:
1. $BACKUP_NAME.rdb - Redis RDB持久化文件
2. $BACKUP_NAME.json - 完整数据JSON导出
3. $BACKUP_NAME-keys.txt - Key列表
4. $BACKUP_NAME-stats.txt - 统计信息
5. $BACKUP_NAME-project.tar.gz - 项目文件备份
6. $BACKUP_NAME-info.txt - 备份信息文件

恢复命令:
bash redis-restore.sh $BACKUP_DIR/$BACKUP_NAME

验证命令:
redis-cli -p $REDIS_PORT DBSIZE
redis-cli -p $REDIS_PORT --scan --pattern "*" | wc -l
EOF
    
    echo -e "${GREEN}✓ 备份信息已保存到: $BACKUP_DIR/$BACKUP_NAME-info.txt${NC}"
}

# 主函数
main() {
    echo -e "${GREEN}=== Claude Route SSL Redis备份工具 ===${NC}"
    echo ""
    
    # 检查Redis连接
    redis-cli -p $REDIS_PORT ping > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 无法连接到Redis端口 $REDIS_PORT${NC}"
        exit 1
    fi
    
    # 执行备份步骤
    create_backup_dir
    backup_rdb
    export_keys_json
    export_key_list
    export_stats
    backup_project_files
    create_backup_info
    
    # 显示备份摘要
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ 备份完成！${NC}"
    echo -e "${GREEN}备份目录: $BACKUP_DIR${NC}"
    echo -e "${GREEN}备份名称: $BACKUP_NAME${NC}"
    echo ""
    echo -e "${YELLOW}备份文件：${NC}"
    ls -lh "$BACKUP_DIR/$BACKUP_NAME"* | awk '{print "  " $9 " (" $5 ")"}'
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 创建最新备份的符号链接
    ln -sf "$BACKUP_NAME" "$BACKUP_DIR/latest"
    echo ""
    echo -e "${BLUE}提示: 使用 'bash redis-restore.sh $BACKUP_DIR/$BACKUP_NAME' 恢复此备份${NC}"
}

# 运行主函数
main