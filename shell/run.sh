#!/bin/bash

# Claude Route SSL Project Startup Script
# 启动本项目：PM2 + Nginx代理

PROJECT_DIR="/home/leon/claude-route-ssl/claude-route-ssl"
PROJECT_NAME="claude-proxy"

echo "🚀 启动 Claude Route SSL 项目"
echo "================================"

# 检查项目目录
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ 项目目录不存在: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

# Step 1: 构建TypeScript项目
echo "📋 Step 1: 构建TypeScript项目..."
if ! npm run build; then
    echo "❌ 项目构建失败！"
    exit 1
fi
echo "✅ 项目构建成功"

# Step 2: 启动PM2进程
echo "📋 Step 2: 启动PM2进程..."
if pm2 describe $PROJECT_NAME > /dev/null 2>&1; then
    echo "⚠️  PM2进程已存在，正在重启..."
    pm2 restart $PROJECT_NAME
else
    echo "🔄 启动新的PM2进程..."
    pm2 start ecosystem.config.js --env production
fi

# 等待进程启动
sleep 3

# 检查PM2进程状态
if pm2 describe $PROJECT_NAME | grep -q "online"; then
    echo "✅ PM2进程启动成功"
else
    echo "❌ PM2进程启动失败"
    pm2 logs $PROJECT_NAME --lines 10
    exit 1
fi

# Step 3: 检查nginx配置并启动
echo "📋 Step 3: 检查nginx配置..."
NGINX_CONF="/home/leon/claude-route-ssl/claude-route-ssl/nginx/conf.d/direct.816981.xyz.conf"

if [ -f "$NGINX_CONF" ]; then
    # 链接nginx配置
    sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-available/direct.816981.xyz.conf
    sudo ln -sf /etc/nginx/sites-available/direct.816981.xyz.conf /etc/nginx/sites-enabled/direct.816981.xyz.conf
    
    # 测试nginx配置
    if sudo nginx -t; then
        echo "✅ nginx配置测试通过"
        sudo systemctl reload nginx
        echo "✅ nginx已重载配置"
    else
        echo "❌ nginx配置测试失败"
        exit 1
    fi
else
    echo "⚠️  nginx配置文件不存在，跳过nginx配置"
fi

# Step 4: 验证服务状态
echo "📋 Step 4: 验证服务状态..."

# 检查PM2服务
echo "🔍 PM2状态:"
pm2 list | grep $PROJECT_NAME

# 检查端口8080
echo "🔍 检查端口8080:"
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080 | grep -q "401"; then
    echo "✅ 服务在8080端口正常响应"
else
    echo "❌ 服务在8080端口无响应"
fi

# 检查HTTPS访问
echo "🔍 检查HTTPS访问:"
if curl -s -o /dev/null -w "%{http_code}" https://direct.816981.xyz | grep -q "401"; then
    echo "✅ HTTPS访问正常"
else
    echo "⚠️  HTTPS访问可能有问题"
fi

echo ""
echo "🎉 Claude Route SSL 项目启动完成！"
echo "================================"
echo "✅ PM2进程: $PROJECT_NAME (端口8080)"
echo "✅ Nginx代理: https://direct.816981.xyz"
echo "✅ 项目目录: $PROJECT_DIR"
echo ""
echo "📊 查看状态: ./status.sh"
echo "🔄 重启服务: ./restart.sh"
echo "⏹️  停止服务: ./stop.sh"
echo "📝 查看日志: pm2 logs $PROJECT_NAME"