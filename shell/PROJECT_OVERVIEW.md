# Claude Route SSL - 项目概览

## 🚀 项目简介

Claude Route SSL 是一个基于 TypeScript 的 Claude API 代理服务器，支持 OAuth 认证和客户端密钥管理系统。

### 核心功能
- ✅ 自动添加 `anthropic-beta: oauth-2025-04-20` header
- ✅ Bearer token (sk-ant-oat01-xxx) 访问 Claude API  
- ✅ 客户端密钥管理系统 (sk-cli-v1-xxx格式)
- ✅ 完整的请求代理和错误处理
- ✅ 支持所有Claude模型
- ✅ PM2后台运行 + Nginx反向代理
- ✅ Redis数据存储 + SSL自动管理

## 🏗️ 系统架构

### 服务架构图
```
Internet → Nginx (443/80) → Claude Route SSL (8080) → Redis (6380) → Claude API
                ↓
         SSL Certificate (Let's Encrypt)
```

### 核心组件
1. **PM2进程管理** - claude-proxy (端口8080)
2. **Nginx反向代理** - direct.816981.xyz → localhost:8080
3. **Redis数据存储** - 端口6380 (账户和密钥管理)
4. **SSL证书** - Let's Encrypt (自动续签)

## 📁 项目结构

```
claude-route-ssl/
├── src/                          # TypeScript源码
│   ├── proxy-server.ts          # 主服务程序
│   └── forward-monitor.ts       # 测试代码 (已排除)
├── dist/                        # 编译后的JS文件
├── shell/                       # 管理脚本
│   ├── run.sh                   # 启动脚本
│   ├── restart.sh               # 重启脚本
│   ├── stop.sh                  # 停止脚本
│   ├── status.sh                # 状态检查脚本
│   ├── medium.sh                # Medium级别密钥生成
│   ├── high.sh                  # High级别密钥生成
│   └── generate-key.sh          # 基础密钥生成
├── nginx/                       # Nginx配置
│   ├── conf.d/                  # 配置文件
│   ├── logs/                    # 日志文件
│   └── setup-ssl.sh             # SSL设置脚本
├── account/                     # 多账户管理
├── product/                     # 产品密钥管理
├── logs/                        # 应用日志
├── ecosystem.config.js          # PM2配置
├── package.json                 # 项目依赖
└── tsconfig.json               # TypeScript配置
```

## 🔧 核心配置

### PM2配置 (ecosystem.config.js)
```javascript
{
  name: 'claude-proxy',
  script: './dist/proxy-server.js',
  port: 8080,
  instances: 1,
  autorestart: true,
  max_memory_restart: '1G'
}
```

### 服务端口
- **8080**: Claude Route SSL主服务
- **6380**: Redis数据存储
- **80/443**: Nginx HTTP/HTTPS

### 域名配置
- **主域名**: direct.816981.xyz
- **SSL证书**: Let's Encrypt 自动续签
- **HTTP**: 自动重定向到HTTPS

## 📋 管理脚本使用

### 启动项目
```bash
cd /home/leon/claude-route-ssl/claude-route-ssl/shell
./run.sh
```

### 查看状态
```bash
./status.sh
```

### 重启服务
```bash
./restart.sh
```

### 停止服务
```bash
./stop.sh
```

### 生成客户端密钥
```bash
./generate-key.sh                # 基础密钥
./medium.sh [account-name]       # Medium级别
./high.sh [account-name]         # High级别
```

## 🔐 安全特性

### SSL/TLS配置
- 现代SSL协议 (TLSv1.2, TLSv1.3)
- 强加密套件
- HSTS安全headers
- 自动证书续签

### 访问控制
- 客户端密钥验证
- Bearer token转换
- OAuth认证支持
- Redis会话管理

### 数据保护
- 敏感数据加密存储
- Token自动刷新
- 密钥轮换机制
- 访问日志记录

## 📊 监控和日志

### PM2监控
```bash
pm2 monit                    # 实时监控面板
pm2 logs claude-proxy        # 查看日志
pm2 list                     # 进程列表
pm2 show claude-proxy        # 详细信息
```

### 日志文件
- **PM2日志**: `logs/pm2-*.log`
- **Nginx日志**: `nginx/logs/*.log`
- **SSL日志**: `nginx/logs/ssl-renewal.log`

### 状态检查
```bash
./status.sh                  # 完整状态检查
curl -I https://direct.816981.xyz  # 快速连接测试
```

## 🔄 自动化功能

### 自动重启
- PM2进程异常自动重启
- 内存限制自动重启
- 配置文件变更重载

### 自动续签
- SSL证书到期前自动续签
- Nginx配置自动重载
- 续签失败邮件通知

### 健康检查
- 定期服务状态检查
- 异常情况自动恢复
- 监控数据收集

## 🚀 性能优化

### 系统配置
- Redis持久化配置
- Nginx缓冲优化
- PM2集群模式支持
- 系统资源限制

### 网络优化
- HTTP/2协议支持
- 连接复用
- 请求压缩
- 缓存策略

## 🛠️ 故障排除

### 常见问题
1. **PM2进程停止**
   - 检查内存使用: `pm2 monit`
   - 查看错误日志: `pm2 logs claude-proxy --err`
   - 重启进程: `./restart.sh`

2. **Redis连接失败**
   - 检查Redis进程: `pgrep -f "redis-server.*6380"`
   - 测试连接: `redis-cli -p 6380 ping`
   - 重启Redis: `./restart.sh`

3. **HTTPS访问异常**
   - 检查SSL证书: `./status.sh`
   - 测试nginx配置: `sudo nginx -t`
   - 重载nginx: `sudo systemctl reload nginx`

### 调试命令
```bash
# 检查端口占用
ss -tlnp | grep -E "(8080|6380|443)"

# 查看进程状态
ps aux | grep -E "(claude-proxy|redis-server|nginx)"

# 测试连接
curl -v https://direct.816981.xyz

# 检查系统资源
top -p $(pgrep -d, -f "claude-proxy\|redis-server")
```

## 📞 技术支持

### 文档资源
- 项目README: `/CLAUDE.md`
- 脚本说明: `/shell/README.md`
- Nginx配置: `/nginx/README.md`

### 联系方式
- GitHub Issues: [项目仓库]
- 技术文档: 项目wiki
- 监控面板: PM2 monit

---

**最后更新**: 2025-08-14
**版本**: v1.0.0
**维护者**: Claude Route SSL Team