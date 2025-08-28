#!/bin/bash

# 客户端密钥生成脚本 - Trial版本
# 用于生成 sk-cli-v1-xxx 格式的客户端密钥并注册到系统
# Trial版本固定使用账户池，固定1天有效期
# 同时生成Trial产品JSON文件用于销售管理

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
ACCOUNT_DIR="../account"
PRODUCT_FILE="../product/trial.json"
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

# 添加密钥到映射文件、Redis和产品文件
add_key_mapping() {
    local client_key=$1
    local client_name=$2
    local current_time=$(date +%s000)  # 毫秒时间戳
    # 未售出的产品不设置过期时间
    
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

# 加载产品文件
try:
    with open(PRODUCT_FILE, "r") as f:
        products = json.load(f)
except:
    products = {}

# 添加新的产品记录
products[key] = {
    "account": "pool",
    "tier": "trial", 
    "status": "unsold",
    "soldAt": None,
    "orderNo": None,
    "expiresAt": None,
    "expiresDate": None
}

# 保存产品文件
with open(PRODUCT_FILE, "w") as f:
    json.dump(products, f, indent=2)

print(f"Trial product record added to {PRODUCT_FILE}")

# 保存到Redis
if redis_connected:
    try:
        # 保存到客户端密钥映射
        redis_key = f"client_keys:{key}"
        r.hset(redis_key, mapping={
            "client_name": client_name,
            "account_name": "trial_pool",
            "use_pool": "true",
            "tier": "trial",
            "created_at": timestamp,
            "created_date": datetime.now(timezone(timedelta(hours=8))).isoformat(),
            "expires_at": "",
            "expires_date": "",
            "active": "true",
            "status": "unsold",  # 添加销售状态
            # Trial级别Sonnet模型限制
            "sonnet_4_per_5_hours": "42",  # Sonnet 4 每5小时42次
            "sonnet_4_current_window_start": str(timestamp),
            "sonnet_4_current_window_requests": "0"
        })
        
        # 添加到账户的密钥列表
        account_keys_key = f"accounts:pool:keys"
        r.sadd(account_keys_key, key)
        
        # 添加到产品Redis列表
        trial_redis_key = f"trial_products:{key}"
        r.hset(trial_redis_key, mapping={
            "account": "pool",
            "tier": "trial",
            "status": "unsold",
            "sold_at": "",
            "order_no": "",
            "created_at": timestamp,
            "expires_at": ""
        })
        
        print(f"Key saved to Redis under client_keys:{key}")
        print(f"Key added to trial pool in Redis")
        print(f"Trial product record saved to Redis under trial_products:{key}")
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

# 主程序
main() {
    echo -e "${GREEN}=== Claude Proxy Trial Product Key Generator ===${NC}"
    echo ""
    
    # Trial版本不接受任何参数
    if [ $# -ne 0 ]; then
        echo -e "${RED}Error: Trial key generation does not accept any parameters${NC}"
        echo -e "${YELLOW}Usage: $0${NC}"
        echo -e "${YELLOW}Trial keys are fixed at 1 day validity with account pool mode${NC}"
        exit 1
    fi
    
    # 确保目录存在
    ensure_directories
    
    echo -e "${BLUE}Creating Trial tier key (account pool mode, 1 day validity after sale)${NC}"
    echo ""
    
    # 自动生成客户端名称
    client_name="TrialPool_$(TZ='Asia/Shanghai' date +%Y%m%d_%H%M%S)"
    
    # 生成新密钥（64字符长度）
    new_key=$(generate_key)
    
    echo -e "${YELLOW}Generating new trial product key...${NC}"
    
    # 添加到映射文件、Redis和产品文件
    if add_key_mapping "$new_key" "$client_name"; then
        echo -e "${GREEN}✓ Trial product key successfully generated and registered${NC}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}Account:${NC}      Account Pool (Dynamic allocation)"
        echo -e "${GREEN}Product Tier:${NC} Trial"
        echo -e "${GREEN}Product Name:${NC} $client_name"
        echo -e "${GREEN}Product Key:${NC}  $new_key"
        echo -e "${GREEN}Status:${NC}       unsold"
        echo -e "${GREEN}Created:${NC}      $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')"
        echo -e "${GREEN}Expires:${NC}      $(TZ='Asia/Shanghai' date -d "+1 days" '+%Y-%m-%d %H:%M:%S')"
        echo -e "${GREEN}Valid Days:${NC}   1 day"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Files Updated:"
        echo "─────────────────────────────────────────────────────────────────────"
        echo "✓ Product file: ../product/trial.json"
        echo "✓ Redis: client_keys:${new_key}"
        echo "✓ Redis: trial_products:${new_key}"
        echo ""
        echo "This key uses Trial account pool with slot-based allocation"
        echo "Trial tier features:"
        echo "  - Only Sonnet models allowed (35 requests per 5 hours)"
        echo "  - 7 slots per account"
        echo "  - 1 day validity (after sale)"
        echo ""
        echo "Product tier: Trial"
        echo "Status: unsold (ready for sale)"
        echo ""
        echo "Client Configuration:"
        echo "─────────────────────────────────────────────────────────────────────"
        echo "Base URL: https://api.justprompt.pro"
        echo "API Key:  $new_key"
        echo ""
        echo "Usage Examples:"
        echo "─────────────────────────────────────────────────────────────────────"
        echo "1. Using x-api-key header:"
        echo "   curl -X POST https://api.justprompt.pro/v1/messages \\"
        echo "     -H \"x-api-key: $new_key\" \\"
        echo "     -H \"Content-Type: application/json\" \\"
        echo "     -d '{\"model\": \"claude-3-5-haiku-20241022\", ...}'"
        echo ""
        echo "2. Using Authorization header:"
        echo "   curl -X POST https://api.justprompt.pro/v1/messages \\"
        echo "     -H \"Authorization: Bearer $new_key\" \\"
        echo "     -H \"Content-Type: application/json\" \\"
        echo "     -d '{\"model\": \"claude-3-5-haiku-20241022\", ...}'"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # 保存到日志文件
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Generated trial product key: $new_key (Product: $client_name)" >> ../logs/generated-keys.log
        
    else
        echo -e "${RED}✗ Failed to register trial product key${NC}"
        exit 1
    fi
}

# 运行主程序
main "$@"