#!/bin/bash

# Claude Route SSL Project Restart Script
# 重启本项目：PM2 + Nginx代理

PROJECT_DIR="/home/leon/claude-route-ssl/claude-route-ssl"
PROJECT_NAME="claude-proxy"

echo "🔄 重启 Claude Route SSL 项目"
echo "================================"

# 检查项目目录
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ 项目目录不存在: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

# Step 1: 构建TypeScript项目
echo "📋 Step 1: 重新构建TypeScript项目..."
if ! npm run build; then
    echo "❌ 项目构建失败！"
    exit 1
fi
echo "✅ 项目构建成功"

# Step 2: 重启PM2进程
echo "📋 Step 2: 重启PM2进程..."
if pm2 describe $PROJECT_NAME > /dev/null 2>&1; then
    echo "🔄 重启现有PM2进程..."
    pm2 restart $PROJECT_NAME
    echo "✅ PM2进程重启成功"
else
    echo "⚠️  PM2进程不存在，启动新进程..."
    pm2 start ecosystem.config.js --env production
    echo "✅ PM2进程启动成功"
fi

# 等待进程重启
sleep 3

# 检查PM2进程状态
if pm2 describe $PROJECT_NAME | grep -q "online"; then
    echo "✅ PM2进程运行正常"
else
    echo "❌ PM2进程重启失败"
    pm2 logs $PROJECT_NAME --lines 10
    exit 1
fi

# Step 3: 重载nginx配置
echo "📋 Step 3: 重载nginx配置..."
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "✅ nginx配置重载成功"
else
    echo "❌ nginx配置测试失败"
    exit 1
fi

# Step 4: 清理PM2日志
echo "📋 Step 4: 清理PM2日志..."
pm2 flush $PROJECT_NAME
echo "✅ PM2日志已清理"

# Step 5: 验证服务状态
echo "📋 Step 5: 验证重启后状态..."

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
echo "🎉 Claude Route SSL 项目重启完成！"
echo "================================"
echo "✅ PM2进程: $PROJECT_NAME (已重启)"
echo "✅ Nginx代理: https://direct.816981.xyz (已重载)"
echo "✅ 项目目录: $PROJECT_DIR"
echo ""
echo "📊 查看状态: ./status.sh"
echo "⏹️  停止服务: ./stop.sh"
echo "📝 查看日志: pm2 logs $PROJECT_NAME"