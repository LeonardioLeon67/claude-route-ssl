# 🚀 Claude Route SSL - 快速开始

## 立即启动项目

### 1️⃣ 进入脚本目录
```bash
cd /home/leon/claude-route-ssl/claude-route-ssl/shell
```

### 2️⃣ 启动所有服务
```bash
./run.sh
```

### 3️⃣ 检查服务状态
```bash
./status.sh
```

### 4️⃣ 访问服务
- **HTTPS**: https://direct.816981.xyz
- **本地**: http://127.0.0.1:8080

## 🔄 日常管理命令

| 命令 | 功能 | 说明 |
|------|------|------|
| `./run.sh` | 启动项目 | 完整启动所有服务 |
| `./restart.sh` | 重启服务 | 重新构建并重启 |
| `./stop.sh` | 停止服务 | 停止PM2进程 |
| `./status.sh` | 查看状态 | 详细服务状态检查 |

## 📊 服务状态检查

```bash
# 快速状态检查
./status.sh

# PM2进程监控
pm2 monit

# 查看实时日志
pm2 logs claude-proxy

# 测试HTTPS连接
curl -I https://direct.816981.xyz
```

## 🔑 生成客户端密钥

```bash
# 基础密钥
./generate-key.sh

# Medium级别密钥
./medium.sh [账户名]

# High级别密钥  
./high.sh [账户名]
```

## ✅ 健康检查清单

运行 `./status.sh` 应该看到：
- ✅ PM2进程: claude-proxy
- ✅ Redis服务: 端口6380
- ✅ Nginx代理服务
- ✅ 本地HTTP连接
- ✅ HTTPS外部访问

## 🆘 故障处理

### 服务异常
```bash
# 1. 重启所有服务
./restart.sh

# 2. 如果仍有问题，完全重新启动
./stop.sh
./run.sh

# 3. 查看详细日志
pm2 logs claude-proxy --lines 50
```

### 端口占用
```bash
# 检查端口占用
ss -tlnp | grep -E "(8080|6380)"

# 强制终止进程
pkill -f "claude-proxy"
pkill -f "redis-server.*6380"
```

---

**快速访问**: https://direct.816981.xyz  
**本地测试**: http://127.0.0.1:8080  
**状态检查**: `./status.sh`