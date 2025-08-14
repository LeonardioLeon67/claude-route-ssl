#!/bin/bash

# 客户端密钥生成脚本 - High版本
# 用于生成 sk-cli-v1-xxx 格式的客户端密钥并注册到系统
# 支持绑定到特定账户
# 同时生成High产品JSON文件用于销售管理

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
ACCOUNT_DIR="../account"
PRODUCT_FILE="../product/high.json"
REDIS_PORT=6380

# 切换到脚本所在目录
cd "$(dirname "$0")"

# 生成随机密钥 (64字符)
generate_key() {
    # 生成64字节的随机字符串
    local random_string=$(openssl rand -hex 32)
    echo "sk-cli-v1-${random_string}"
}

# 检查并创建目录
ensure_directories() {
    if [ ! -d "../product" ]; then
        mkdir -p ../product
        echo -e "${GREEN}Created product directory${NC}"
    fi
}

# 检查账户是否存在
check_account() {
    local account_name=$1
    local account_file="${ACCOUNT_DIR}/${account_name}.json"
    
    if [ ! -f "$account_file" ]; then
        echo -e "${RED}Error: Account file not found: ${account_file}${NC}"
        echo "Available accounts:"
        ls -1 "${ACCOUNT_DIR}/"*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$//' | sed 's/^/  - /'
        return 1
    fi
    
    # 检查是否包含有效的OAuth credentials
    local has_oauth=$(cat "$account_file" | grep -o '"claudeAiOauth"' | wc -l)
    if [ "$has_oauth" -eq 0 ]; then
        echo -e "${RED}Error: No valid OAuth credentials found in account file${NC}"
        return 1
    fi
    
    return 0
}

