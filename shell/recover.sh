#!/bin/bash

# 黑名单账户恢复脚本
# 用于恢复被加入黑名单的账户，使其重新可用于密钥绑定

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

REDIS_PORT=6380

# 切换到脚本所在目录
cd "$(dirname "$0")"

# 显示使用说明
show_usage() {
    echo -e "${CYAN}=== Account Blacklist Recovery Tool ===${NC}"
    echo ""
    echo -e "${GREEN}Usage:${NC}"
    echo -e "  $0 <account-name>"
    echo ""
    echo -e "${GREEN}Parameters:${NC}"
    echo -e "  account-name    Name of the account to recover from blacklist"
    echo ""
    echo -e "${GREEN}Examples:${NC}"
    echo -e "  $0 jasonlucy002-outlook"
    echo -e "  $0 tomlucy001-outlook"
    echo ""
    echo -e "${GREEN}Description:${NC}"
    echo -e "  This script removes the specified account from blacklist across all tiers,"
    echo -e "  allowing new keys to bind to this account again."
    echo ""
}

# 检查Redis连接
check_redis() {
    if ! redis-cli -p $REDIS_PORT ping > /dev/null 2>&1; then
        echo -e "${RED}❌ Error: Cannot connect to Redis on port $REDIS_PORT${NC}"
        exit 1
    fi
}

# 查找账户所在的级别
find_account_tier() {
    local account_name=$1
    local found_tiers=()
    
    # 检查各级别目录
    for tier in medium high supreme; do
        if [ -f "../account/$tier/${account_name}.json" ]; then
            found_tiers+=("$tier")
        fi
    done
    
    # 也检查根目录（向后兼容）
    if [ -f "../account/${account_name}.json" ]; then
        found_tiers+=("root")
    fi
    
    echo "${found_tiers[@]}"
}

# 检查账户是否在黑名单中
check_blacklist_status() {
    local account_name=$1
    local blacklisted_tiers=()
    
    for tier in medium high supreme; do
        local blacklist_key="account_blacklist:${tier}:${account_name}"
        if redis-cli -p $REDIS_PORT exists "$blacklist_key" > /dev/null 2>&1; then
            if [ "$(redis-cli -p $REDIS_PORT exists "$blacklist_key")" = "1" ]; then
                blacklisted_tiers+=("$tier")
            fi
        fi
    done
    
    echo "${blacklisted_tiers[@]}"
}

# 恢复账户（从黑名单移除）
recover_account() {
    local account_name=$1
    local recovered_count=0
    
    echo -e "${BLUE}🔍 检查账户黑名单状态...${NC}"
    
    for tier in medium high supreme; do
        local blacklist_key="account_blacklist:${tier}:${account_name}"
        local blacklist_info=$(redis-cli -p $REDIS_PORT get "$blacklist_key" 2>/dev/null)
        
        if [ ! -z "$blacklist_info" ]; then
            echo -e "${YELLOW}📋 发现黑名单记录: [${tier^^}] ${account_name} - ${blacklist_info}${NC}"
            
            # 删除黑名单记录
            redis-cli -p $REDIS_PORT del "$blacklist_key" > /dev/null
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ 已从 ${tier^^} 级别黑名单中移除${NC}"
                recovered_count=$((recovered_count + 1))
            else
                echo -e "${RED}✗ 从 ${tier^^} 级别黑名单移除失败${NC}"
            fi
        fi
    done
    
    echo "$recovered_count"
}

# 主函数
main() {
    echo -e "${CYAN}=== Account Blacklist Recovery Tool ===${NC}"
    echo ""
    
    # 检查参数
    if [ $# -eq 0 ]; then
        echo -e "${RED}❌ Error: Account name is required${NC}"
        echo ""
        show_usage
        exit 1
    fi
    
    if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        show_usage
        exit 0
    fi
    
    local account_name=$1
    
    # 检查Redis连接
    check_redis
    
    echo -e "${BLUE}🎯 目标账户: ${account_name}${NC}"
    echo ""
    
    # 查找账户文件
    local found_tiers=($(find_account_tier "$account_name"))
    
    if [ ${#found_tiers[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠️  Warning: Account file not found in any tier directory${NC}"
        echo -e "${YELLOW}   但仍会尝试清除可能存在的黑名单记录${NC}"
        echo ""
    else
        echo -e "${GREEN}📂 发现账户文件:${NC}"
        for tier in "${found_tiers[@]}"; do
            if [ "$tier" = "root" ]; then
                echo -e "  - ../account/${account_name}.json"
            else
                echo -e "  - ../account/${tier}/${account_name}.json"
            fi
        done
        echo ""
    fi
    
    # 检查当前黑名单状态
    local blacklisted_tiers=($(check_blacklist_status "$account_name"))
    
    if [ ${#blacklisted_tiers[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ 账户 ${account_name} 当前不在任何黑名单中${NC}"
        echo -e "${GREEN}   该账户已可正常用于密钥绑定${NC}"
        exit 0
    fi
    
    echo -e "${RED}🚫 当前黑名单状态:${NC}"
    for tier in "${blacklisted_tiers[@]}"; do
        local blacklist_info=$(redis-cli -p $REDIS_PORT get "account_blacklist:${tier}:${account_name}")
        echo -e "  - [${tier^^}] ${blacklist_info}"
    done
    echo ""
    
    # 执行恢复操作
    echo -e "${YELLOW}🔧 开始恢复操作...${NC}"
    echo ""
    
    local recovered_count=$(recover_account "$account_name")
    
    echo ""
    if [ "$recovered_count" -gt 0 ] 2>/dev/null; then
        echo -e "${GREEN}✅ 恢复完成！${NC}"
        echo -e "${GREEN}   账户 ${account_name} 已从 ${recovered_count} 个级别的黑名单中移除${NC}"
        echo -e "${GREEN}   现在可以正常用于新密钥的绑定${NC}"
        echo ""
        echo -e "${CYAN}📋 接下来的操作:${NC}"
        echo -e "  - 新生成的密钥可以绑定到此账户"
        echo -e "  - 使用账户池模式的密钥可以分配到此账户"
        echo -e "  - 使用 'direct pool' 可查看账户当前状态"
    else
        echo -e "${YELLOW}⚠️  没有找到需要恢复的黑名单记录${NC}"
        echo -e "${YELLOW}   账户可能已经不在黑名单中${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}                    $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 运行主程序
main "$@"