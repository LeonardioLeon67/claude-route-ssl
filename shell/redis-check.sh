#!/bin/bash

# Redis 连接检查脚本
# 确保使用正确的端口 6380

REDIS_PORT=6380
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🔍 检查 Redis 连接状态${NC}"
echo "==============================================="

# 检查 6380 端口
echo -n "检查端口 6380: "
if redis-cli -p $REDIS_PORT ping > /dev/null 2>&1; then
    echo -e "${GREEN}✅ 连接正常${NC}"
else
    echo -e "${RED}❌ 连接失败${NC}"
    echo -e "${YELLOW}💡 提示: 系统配置使用端口 6380，请确保 Redis 在正确端口运行${NC}"
    exit 1
fi

# 检查错误的端口 6379
echo -n "检查端口 6379: "
if redis-cli -p 6379 ping > /dev/null 2>&1; then
    echo -e "${RED}⚠️  警告: 检测到 Redis 在端口 6379 运行${NC}"
    echo -e "${YELLOW}   这可能导致数据不一致问题${NC}"
    echo -e "${YELLOW}   建议停止端口 6379 的 Redis 实例${NC}"
else
    echo -e "${GREEN}✅ 端口 6379 空闲（正确）${NC}"
fi

echo ""
echo -e "${GREEN}🎯 Redis 检查完成${NC}"