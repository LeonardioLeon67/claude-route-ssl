# Nginx SSL配置文档

## 域名配置
- **主域名**: api.justprompt.pro
- **证书目录**: `/home/leon/claude-route-ssl/claude-route-ssl/nginx/ssl/`
- **配置文件**: `/home/leon/claude-route-ssl/claude-route-ssl/nginx/api.justprompt.pro.conf`

## 证书管理

### 首次申请证书
```bash
# 运行证书申请脚本
./nginx/apply-cert.sh
```

### 证书自动续签
证书会自动续签，续签任务通过用户crontab设置：
- 每天凌晨2:30和下午2:30自动检查
- 证书即将过期时自动续签
- 续签后自动更新到项目目录并重载nginx
- 使用当前用户(leon)的crontab，非系统cron

### 手动续签证书
```bash
# 手动运行续签脚本
./nginx/renew-cert.sh
```

### 设置自动续签
```bash
# 运行cron设置脚本（只需运行一次）
./nginx/setup-cron.sh

# 查看当前用户的crontab
crontab -l

# 手动编辑crontab
crontab -e
```

## 证书文件说明
- `fullchain.pem`: 完整证书链（包含服务器证书和中间证书）
- `privkey.pem`: 私钥文件（权限600，仅所有者可读写）
- `cert.pem`: 服务器证书
- `chain.pem`: 中间证书链

## Nginx配置部署

### 1. 链接配置文件到nginx
```bash
sudo ln -s /home/leon/claude-route-ssl/claude-route-ssl/nginx/api.justprompt.pro.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/api.justprompt.pro.conf /etc/nginx/sites-enabled/
```

### 2. 测试配置
```bash
sudo nginx -t
```

### 3. 重载nginx
```bash
sudo systemctl reload nginx
```

## 日志文件
- **访问日志**: `/var/log/nginx/api.justprompt.pro.access.log`
- **错误日志**: `/var/log/nginx/api.justprompt.pro.error.log`
- **续签日志**: `/home/leon/claude-route-ssl/claude-route-ssl/nginx/ssl/renew.log`

## 故障排除

### 证书申请失败
1. 检查域名DNS解析是否正确指向服务器
2. 确保80端口可访问（用于Let's Encrypt验证）
3. 检查防火墙设置

### 证书续签失败
1. 查看续签日志：`cat nginx/ssl/renew.log`
2. 手动测试续签：`sudo certbot renew --dry-run`
3. 检查cron任务：`crontab -l`

### Nginx无法启动
1. 检查配置语法：`sudo nginx -t`
2. 查看错误日志：`sudo tail -f /var/log/nginx/error.log`
3. 确认证书文件存在且权限正确

## 重要提示
- 证书有效期为90天，建议提前30天续签
- 自动续签脚本每天运行两次，确保及时续签
- 续签后会自动复制到项目目录并重载nginx
- 保持`/var/www/certbot`目录可访问，用于证书验证