# Claude Route SSL - 项目管理脚本

本目录包含管理Claude Route SSL项目的所有脚本工具。

## 📋 脚本列表

### 🚀 run.sh - 项目启动脚本
完整启动Claude Route SSL项目的所有服务。

**功能：**
- 编译TypeScript代码
- 检查并启动Redis服务
- 启动PM2进程 (claude-proxy)
- 检查并配置nginx
- 验证所有服务状态

**使用：**
```bash
cd /home/leon/claude-route-ssl/claude-route-ssl/shell
./run.sh
```

### 🔄 restart.sh - 项目重启脚本
重启项目的核心服务。

**功能：**
- 重新编译最新代码
- 重启PM2进程
- 检查并启动Redis服务
- 重载nginx配置
- 验证所有服务状态

**使用：**
```bash
./restart.sh
```

### 🛑 stop.sh - 项目停止脚本
停止Claude Route SSL项目进程。

**功能：**
- 停止PM2进程
- 可选择删除PM2进程
- 保持nginx和Redis服务运行（用于其他项目）
- 显示服务状态

**使用：**
```bash
./stop.sh
```

### 📊 status.sh - 项目状态检查脚本
详细检查项目所有服务的运行状态。

**功能：**
- 系统信息和资源使用
- PM2进程详细状态
- 端口监听状态
- 服务运行状态
- SSL证书状态
- 网络连接测试
- 服务状态总结

**使用：**
```bash
./status.sh
```

## 🏗️ 项目架构

### 核心服务
- **PM2进程**: claude-proxy (端口8080)
- **Nginx代理**: direct.816981.xyz → localhost:8080
- **Redis存储**: 端口6380 (账户和密钥管理)
- **SSL证书**: Let's Encrypt (自动续签)

### 服务依赖关系
```
Internet → Nginx (443/80) → Claude Route SSL (8080) → Redis (6380)
                ↓
         SSL Certificate (Let's Encrypt)
```

## 📁 文件结构

```
shell/
├── run.sh        # 启动脚本
├── restart.sh    # 重启脚本  
├── stop.sh       # 停止脚本
├── status.sh     # 状态检查脚本
├── medium.sh     # Medium级别密钥生成
├── high.sh       # High级别密钥生成
├── generate-key.sh  # 基础密钥生成
└── README.md     # 本文档
```

## 🚦 使用流程

### 首次部署
1. 确保域名 `direct.816981.xyz` 解析到服务器
2. 安装依赖：nginx, certbot, redis-server, pm2
3. 运行启动脚本：`./run.sh`

### 日常管理
- **查看状态**: `./status.sh`
- **重启服务**: `./restart.sh`
- **停止服务**: `./stop.sh`
- **查看日志**: `pm2 logs claude-proxy`

### 故障排除
1. 检查服务状态：`./status.sh`
2. 查看详细日志：`pm2 logs claude-proxy --lines 50`
3. 重启服务：`./restart.sh`
4. 如果问题持续，运行完整启动：`./run.sh`

## ⚠️ 重要说明

### 排除文件
- `forward-monitor.ts` - 测试代码，不参与项目编译和运行
- 已在 `tsconfig.json` 中排除此文件

### 服务端口
- **8080**: Claude Route SSL主服务
- **6380**: Redis数据存储
- **80/443**: Nginx HTTP/HTTPS

### SSL证书
- 域名：direct.816981.xyz
- 自动续签已配置
- 证书路径：`/etc/letsencrypt/live/direct.816981.xyz/`

### 数据存储
- 账户数据：`/account/` 目录
- 产品密钥：`/product/` 目录
- Redis缓存：端口6380

## 🔧 环境要求

### 系统依赖
- Node.js (已安装)
- PM2: `npm install -g pm2`
- Nginx: `sudo apt install nginx`
- Redis: `sudo apt install redis-server`
- Certbot: `sudo apt install certbot python3-certbot-nginx`

### 权限要求
- 脚本需要执行权限
- 需要sudo权限操作nginx和系统服务
- 需要访问SSL证书目录权限

## 📞 支持与维护

### 监控
- PM2自动重启：配置了内存限制和重启延迟
- SSL自动续签：Let's Encrypt + certbot定时任务
- 服务健康检查：使用status.sh定期检查

### 日志文件
- PM2日志：`logs/pm2-*.log`
- Nginx日志：`nginx/logs/*.log`
- SSL续签日志：`nginx/logs/ssl-renewal.log`

### 备份建议
- 定期备份 `/account/` 目录
- 定期备份 `/product/` 目录  
- 备份nginx配置文件
- 备份Redis数据（如需要）