# 添加密钥到映射文件、Redis和产品文件
add_key_mapping() {
    local client_key=$1
    local client_name=$2
    local account_name=$3
    local current_time=$(date +%s000)  # 毫秒时间戳
    
    
    # 如果产品文件不存在，创建一个空的JSON文件
    if [ ! -f "$PRODUCT_FILE" ]; then
        echo "{}" > "$PRODUCT_FILE"
    fi
    
    # 使用Python添加新的密钥映射并保存到Redis和产品文件
    python3 - <<EOF
import json
import sys
import redis
from datetime import datetime

key = "$client_key"
client_name = "$client_name"
account_name = "$account_name"
timestamp = $current_time
PRODUCT_FILE = "$PRODUCT_FILE"

# 连接Redis
try:
    r = redis.Redis(host='localhost', port=$REDIS_PORT, decode_responses=True)
    r.ping()
    redis_connected = True
    print(f"Connected to Redis on port $REDIS_PORT")
except:
    redis_connected = False
    print("Warning: Could not connect to Redis, will only save to file")

# Note: 废弃的key-mappings.json文件功能已移除，只使用Redis和产品文件

# 加载产品文件
try:
    with open(PRODUCT_FILE, "r") as f:
        products = json.load(f)
except:
    products = {}

# 添加新的产品记录
products[key] = {
    "account": account_name,
    "tier": "high",
    "status": "unsold",
    "soldAt": "NULL",
    "orderNo": "NULL"
}

# 保存产品文件
with open(PRODUCT_FILE, "w") as f:
    json.dump(products, f, indent=2)

print(f"High product record added to {PRODUCT_FILE}")

# 保存到Redis
if redis_connected:
    try:
        # 保存到客户端密钥映射
        redis_key = f"client_keys:{key}"
        r.hset(redis_key, mapping={
            "client_name": client_name,
            "account_name": account_name,
            "tier": "high",
            "created_at": timestamp,
            "created_date": datetime.now().isoformat(),
            "active": "true",
            "status": "unsold",  # 添加销售状态
            # High级别分模型限制
            "opus_4_per_5_hours": "45",  # Opus 4.1 每5小时45次
            "opus_4_current_window_start": str(timestamp),
            "opus_4_current_window_requests": "0",
            "sonnet_4_per_5_hours": "180",  # Sonnet 4 每5小时180次  
            "sonnet_4_current_window_start": str(timestamp),
            "sonnet_4_current_window_requests": "0"
        })
        
        # 添加到账户的密钥列表
        account_keys_key = f"accounts:{account_name}:keys"
        r.sadd(account_keys_key, key)
        
        # 更新账户信息，添加此密钥
        account_key = f"accounts:{account_name}"
        account_data = r.get(account_key)
        if account_data:
            import json
            account_info = json.loads(account_data)
            if 'clientKeys' not in account_info:
                account_info['clientKeys'] = []
            account_info['clientKeys'].append({
                'key': key,
                'name': client_name,
                'tier': 'high',
                'createdAt': timestamp,
                'status': 'unsold'
            })
            r.set(account_key, json.dumps(account_info))
        
        # 添加到产品Redis列表
        high_redis_key = f"high_products:{key}"
        r.hset(high_redis_key, mapping={
            "account": account_name,
            "tier": "high",
            "status": "unsold",
            "sold_at": "",
            "order_no": "",
            "created_at": timestamp
        })
        
        print(f"Key saved to Redis under client_keys:{key}")
        print(f"Key added to account {account_name} in Redis")
        print(f"High product record saved to Redis under high_products:{key}")
    except Exception as e:
        print(f"Warning: Could not save to Redis: {e}")

print("Success")
EOF
    
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# 显示使用说明
show_usage() {
    echo "Usage: $0 [account-name]"
    echo ""
    echo "Examples:"
    echo "  $0 jasonlucy8160-outlook    # Generate high key for specific account"
    echo "  $0                           # Interactive mode (select account)"
    echo ""
    echo "Available accounts:"
    ls -1 "${ACCOUNT_DIR}/"*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$//' | sed 's/^/  - /'
}

# 主程序
main() {
    echo -e "${GREEN}=== Claude Proxy High Product Key Generator ===${NC}"
    echo ""
    
    # 确保目录存在
    ensure_directories
    
    # 获取账户名称
    local account_name=""
    
    if [ $# -eq 1 ]; then
        # 从命令行参数获取账户名
        account_name=$1
        
        # 检查是否是帮助参数
        if [ "$account_name" == "-h" ] || [ "$account_name" == "--help" ]; then
            show_usage
            exit 0
        fi
    else
        # 交互式选择账户
        echo "Available accounts:"
        local accounts=($(ls -1 "${ACCOUNT_DIR}/"*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$//'))
        
        if [ ${#accounts[@]} -eq 0 ]; then
            echo -e "${RED}Error: No accounts found in ${ACCOUNT_DIR}${NC}"
            exit 1
        fi
        
        for i in "${!accounts[@]}"; do
            echo "  $((i+1)). ${accounts[$i]}"
        done
        
        echo ""
        read -p "Select account number (1-${#accounts[@]}): " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ $selection -ge 1 ] && [ $selection -le ${#accounts[@]} ]; then
            account_name=${accounts[$((selection-1))]}
        else
            echo -e "${RED}Invalid selection${NC}"
            exit 1
        fi
    fi
    
    # 检查账户是否存在
    if ! check_account "$account_name"; then
        exit 1
    fi
    
    echo -e "${BLUE}Selected account: ${account_name}${NC}"
    echo ""
    
    # 自动生成客户端名称
    client_name="${account_name}_High_$(date +%Y%m%d_%H%M%S)"
    
    # 生成新密钥（64字符长度）
    new_key=$(generate_key)
    
    echo ""
    echo -e "${YELLOW}Generating new high product key for account: ${account_name}...${NC}"
    
    # 添加到映射文件、Redis和产品文件
    if add_key_mapping "$new_key" "$client_name" "$account_name"; then
        echo -e "${GREEN}✓ High product key successfully generated and registered${NC}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}Account:${NC}      $account_name"
        echo -e "${GREEN}Product Tier:${NC} High"
        echo -e "${GREEN}Product Name:${NC} $client_name"
        echo -e "${GREEN}Product Key:${NC}  $new_key"
        echo -e "${GREEN}Status:${NC}       unsold"
        echo -e "${GREEN}Created:${NC}      $(date '+%Y-%m-%d %H:%M:%S')"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Files Updated:"
        echo "─────────────────────────────────────────────────────────────────────"
        echo "✓ Product file: ../product/high.json"
        echo "✓ Redis: client_keys:${new_key}"
        echo "✓ Redis: high_products:${new_key}"
        echo ""
        echo "This key is bound to account: $account_name"
        echo "Product tier: High"
        echo "Status: unsold (ready for sale)"
        echo ""
        echo "Client Configuration:"
        echo "─────────────────────────────────────────────────────────────────────"
        echo "Base URL: https://direct.816981.xyz"
        echo "API Key:  $new_key"
        echo ""
        echo "Usage Examples:"
        echo "─────────────────────────────────────────────────────────────────────"
        echo "1. Using x-api-key header:"
        echo "   curl -X POST https://direct.816981.xyz/v1/messages \\"
        echo "     -H \"x-api-key: $new_key\" \\"
        echo "     -H \"Content-Type: application/json\" \\"
        echo "     -d '{\"model\": \"claude-3-5-haiku-20241022\", ...}'"
        echo ""
        echo "2. Using Authorization header:"
        echo "   curl -X POST https://direct.816981.xyz/v1/messages \\"
        echo "     -H \"Authorization: Bearer $new_key\" \\"
        echo "     -H \"Content-Type: application/json\" \\"
        echo "     -d '{\"model\": \"claude-3-5-haiku-20241022\", ...}'"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # 保存到日志文件
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Generated high product key for account $account_name: $new_key (Product: $client_name)" >> ../logs/generated-keys.log
        
    else
        echo -e "${RED}✗ Failed to register high product key${NC}"
        exit 1
    fi
}

# 运行主程序
main "$@"