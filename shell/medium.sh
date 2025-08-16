#!/bin/bash

# 客户端密钥生成脚本 - Medium版本
# 用于生成 sk-cli-v1-xxx 格式的客户端密钥并注册到系统
# 支持绑定到特定账户
# 同时生成Medium产品JSON文件用于销售管理

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
ACCOUNT_DIR="../account"
PRODUCT_FILE="../product/medium.json"
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

# 检查账户是否存在（支持分级目录结构）
check_account() {
    local account_name=$1
    local account_file=""
    
    # 首先在medium子目录中查找
    if [ -f "${ACCOUNT_DIR}/medium/${account_name}.json" ]; then
        account_file="${ACCOUNT_DIR}/medium/${account_name}.json"
    # 然后在根目录中查找（向后兼容）
    elif [ -f "${ACCOUNT_DIR}/${account_name}.json" ]; then
        account_file="${ACCOUNT_DIR}/${account_name}.json"
    # 最后在所有子目录中递归查找
    else
        account_file=$(find "${ACCOUNT_DIR}" -name "${account_name}.json" -type f 2>/dev/null | head -1)
    fi
    
    if [ -z "$account_file" ] || [ ! -f "$account_file" ]; then
        echo -e "${RED}Error: Account file not found for: ${account_name}${NC}"
        echo "Available accounts:"
        # 递归显示所有级别的账户
        find "${ACCOUNT_DIR}" -name "*.json" -type f 2>/dev/null | while read file; do
            local name=$(basename "$file" .json)
            local level=$(basename "$(dirname "$file")")
            if [ "$level" = "account" ]; then
                echo "  - $name"
            else
                echo "  - $name ($level)"
            fi
        done
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
    local use_pool=$4  # "pool" 或具体账户名
    local expiry_days=${5:-30}  # 默认30天有效期
    local current_time=$(date +%s000)  # 毫秒时间戳
    local expiry_time=$(date -d "+${expiry_days} days" +%s000)  # 过期时间
    
    
    # 如果产品文件不存在，创建一个空的JSON文件
    if [ ! -f "$PRODUCT_FILE" ]; then
        echo "{}" > "$PRODUCT_FILE"
    fi
    
    # 使用Python添加新的密钥映射并保存到Redis和产品文件
    python3 - <<EOF
import json
import sys
import redis
from datetime import datetime, timezone, timedelta

key = "$client_key"
client_name = "$client_name"
account_name = "$account_name"
timestamp = $current_time
expiry_timestamp = $expiry_time
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
    "tier": "medium", 
    "status": "unsold",
    "soldAt": None,
    "orderNo": None,
    "expiresAt": None,
    "expiresDate": None
}

# 保存产品文件
with open(PRODUCT_FILE, "w") as f:
    json.dump(products, f, indent=2)

print(f"Medium product record added to {PRODUCT_FILE}")

# 保存到Redis
if redis_connected:
    try:
        # 保存到客户端密钥映射
        redis_key = f"client_keys:{key}"
        r.hset(redis_key, mapping={
            "client_name": client_name,
            "account_name": account_name if account_name != "pool" else "medium_pool",
            "use_pool": "true" if account_name == "pool" else "false",
            "tier": "medium",
            "created_at": timestamp,
            "created_date": datetime.now(timezone(timedelta(hours=8))).isoformat(),
            "expires_at": str(expiry_timestamp),
            "expires_date": datetime.fromtimestamp(expiry_timestamp/1000).isoformat(),
            "active": "true",
            "status": "unsold"  # 添加销售状态
            # Medium级别无请求次数限制
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
                'tier': 'medium',
                'createdAt': timestamp,
                'expiresAt': None,
                'status': 'unsold'
            })
            r.set(account_key, json.dumps(account_info))
        
        # 添加到产品Redis列表
        medium_redis_key = f"medium_products:{key}"
        r.hset(medium_redis_key, mapping={
            "account": account_name,
            "tier": "medium",
            "status": "unsold",
            "sold_at": "",
            "order_no": "",
            "created_at": timestamp,
            "expires_at": str(expiry_timestamp)
        })
        
        print(f"Key saved to Redis under client_keys:{key}")
        print(f"Key added to account {account_name} in Redis")
        print(f"Medium product record saved to Redis under medium_products:{key}")
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
    echo "Usage: $0 [account-name|pool] [expiry-days]"
    echo ""
    echo "Parameters:"
    echo "  account-name    Account to bind the key to, or 'pool' for account pool (default: pool)"
    echo "  expiry-days     Key validity in days (default: 30)"
    echo ""
    echo "Examples:"
    echo "  $0                               # Use account pool (default)"
    echo "  $0 pool                          # Explicitly use account pool"
    echo "  $0 pool 60                       # Account pool with 60 days expiry"
    echo "  $0 jasonlucy8160-outlook        # Bind to specific account"
    echo "  $0 jasonlucy8160-outlook 60     # Specific account with 60 days expiry"
    echo ""
    echo "Account Pool Mode:"
    echo "  When using 'pool' or no parameters, the key will randomly select"
    echo "  an account from /account/medium/ directory for each request."
    echo ""
    echo "Available accounts:"
    find "${ACCOUNT_DIR}" -name "*.json" -type f 2>/dev/null | while read file; do
        local name=$(basename "$file" .json)
        local level=$(basename "$(dirname "$file")")
        if [ "$level" = "account" ]; then
            echo "  - $name"
        else
            echo "  - $name ($level)"
        fi
    done
}

