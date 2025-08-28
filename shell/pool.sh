#!/bin/bash

# 账户池状态监控脚本
# 显示所有级别账户池的当前状态

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

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                   Account Pool Status Monitor${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 检查Redis连接
redis-cli -p $REDIS_PORT ping > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Cannot connect to Redis on port $REDIS_PORT${NC}"
    exit 1
fi

# 显示各级别账户池状态的函数
show_tier_status() {
    local tier=$1
    local tier_color=$2
    local max_slots=$3
    local account_dir="../account/$tier"
    
    if [ ! -d "$account_dir" ]; then
        echo -e "${RED}Warning: $tier directory not found: $account_dir${NC}"
        return
    fi
    
    # 添加级别特定说明
    local tier_info=""
    if [ "$tier" = "trial" ]; then
        tier_info=" | Sonnet only, 42/5h, 1 day"
    elif [ "$tier" = "medium" ]; then
        tier_info=" | Sonnet only, 42/5h, 30 days"
    elif [ "$tier" = "high" ]; then
        tier_info=" | All models, Opus:10/5h, Sonnet:50/5h, 30 days"
    elif [ "$tier" = "supreme" ]; then
        tier_info=" | All models, Opus:15/5h, Sonnet:75/5h, 30 days"
    fi
    
    echo -e "${tier_color}=== ${tier^^} TIER ACCOUNTS (${max_slots} slots/account${tier_info}) ===${NC}"
    echo ""
    
    local total_accounts=0
    local total_slots_used=0
    local blacklisted_accounts=0
    
    # 检查是否有账户文件
    local has_accounts=false
    for account_file in "$account_dir"/*.json; do
        if [ -f "$account_file" ]; then
            has_accounts=true
            break
        fi
    done
    
    if [ "$has_accounts" = false ]; then
        echo ""
        return
    fi
    
    for account_file in "$account_dir"/*.json; do
        if [ -f "$account_file" ]; then
            local account_name=$(basename "$account_file" .json)
            local slot_key="${tier}_pool:slots:$account_name"
            local slots_used=$(redis-cli -p $REDIS_PORT get "$slot_key" 2>/dev/null)
            
            if [ -z "$slots_used" ]; then
                slots_used=0
            fi
            
            # 检查是否在黑名单中
            local blacklist_key="account_blacklist:${tier}:$account_name"
            local is_blacklisted=$(redis-cli -p $REDIS_PORT exists "$blacklist_key" 2>/dev/null)
            
            # 黑名单账户跳过主状态栏显示，只统计非黑名单账户
            if [ "$is_blacklisted" = "1" ]; then
                blacklisted_accounts=$((blacklisted_accounts + 1))
                continue  # 跳过显示，只在Blacklist Management区域显示
            fi
            
            total_accounts=$((total_accounts + 1))
            total_slots_used=$((total_slots_used + slots_used))
            
            # 选择颜色和状态（只对非黑名单账户）
            local color status
            if [ $slots_used -eq 0 ]; then
                color=$GREEN
                status="Available"
            elif [ $slots_used -eq $max_slots ]; then
                color=$RED
                status="Full"
            else
                color=$YELLOW
                status="Partial"
            fi
            
            # 显示进度条
            local bar=""
            for i in $(seq 1 $max_slots); do
                if [ $i -le $slots_used ]; then
                    bar="${bar}█"
                else
                    bar="${bar}░"
                fi
            done
            
            printf "  %-30s: ${color}%s${NC} [%d/%d] %s\n" \
                "$account_name" "$bar" "$slots_used" "$max_slots" "$status"
        fi
    done
    
    # 统计信息
    if [ $total_accounts -gt 0 ]; then
        local total_slots=$((total_accounts * max_slots))
        local available_slots=$((total_slots - total_slots_used))
        local usage_percent=$((total_slots_used * 100 / total_slots))
        
        echo ""
        echo "    Accounts: $total_accounts | Total Slots: $total_slots | Used: $total_slots_used | Available: $available_slots | Usage: ${usage_percent}%"
    fi
    
    echo ""
}

# 显示所有级别的状态
show_tier_status "trial" "$YELLOW" 7
show_tier_status "medium" "$GREEN" 7
show_tier_status "high" "$PURPLE" 3  
show_tier_status "supreme" "$CYAN" 2

# 显示黑名单账户详细信息
echo ""
echo -e "${RED}🚫 Blacklisted Accounts:${NC}"
echo "─────────────────────────────────────────────────────────────────────"

blacklist_found=false
for tier in trial medium high supreme; do
    # 确定级别颜色和slot配置
    case $tier in
        "trial") tier_color=$YELLOW; max_slots=7 ;;
        "medium") tier_color=$GREEN; max_slots=7 ;;
        "high") tier_color=$PURPLE; max_slots=3 ;;
        "supreme") tier_color=$CYAN; max_slots=2 ;;
    esac
    
    # 获取该级别的黑名单账户
    blacklist_keys=$(redis-cli -p $REDIS_PORT keys "account_blacklist:${tier}:*" 2>/dev/null)
    
    if [ ! -z "$blacklist_keys" ]; then
        blacklist_found=true
        
        for blacklist_key in $blacklist_keys; do
            # 从key中提取账户名
            account_name=$(echo "$blacklist_key" | sed "s/account_blacklist:${tier}://")
            
            # 获取黑名单时间
            blacklist_info=$(redis-cli -p $REDIS_PORT get "$blacklist_key" 2>/dev/null)
            
            # 获取当前slot占用
            slot_key="${tier}_pool:slots:$account_name"
            slots_used=$(redis-cli -p $REDIS_PORT get "$slot_key" 2>/dev/null)
            if [ -z "$slots_used" ]; then
                slots_used=0
            fi
            
            # 显示黑名单账户信息
            printf "  ${tier_color}[${tier^^}]${NC} %-25s: ${RED}BLACKLISTED ⛔${NC} (slots: %d/%d) - %s\n" \
                "$account_name" "$slots_used" "$max_slots" "$blacklist_info"
        done
    fi
done

# 只显示真实的黑名单账户，不显示"无黑名单"消息


echo ""
echo -e "${YELLOW}🔄 Refresh Failed Status:${NC}"
echo "─────────────────────────────────────────────────────────────────────"

# 显示刷新失败达到上限的账户
refresh_failed_count=0

for tier in trial medium high supreme; do
    # 获取所有刷新尝试记录
    attempt_keys=$(redis-cli -p $REDIS_PORT keys "refresh_attempts:*" 2>/dev/null)
    
    if [ ! -z "$attempt_keys" ]; then
        for attempt_key in $attempt_keys; do
            # 获取尝试次数
            attempt_count=$(redis-cli -p $REDIS_PORT get "$attempt_key" 2>/dev/null)
            
            if [ ! -z "$attempt_count" ] && [ "$attempt_count" -ge 3 ]; then
                # 从key中提取账户名 (格式: refresh_attempts:account_name)
                account_name=$(echo "$attempt_key" | sed 's/refresh_attempts://')
                
                # 检查账户属于哪个级别（通过检查目录）
                account_tier=""
                if [ -f "../account/trial/${account_name}.json" ]; then
                    account_tier="trial"
                    tier_color=$YELLOW
                elif [ -f "../account/medium/${account_name}.json" ]; then
                    account_tier="medium"
                    tier_color=$GREEN
                elif [ -f "../account/high/${account_name}.json" ]; then
                    account_tier="high"
                    tier_color=$PURPLE
                elif [ -f "../account/supreme/${account_name}.json" ]; then
                    account_tier="supreme"
                    tier_color=$CYAN
                fi
                
                if [ ! -z "$account_tier" ]; then
                    refresh_failed_count=$((refresh_failed_count + 1))
                    
                    # 获取最后失败时间
                    cooldown_key="refresh_cooldown:${account_name}"
                    last_failure=$(redis-cli -p $REDIS_PORT get "$cooldown_key" 2>/dev/null)
                    
                    if [ ! -z "$last_failure" ]; then
                        # 计算距离上次失败的时间
                        current_time=$(date +%s000)
                        time_diff=$((current_time - last_failure))
                        hours_ago=$((time_diff / 3600000))
                        minutes_ago=$(((time_diff % 3600000) / 60000))
                        
                        if [ $hours_ago -gt 0 ]; then
                            time_display="${hours_ago}h ${minutes_ago}m ago"
                        else
                            time_display="${minutes_ago}m ago"
                        fi
                    else
                        time_display="unknown"
                    fi
                    
                    # 检查是否在黑名单
                    blacklist_key="account_blacklist:${account_tier}:${account_name}"
                    is_blacklisted=$(redis-cli -p $REDIS_PORT exists "$blacklist_key" 2>/dev/null)
                    
                    if [ "$is_blacklisted" = "1" ]; then
                        status_text="BLACKLISTED"
                        status_color=$RED
                    else
                        status_text="REFRESH LIMIT"
                        status_color=$YELLOW
                    fi
                    
                    printf "  ${tier_color}[${account_tier^^}]${NC} %-25s: ${status_color}%s${NC} (${attempt_count}/3 attempts, last: %s)\n" \
                        "$account_name" "$status_text" "$time_display"
                fi
            fi
        done
    fi
done


echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "                    $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"