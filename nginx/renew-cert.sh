#!/bin/bash

# 自动续签SSL证书脚本
# 配置域名和目录
DOMAIN="api.justprompt.pro"
CERT_DIR="/home/leon/claude-route-ssl/claude-route-ssl/nginx/ssl"
LOG_FILE="/home/leon/claude-route-ssl/claude-route-ssl/nginx/ssl/renew.log"

# 记录日志
echo "===========================================" >> $LOG_FILE
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始证书续签检查" >> $LOG_FILE

# 尝试续签证书
sudo certbot renew --quiet --no-self-upgrade >> $LOG_FILE 2>&1

# 检查续签是否成功
if [ $? -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 证书续签检查完成" >> $LOG_FILE
    
    # 检查证书是否实际更新
    if sudo test -e /etc/letsencrypt/live/$DOMAIN/fullchain.pem; then
        # 获取证书的修改时间
        CERT_MOD_TIME=$(sudo stat -c %Y /etc/letsencrypt/live/$DOMAIN/fullchain.pem)
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - CERT_MOD_TIME))
        
        # 如果证书在最近5分钟内更新过，则复制到项目目录
        if [ $TIME_DIFF -lt 300 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 检测到证书更新，正在复制到项目目录..." >> $LOG_FILE
            
            # 复制新证书到项目目录
            sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem $CERT_DIR/
            sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem $CERT_DIR/
            sudo cp /etc/letsencrypt/live/$DOMAIN/cert.pem $CERT_DIR/
            sudo cp /etc/letsencrypt/live/$DOMAIN/chain.pem $CERT_DIR/
            
            # 设置权限
            sudo chown leon:leon $CERT_DIR/*.pem
            sudo chmod 644 $CERT_DIR/*.pem
            sudo chmod 600 $CERT_DIR/privkey.pem
            
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 证书已更新到: $CERT_DIR" >> $LOG_FILE
            
            # 重载nginx配置
            sudo nginx -t && sudo systemctl reload nginx
            if [ $? -eq 0 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Nginx已重新加载" >> $LOG_FILE
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Nginx重载失败!" >> $LOG_FILE
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 证书未更新，无需操作" >> $LOG_FILE
        fi
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 证书续签失败!" >> $LOG_FILE
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 续签检查结束" >> $LOG_FILE
echo "" >> $LOG_FILE