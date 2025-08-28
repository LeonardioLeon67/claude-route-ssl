#!/bin/bash

# Claude Route SSL Project - 状态检查脚本
# 简化版本，快速检查所有核心服务状态

PROJECT_DIR="/home/leon/claude-route-ssl/claude-route-ssl"
PROJECT_NAME="claude-proxy"
REDIS_PORT="6380"

echo "📊 Claude Route SSL - 服务状态"
echo "================================"
echo "🕐 检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 检查项目目录
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ 项目目录不存在: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

# Step 1: PM2进程状态
echo "📋 PM2进程状态:"
echo "--------------------------------"
if command -v pm2 &> /dev/null; then
    if pm2 describe $PROJECT_NAME > /dev/null 2>&1; then
        PM2_STATUS=$(pm2 describe $PROJECT_NAME | grep -E "status.*online" && echo "✅ 运行中" || echo "❌ 已停止")
        echo "$PM2_STATUS - $PROJECT_NAME"
        
        # 显示简要信息
        pm2 list | head -1
        pm2 list | grep $PROJECT_NAME 2>/dev/null || echo "进程未在列表中显示"
        
        # 显示最新日志
        echo ""
        echo "🔍 最新日志 (3条):"
        pm2 logs $PROJECT_NAME --lines 3 --nostream 2>/dev/null | tail -3 || echo "无法获取日志"
    else
        echo "❌ PM2进程不存在: $PROJECT_NAME"
    fi
else
    echo "❌ PM2未安装"
fi
echo ""

# Step 2: Redis服务状态
echo "📋 Redis服务状态:"
echo "--------------------------------"
if pgrep -f "redis-server.*$REDIS_PORT" > /dev/null; then
    REDIS_PID=$(pgrep -f "redis-server.*$REDIS_PORT")
    echo "✅ Redis运行中 (PID: $REDIS_PID, 端口: $REDIS_PORT)"
    
    # 测试连接
    if redis-cli -p $REDIS_PORT ping 2>/dev/null | grep -q "PONG"; then
        echo "✅ Redis连接正常"
        REDIS_CLIENTS=$(redis-cli -p $REDIS_PORT info clients 2>/dev/null | grep connected_clients | cut -d: -f2 | tr -d '\r' || echo "N/A")
        echo "📊 连接数: $REDIS_CLIENTS"
    else
        echo "❌ Redis连接失败"
    fi
elif systemctl is-active redis-server > /dev/null 2>&1; then
    echo "⚠️  系统Redis服务运行中，但项目Redis($REDIS_PORT)未运行"
else
    echo "❌ Redis服务未运行"
fi
echo ""

# Step 3: Nginx代理状态
echo "📋 Nginx代理状态:"
echo "--------------------------------"
if systemctl is-active nginx > /dev/null 2>&1; then
    echo "✅ Nginx服务运行中"
    
    # 检查配置
    if [ -L "/etc/nginx/sites-enabled/api.justprompt.pro.conf" ]; then
        echo "✅ 项目配置已启用: api.justprompt.pro"
    else
        echo "⚠️  项目配置未启用"
    fi
    
    # 测试配置
    if sudo nginx -t > /dev/null 2>&1; then
        echo "✅ Nginx配置正确"
    else
        echo "❌ Nginx配置有误"
    fi
else
    echo "❌ Nginx服务未运行"
fi
echo ""

# Step 4: 端口监听状态
echo "📋 端口监听状态:"
echo "--------------------------------"
# 使用lsof或ss检查端口
if command -v lsof &> /dev/null; then
    if lsof -i :8080 > /dev/null 2>&1; then
        echo "✅ 端口8080正在监听"
        lsof -i :8080 | grep LISTEN | head -1
    else
        echo "❌ 端口8080未监听"
    fi
    
    if lsof -i :$REDIS_PORT > /dev/null 2>&1; then
        echo "✅ 端口$REDIS_PORT正在监听"
        lsof -i :$REDIS_PORT | grep LISTEN | head -1
    else
        echo "❌ 端口$REDIS_PORT未监听"
    fi
elif command -v ss &> /dev/null; then
    if ss -tuln | grep -q ":8080 "; then
        echo "✅ 端口8080正在监听"
    else
        echo "❌ 端口8080未监听"
    fi
    
    if ss -tuln | grep -q ":$REDIS_PORT "; then
        echo "✅ 端口$REDIS_PORT正在监听"
    else
        echo "❌ 端口$REDIS_PORT未监听"
    fi
