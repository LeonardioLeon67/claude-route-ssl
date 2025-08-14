#!/bin/bash

# Claude Route SSL Project - 停止脚本
# 停止PM2进程，但保持nginx运行

PROJECT_DIR="/home/leon/claude-route-ssl/claude-route-ssl"

echo "🛑 Claude Route SSL - 停止中..."
echo "=================================="

cd $PROJECT_DIR

# Step 1: 停止PM2进程
echo "📋 Step 1: 停止PM2进程..."
if pm2 list | grep -q "claude-proxy.*online"; then
    if pm2 stop claude-proxy; then
        echo "✅ PM2进程已停止"
    else
        echo "❌ PM2进程停止失败!"
        exit 1
    fi
else
    echo "⚠️  PM2进程未运行"
fi

# Step 2: 停止进程但保留配置（不删除）
echo "📋 Step 2: 保留PM2进程配置..."
echo "⏸️  PM2进程已停止但保留配置"
echo "💡 如需完全删除进程配置: pm2 delete claude-proxy"

# Step 3: 检查nginx状态 (保持运行)
echo "📋 Step 3: 检查nginx状态..."
if sudo systemctl is-active --quiet nginx; then
    echo "✅ Nginx服务保持运行 (用于其他站点)"
    echo "💡 如需停止nginx: sudo systemctl stop nginx"
else
    echo "⚠️  Nginx服务未运行"
fi

# Step 4: 验证端口状态
echo "📋 Step 4: 验证端口状态..."
if netstat -tuln | grep -q ":8080 "; then
    echo "⚠️  端口8080仍在使用，可能存在其他进程"
    echo "🔍 查看占用进程: sudo netstat -tulnp | grep :8080"
else
    echo "✅ 端口8080已释放"
fi

echo ""
echo "🎉 Claude Route SSL 停止完成!"
echo "=================================="

# 显示PM2状态
echo "📊 当前PM2状态:"
pm2 list | head -n 1
pm2 list | grep -E "(claude-proxy|id.*name)" || echo "无Claude相关进程"

echo ""
echo "🔗 服务状态:"
if sudo systemctl is-active --quiet nginx; then
    echo "   Nginx: ✅ 运行中"
else
    echo "   Nginx: ❌ 已停止"
fi

echo ""
echo "📋 重新启动服务:"
echo "   ./run.sh       # 完整启动"
echo "   ./restart.sh   # 重启服务"
echo ""
echo "📊 查看状态:"
echo "   ./status.sh    # 查看详细状态"