# 主程序
main() {
    echo -e "${GREEN}=== Claude Proxy Medium Product Key Generator ===${NC}"
    echo ""
    
    # 确保目录存在
    ensure_directories
    
    # 获取账户名称
    local account_name=""
    local use_pool="false"
    
    if [ $# -eq 0 ]; then
        # 无参数，默认使用账户池
        account_name="pool"
        use_pool="true"
        echo -e "${BLUE}Using account pool mode for Medium tier (default)${NC}"
        local expiry_days=30
    elif [ $# -ge 1 ]; then
        # 从命令行参数获取账户名
        account_name=$1
        
        # 检查是否是帮助参数
        if [ "$account_name" == "-h" ] || [ "$account_name" == "--help" ]; then
            show_usage
            exit 0
        fi
        
        # 检查是否使用账户池
        if [ "$account_name" == "pool" ]; then
            use_pool="true"
            echo -e "${BLUE}Using account pool mode for Medium tier${NC}"
        fi
        
        # 检查第二个参数是否为有效期天数
        local expiry_days=30  # 默认30天
        if [ $# -eq 2 ]; then
            if [[ $2 =~ ^[0-9]+$ ]] && [ $2 -gt 0 ]; then
                expiry_days=$2
            else
                echo -e "${RED}Error: Expiry days must be a positive integer${NC}"
                exit 1
            fi
        fi
    else
        # 交互式选择账户
        echo "Available accounts:"
        
        # 使用数组收集所有账户文件
        local account_files=()
        while IFS= read -r -d '' file; do
            account_files+=("$file")
        done < <(find "${ACCOUNT_DIR}" -name "*.json" -type f -print0 2>/dev/null)
        
        if [ ${#account_files[@]} -eq 0 ]; then
            echo -e "${RED}Error: No accounts found in ${ACCOUNT_DIR}${NC}"
            exit 1
        fi
        
        local accounts=()
        local account_names=()
        for file in "${account_files[@]}"; do
            local name=$(basename "$file" .json)
            local level=$(basename "$(dirname "$file")")
            account_names+=("$name")  # 存储实际的账户名
            if [ "$level" = "account" ]; then
                accounts+=("$name")
            else
                accounts+=("$name ($level)")
            fi
        done
        
        for i in "${!accounts[@]}"; do
            echo "  $((i+1)). ${accounts[$i]}"
        done
        
        echo ""
        read -p "Select account number (1-${#accounts[@]}): " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ $selection -ge 1 ] && [ $selection -le ${#accounts[@]} ]; then
            account_name=${account_names[$((selection-1))]}  # 使用实际的账户名
        else
            echo -e "${RED}Invalid selection${NC}"
            exit 1
        fi
    fi
    
    # 检查账户是否存在（如果不是账户池模式）
    if [ "$use_pool" != "true" ] && [ "$account_name" != "pool" ]; then
        if ! check_account "$account_name"; then
            exit 1
        fi
    fi
    
    echo -e "${BLUE}Selected account: ${account_name}${NC}"
    echo ""
    
    # 自动生成客户端名称
    if [ "$use_pool" == "true" ] || [ "$account_name" == "pool" ]; then
        client_name="MediumPool_$(TZ='Asia/Shanghai' date +%Y%m%d_%H%M%S)"
    else
        client_name="${account_name}_Medium_$(TZ='Asia/Shanghai' date +%Y%m%d_%H%M%S)"
    fi
    
    # 生成新密钥（64字符长度）
    new_key=$(generate_key)
    
    echo ""
    echo -e "${YELLOW}Generating new medium product key for account: ${account_name}...${NC}"
    
    # 添加到映射文件、Redis和产品文件
    local display_account="$account_name"
    if [ "$use_pool" == "true" ] || [ "$account_name" == "pool" ]; then
        account_name="pool"  # 传递"pool"标识使用账户池
        display_account="Account Pool (Dynamic allocation with 24-hour rotation)"
    fi
    
    if add_key_mapping "$new_key" "$client_name" "$account_name" "$use_pool" "${expiry_days:-30}"; then
        echo -e "${GREEN}✓ Medium product key successfully generated and registered${NC}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}Account:${NC}      $display_account"
        echo -e "${GREEN}Product Tier:${NC} Medium"
        echo -e "${GREEN}Product Name:${NC} $client_name"
        echo -e "${GREEN}Product Key:${NC}  $new_key"
        echo -e "${GREEN}Status:${NC}       unsold"
        echo -e "${GREEN}Created:${NC}      $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S') (北京时间)"
        echo -e "${GREEN}Expires:${NC}      $(TZ='Asia/Shanghai' date -d "+${expiry_days:-30} days" '+%Y-%m-%d %H:%M:%S') (北京时间)"
        echo -e "${GREEN}Valid Days:${NC}   ${expiry_days:-30} days"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Files Updated:"
        echo "─────────────────────────────────────────────────────────────────────"
        echo "✓ Product file: ../product/medium.json"
        echo "✓ Redis: client_keys:${new_key}"
        echo "✓ Redis: medium_products:${new_key}"
        echo ""
        if [ "$use_pool" == "true" ] || [ "$account_name" == "pool" ]; then
            echo "This key uses Medium account pool with slot-based allocation"
            echo "Accounts will rotate every 24 hours within available slots"
        else
            echo "This key is bound to account: $account_name"
        fi
        echo "Product tier: Medium"
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
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Generated medium product key for account $account_name: $new_key (Product: $client_name)" >> ../logs/generated-keys.log
        
    else
        echo -e "${RED}✗ Failed to register medium product key${NC}"
        exit 1
    fi
}

# 运行主程序
main "$@"