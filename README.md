# Claude API 动态绑定转发服务

这是一个基于nginx-lua的Claude API转发服务，实现了URL与API密钥的动态绑定机制。每个随机生成的URL只能绑定一个API密钥，确保访问安全。

## 功能特点

- 🔒 **动态绑定**: 客户端首次访问时自动绑定API密钥与URL
- 🚫 **访问控制**: 其他API密钥无法使用已绑定的URL
- 💾 **持久化**: 绑定关系保存在JSON文件中，重启后仍有效
- 🔄 **SSL支持**: 使用Let's Encrypt证书提供HTTPS访问

## 快速启动

### 1. 启动nginx服务
```bash
cd /root/claude-route/claude-route-ssl
nginx -c /root/claude-route/claude-route-ssl/nginx.conf
```

### 2. 生成客户端URL
```bash
./generate_url.sh
```
输出示例：
```
生成的随机URL路径: /abc123def456/v1/messages
完整URL: https://api.816981.xyz/abc123def456/v1/messages
URL已记录到 generated_paths.txt
```

### 3. 分配给客户端
将生成的完整URL给客户端使用：
```
Base URL: https://api.816981.xyz/abc123def456
API端点: https://api.816981.xyz/abc123def456/v1/messages
```

## 工作原理

1. **首次访问**: 客户端用API密钥访问分配的URL时，系统自动创建绑定关系
2. **绑定记录**: 绑定信息保存到 `bindings.json` 文件
3. **访问控制**: 后续只有绑定的API密钥能访问该URL，其他密钥返回403错误

## 文件说明

```
claude-route-ssl/
├── nginx.conf              # nginx主配置文件
├── generate_url.sh          # 生成随机URL脚本
├── generated_paths.txt      # 生成的URL记录
├── bindings.json           # 动态绑定数据存储
├── logs/                   # 日志目录
│   ├── nginx_access.log    # 访问日志
│   └── nginx_error.log     # 错误日志
└── /var/www/lua/
    └── dynamic_auth.lua    # Lua动态验证脚本
```

## 常用命令

### 查看服务状态
```bash
ps aux | grep nginx
```

### 重启nginx
```bash
nginx -s stop
nginx -c /root/claude-route/claude-route-ssl/nginx.conf
```

### 重新加载配置
```bash
nginx -s reload
```

### 查看生成的URL列表
```bash
cat generated_paths.txt
```

### 查看绑定关系
```bash
cat bindings.json
```

### 查看访问日志
```bash
tail -f logs/nginx_access.log
```

### 查看错误日志
```bash
tail -f logs/nginx_error.log
```

## 测试验证

### 测试首次绑定
```bash
curl -X POST https://api.816981.xyz/[YOUR_TOKEN]/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: your-api-key-here" \
  -d '{"model": "claude-3-sonnet-20240229", "max_tokens": 10, "messages": [{"role": "user", "content": "Hello"}]}'
```

### 测试访问控制（应该返回403）
```bash
curl -X POST https://api.816981.xyz/[YOUR_TOKEN]/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: different-api-key" \
  -d '{"model": "claude-3-sonnet-20240229", "max_tokens": 10, "messages": [{"role": "user", "content": "Hello"}]}'
```

## 预期响应

- **首次绑定成功**: 返回401（测试密钥无效）或正常Claude API响应
- **绑定的密钥继续访问**: 正常Claude API响应  
- **其他密钥访问**: 返回403 "This token is bound to another API key"

## 故障排除

### nginx启动失败
1. 检查配置语法: `nginx -t -c /root/claude-route/claude-route-ssl/nginx.conf`
2. 检查端口占用: `netstat -tlnp | grep :443`
3. 检查SSL证书: `ls -la /etc/letsencrypt/live/api.816981.xyz/`

### 绑定功能异常
1. 检查文件权限: `ls -la bindings.json generated_paths.txt`
2. 检查Lua脚本: `ls -la /var/www/lua/dynamic_auth.lua`
3. 查看错误日志: `tail logs/nginx_error.log`

### 权限问题修复
```bash
chmod 755 /root /root/claude-route /root/claude-route/claude-route-ssl
chown www-data:www-data bindings.json generated_paths.txt
chmod 666 bindings.json generated_paths.txt
```

## 系统要求

- Ubuntu/Debian系统
- nginx-extras (包含lua模块)
- SSL证书 (Let's Encrypt)
- 端口443/80开放

## 安全注意事项

- 绑定数据保存在本地文件中，确保服务器安全
- 日志文件可能包含敏感信息，定期清理
- 只分配URL给可信的客户端
- 定期监控访问日志检查异常访问

---

**快速恢复服务**: 运行 `nginx -c /root/claude-route/claude-route-ssl/nginx.conf` 即可启动服务