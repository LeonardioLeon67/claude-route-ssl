#!/bin/bash

# Claude Route SSL 项目启动脚本

echo "=== Claude Route SSL 启动脚本 ==="
echo ""

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用root权限运行此脚本"
    exit 1
fi

# 1. 设置时区（可选）
read -p "是否需要设置系统时区为北京时间？(y/n): " set_timezone
if [ "$set_timezone" = "y" ] || [ "$set_timezone" = "Y" ]; then
    ./setup_timezone.sh
    echo ""
fi

# 2. 启动Redis服务
echo "检查Redis服务状态..."
if ! systemctl is-active --quiet redis-server; then
    echo "正在启动Redis服务..."
    systemctl start redis-server
    echo "Redis服务已启动"
else
    echo "Redis服务已在运行"
fi

# 3. 设置文件权限
echo ""
echo "设置文件权限..."
chmod 755 /root /root/claude-route /root/claude-route/claude-route-ssl
touch bindings.json generated_paths.txt
chown www-data:www-data bindings.json generated_paths.txt
chmod 666 bindings.json generated_paths.txt
echo "文件权限设置完成"

# 4. 检查nginx配置
echo ""
echo "检查nginx配置..."
if nginx -t -c /root/claude-route/claude-route-ssl/nginx.conf; then
    echo "nginx配置检查通过"
else
    echo "nginx配置有误，请检查"
    exit 1
fi

# 5. 启动nginx
echo ""
echo "启动nginx服务..."
# 先停止可能运行的nginx
nginx -s stop 2>/dev/null || true
sleep 1
# 启动nginx
if nginx -c /root/claude-route/claude-route-ssl/nginx.conf; then
    echo "nginx服务启动成功"
else
    echo "nginx服务启动失败"
    exit 1
fi

# 6. 显示服务状态
echo ""
echo "=== 服务状态 ==="
echo "Redis: $(systemctl is-active redis-server)"
echo "Nginx: $(ps aux | grep -v grep | grep nginx > /dev/null && echo 'active' || echo 'inactive')"
echo ""
echo "当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "服务已启动！"
echo ""
echo "使用以下命令生成新的URL："
echo "  ./generate_url.sh"
echo ""
echo "查看账户状态："
echo "  lua account_manager.lua list"