else
    echo "⚠️  无法检查端口状态 (lsof/ss不可用)"
fi
echo ""

# Step 5: 服务连通性测试
echo "📋 服务连通性测试:"
echo "--------------------------------"

# 测试本地HTTP
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080 2>/dev/null | grep -q "401\|200"; then
    echo "✅ 本地HTTP服务正常 (127.0.0.1:8080)"
else
    echo "❌ 本地HTTP服务无响应"
fi

# 测试HTTPS
if curl -s -o /dev/null -w "%{http_code}" https://api.justprompt.pro 2>/dev/null | grep -q "401\|200"; then
    RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" https://api.justprompt.pro 2>/dev/null || echo "N/A")
    echo "✅ HTTPS访问正常 (api.justprompt.pro) - ${RESPONSE_TIME}s"
else
    echo "❌ HTTPS访问失败"
fi
echo ""

# Step 6: SSL证书状态
echo "📋 SSL证书状态:"
echo "--------------------------------"
CERT_PATH="/etc/letsencrypt/live/api.justprompt.pro/fullchain.pem"
if [ -f "$CERT_PATH" ]; then
    if command -v openssl &> /dev/null; then
        CERT_EXPIRY=$(sudo openssl x509 -enddate -noout -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)
        if [ -n "$CERT_EXPIRY" ]; then
            DAYS_LEFT=$(echo $(( ($(date -d "$CERT_EXPIRY" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 )))
            echo "✅ SSL证书存在"
            echo "📅 到期时间: $CERT_EXPIRY"
            echo "⏰ 剩余天数: $DAYS_LEFT 天"
            
            if [ "$DAYS_LEFT" -lt 30 ] && [ "$DAYS_LEFT" -gt 0 ]; then
                echo "⚠️  证书即将过期，需要续签"
            elif [ "$DAYS_LEFT" -le 0 ]; then
                echo "❌ 证书已过期！"
            fi
        else
            echo "⚠️  SSL证书文件存在但无法读取"
        fi
    else
        echo "⚠️  SSL证书存在但openssl不可用，无法检查详情"
    fi
else
    echo "❌ SSL证书不存在"
fi
echo ""

# Step 7: Token刷新定时器状态
echo "📋 Token刷新定时器状态:"
echo "--------------------------------"
# 获取所有刷新计划
SCHEDULE_KEYS=$(redis-cli -p $REDIS_PORT keys "refresh_schedules:*" 2>/dev/null | sort)
if [ -z "$SCHEDULE_KEYS" ]; then
    echo "⚠️  没有设置刷新计划"
else
    ACTIVE_COUNT=0
    for KEY in $SCHEDULE_KEYS; do
        ACCOUNT=$(echo $KEY | cut -d':' -f2)
        SCHEDULE=$(redis-cli -p $REDIS_PORT get "$KEY" 2>/dev/null)
        
        if [ ! -z "$SCHEDULE" ]; then
            REFRESH_AT=$(echo $SCHEDULE | jq -r '.refreshAt' 2>/dev/null)
            STATUS=$(echo $SCHEDULE | jq -r '.status' 2>/dev/null)
            
            if [ "$REFRESH_AT" != "null" ] && [ ! -z "$REFRESH_AT" ]; then
                NOW=$(date +%s)
                REFRESH_SEC=$((REFRESH_AT/1000))
                REMAINING=$((REFRESH_SEC - NOW))
                
                if [ $REMAINING -gt 0 ]; then
                    HOURS=$((REMAINING / 3600))
                    MINUTES=$(((REMAINING % 3600) / 60))
                    ((ACTIVE_COUNT++))
                fi
            fi
        fi
    done
    echo "✅ 活跃定时器: ${ACTIVE_COUNT}个"
    
    # 显示最近的刷新计划
    NEXT_REFRESH=""
    MIN_REMAINING=999999999
    for KEY in $SCHEDULE_KEYS; do
        SCHEDULE=$(redis-cli -p $REDIS_PORT get "$KEY" 2>/dev/null)
        if [ ! -z "$SCHEDULE" ]; then
            REFRESH_AT=$(echo $SCHEDULE | jq -r '.refreshAt' 2>/dev/null)
            ACCOUNT_NAME=$(echo $SCHEDULE | jq -r '.accountName' 2>/dev/null)
            
            if [ "$REFRESH_AT" != "null" ] && [ ! -z "$REFRESH_AT" ]; then
                NOW=$(date +%s)
                REFRESH_SEC=$((REFRESH_AT/1000))
                REMAINING=$((REFRESH_SEC - NOW))
                
                if [ $REMAINING -gt 0 ] && [ $REMAINING -lt $MIN_REMAINING ]; then
                    MIN_REMAINING=$REMAINING
                    HOURS=$((REMAINING / 3600))
                    MINUTES=$(((REMAINING % 3600) / 60))
                    NEXT_REFRESH="$ACCOUNT_NAME (${HOURS}h${MINUTES}m后)"
                fi
            fi
        fi
    done
    
    if [ ! -z "$NEXT_REFRESH" ]; then
        echo "⏰ 下次刷新: $NEXT_REFRESH"
    fi
fi
echo ""

# Step 8: 资源使用情况
echo "📋 资源使用情况:"
echo "--------------------------------"
if pgrep -f "$PROJECT_NAME" > /dev/null; then
    echo "🔍 Claude相关进程资源使用:"
    ps aux | grep -E "($PROJECT_NAME|proxy-server)" | grep -v grep | while read line; do
        echo "   $(echo $line | awk '{printf "PID:%s CPU:%s%% MEM:%s%% CMD:%s\n", $2, $3, $4, $11}')"
    done
else
    echo "⚠️  未发现Claude相关进程"
fi

echo ""
echo "💾 系统资源:"
echo "   内存: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "   磁盘: $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
echo ""

# 总结
echo "📋 服务状态总结:"
echo "================================"

# 检查各项服务状态
PM2_OK="❌"
REDIS_OK="❌"  
NGINX_OK="❌"
HTTP_OK="❌"
HTTPS_OK="❌"

if pm2 describe $PROJECT_NAME > /dev/null 2>&1 && pm2 describe $PROJECT_NAME | grep -q "online"; then
    PM2_OK="✅"
fi

if pgrep -f "redis-server.*$REDIS_PORT" > /dev/null; then
    REDIS_OK="✅"
fi

if systemctl is-active nginx > /dev/null 2>&1; then
    NGINX_OK="✅"
fi

if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080 2>/dev/null | grep -q "401\|200"; then
    HTTP_OK="✅"
fi

if curl -s -o /dev/null -w "%{http_code}" https://api.justprompt.pro 2>/dev/null | grep -q "401\|200"; then
    HTTPS_OK="✅"
fi

echo "核心服务状态:"
echo "   $PM2_OK PM2进程 ($PROJECT_NAME)"
echo "   $REDIS_OK Redis服务 (端口$REDIS_PORT)" 
echo "   $NGINX_OK Nginx代理服务"
echo "   $HTTP_OK 本地HTTP连接"
echo "   $HTTPS_OK HTTPS外部访问"

echo ""
if [[ "$PM2_OK" == "✅" && "$REDIS_OK" == "✅" && "$NGINX_OK" == "✅" && "$HTTP_OK" == "✅" && "$HTTPS_OK" == "✅" ]]; then
    echo "🎉 所有服务运行正常！"
    echo "🔗 访问地址: https://api.justprompt.pro"
else
    echo "⚠️  部分服务存在问题"
    echo ""
    echo "📋 建议操作:"
    if [[ "$PM2_OK" == "❌" ]]; then
        echo "   - 启动PM2: ./run.sh 或 ./restart.sh"
    fi
    if [[ "$REDIS_OK" == "❌" ]]; then
        echo "   - 启动Redis: redis-server --port $REDIS_PORT --daemonize yes"
    fi
    if [[ "$NGINX_OK" == "❌" ]]; then
        echo "   - 启动Nginx: sudo systemctl start nginx"
    fi
    echo "   - 查看日志: pm2 logs $PROJECT_NAME"
    echo "   - 完整重启: ./restart.sh"
fi

echo ""
echo "📊 其他操作:"
echo "   🚀 启动: ./run.sh"
echo "   🔄 重启: ./restart.sh" 
echo "   ⏹️  停止: ./stop.sh"
echo "   📝 日志: pm2 logs $PROJECT_NAME"