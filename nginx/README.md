# Nginx SSL Setup for direct.816981.xyz

本目录包含为域名 `direct.816981.xyz` 配置 Nginx 反向代理和 SSL 证书的所有必要文件。

## 目录结构

```
nginx/
├── conf.d/
│   └── direct.816981.xyz.conf    # Nginx 配置文件
├── logs/                          # 日志目录
│   ├── access.log                 # 访问日志
│   ├── error.log                  # 错误日志
│   └── ssl-renewal.log            # SSL 续签日志
├── ssl/                           # SSL 相关文件目录
├── setup-ssl.sh                   # SSL 证书申请和配置脚本
├── auto-renew.sh                  # SSL 证书自动续签脚本
├── setup-cron.sh                  # 设置定时任务脚本
└── README.md                      # 本说明文件
```

## 快速开始

### 1. 确保域名解析正确
确保 `direct.816981.xyz` 已经解析到你的服务器 IP。

### 2. 安装必要依赖
```bash
# 安装 nginx 和 certbot
sudo apt update
sudo apt install nginx certbot python3-certbot-nginx -y
```

### 3. 启动 Claude Route SSL 服务
```bash
# 确保项目在端口 8080 上运行
npm start
```

### 4. 执行 SSL 设置
```bash
# 运行 SSL 设置脚本
cd /home/leon/claude-route-ssl/claude-route-ssl/nginx
./setup-ssl.sh
```

### 5. 设置自动续签
```bash
# 设置 SSL 证书自动续签
./setup-cron.sh
```

## 脚本说明

### setup-ssl.sh
- 自动配置 nginx
- 申请 Let's Encrypt SSL 证书
- 配置 HTTPS 重定向
- 设置安全 headers
- 配置反向代理到端口 8080

### auto-renew.sh
- 检查证书是否需要续签
- 自动续签即将过期的证书
- 记录续签日志
- 自动重载 nginx 配置

### setup-cron.sh
- 设置定时任务
- 每天两次检查证书状态
- 自动执行续签操作

## 使用说明

### 手动测试 SSL 续签
```bash
sudo certbot renew --dry-run
```

### 查看证书状态
```bash
sudo certbot certificates
```

### 查看 nginx 状态
```bash
sudo systemctl status nginx
```

### 查看日志
```bash
# 查看访问日志
tail -f /home/leon/claude-route-ssl/claude-route-ssl/nginx/logs/access.log

# 查看错误日志
tail -f /home/leon/claude-route-ssl/claude-route-ssl/nginx/logs/error.log

# 查看 SSL 续签日志
tail -f /home/leon/claude-route-ssl/claude-route-ssl/nginx/logs/ssl-renewal.log
```

## 安全配置

配置文件包含以下安全措施：
- 强制 HTTPS 重定向
- 现代 SSL/TLS 配置
- 安全 headers (HSTS, X-Frame-Options, 等)
- 禁用不安全的 SSL 协议
- 配置适当的缓冲和超时设置

## 故障排除

### 证书申请失败
1. 确认域名解析正确
2. 检查防火墙设置 (端口 80, 443)
3. 确认 nginx 配置语法正确
4. 查看 certbot 详细错误信息

### Nginx 配置错误
```bash
# 测试配置语法
sudo nginx -t

# 重新加载配置
sudo systemctl reload nginx
```

### SSL 证书续签失败
1. 检查 certbot 服务状态
2. 查看续签日志
3. 手动执行续签测试
4. 确认自动续签任务正常运行

## 技术支持

如需技术支持，请查看：
- nginx 日志文件
- SSL 续签日志
- 系统日志 `/var/log/nginx/`
- Certbot 日志 `/var/log/letsencrypt/`