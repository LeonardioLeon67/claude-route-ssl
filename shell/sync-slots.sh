#!/bin/bash

# Slot数据同步脚本
# 确保Redis中的slot计数与实际的key绑定关系一致

REDIS_PORT=6380

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=== Slot Data Synchronization Tool ===${NC}"
echo ""

# 检查Redis连接
if ! redis-cli -p $REDIS_PORT ping > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Cannot connect to Redis on port $REDIS_PORT${NC}"
    exit 1
fi

echo -e "${BLUE}🔍 Checking slot consistency...${NC}"
echo ""

for tier in medium high supreme; do
    echo -e "${YELLOW}=== $tier TIER ===${NC}"
    
    # 获取永久绑定关系
    binding_key="${tier}_pool:permanent_binding"
    bindings=$(redis-cli -p $REDIS_PORT hgetall "$binding_key" 2>/dev/null)
    
    # 统计每个账户的实际绑定数量
    declare -A account_bindings
    
    if [ ! -z "$bindings" ]; then
        # 解析绑定关系 (key value key value ...)
        keys=()
        values=()
        while IFS= read -r line; do
            if [ ${#keys[@]} -eq ${#values[@]} ]; then
                keys+=("$line")
            else
                values+=("$line")
                account="${line}"
                if [ -z "${account_bindings[$account]}" ]; then
                    account_bindings[$account]=0
                fi
                account_bindings[$account]=$((account_bindings[$account] + 1))
            fi
        done <<< "$bindings"
    fi
    
    # 检查每个账户的slot数据
    echo "  Checking accounts..."
    account_dir="../account/$tier"
    
    echo "  Account directory: $account_dir"
    
    if [ -d "$account_dir" ]; then
        for account_file in "$account_dir"/*.json; do
            if [ -f "$account_file" ]; then
                account_name=$(basename "$account_file" .json)
                slot_key="${tier}_pool:slots:$account_name"
                current_slots=$(redis-cli -p $REDIS_PORT get "$slot_key" 2>/dev/null)
                
                if [ -z "$current_slots" ]; then
                    current_slots=0
                fi
                
                # 获取实际绑定数量
                actual_bindings=${account_bindings[$account_name]:-0}
                
                if [ $current_slots -ne $actual_bindings ]; then
                    echo -e "  ${RED}❌ $account_name: slots=$current_slots, bindings=$actual_bindings${NC}"
                    
                    # 修复slot计数
                    if [ $actual_bindings -eq 0 ]; then
                        redis-cli -p $REDIS_PORT del "$slot_key" > /dev/null
                        echo -e "  ${GREEN}✓ Deleted empty slot record for $account_name${NC}"
                    else
                        redis-cli -p $REDIS_PORT set "$slot_key" "$actual_bindings" > /dev/null
                        echo -e "  ${GREEN}✓ Updated $account_name slots: $current_slots → $actual_bindings${NC}"
                    fi
                else
                    echo -e "  ${GREEN}✓ $account_name: consistent ($current_slots slots)${NC}"
                fi
            fi
        done
    fi
    
    echo ""
done

echo -e "${GREEN}🎉 Slot synchronization completed!${NC}"
echo -e "${BLUE}Run 'direct pool' to verify the updated status.${NC}"