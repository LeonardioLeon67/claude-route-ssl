#!/bin/bash

# 域名配置
DOMAIN="api.justprompt.pro"
EMAIL="admin@justprompt.pro"  # 替换为你的邮箱
CERT_DIR="/home/leon/claude-route-ssl/claude-route-ssl/nginx/ssl"
WEBROOT="/var/www/certbot"  # 用于验证的webroot目录

# 创建webroot目录
sudo mkdir -p $WEBROOT

# 检查是否已安装certbot
if ! command -v certbot &> /dev/null; then
    echo "正在安装certbot..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-nginx
fi

# 申请证书
echo "正在申请 $DOMAIN 的SSL证书..."
sudo certbot certonly \
    --webroot \
    --webroot-path $WEBROOT \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    --domains $DOMAIN \
    --cert-path $CERT_DIR \
    --key-path $CERT_DIR \
    --fullchain-path $CERT_DIR \
    --chain-path $CERT_DIR

# 检查证书是否申请成功
if [ $? -eq 0 ]; then
    echo "证书申请成功！"
    
    # 复制证书到指定目录
    sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem $CERT_DIR/
    sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem $CERT_DIR/
    sudo cp /etc/letsencrypt/live/$DOMAIN/cert.pem $CERT_DIR/
    sudo cp /etc/letsencrypt/live/$DOMAIN/chain.pem $CERT_DIR/
    
    # 设置权限
    sudo chown -R leon:leon $CERT_DIR
    sudo chmod 644 $CERT_DIR/*.pem
    sudo chmod 600 $CERT_DIR/privkey.pem
    
    echo "证书已复制到: $CERT_DIR"
    ls -la $CERT_DIR/
else
    echo "证书申请失败，请检查域名解析是否正确"
    exit 1
fi