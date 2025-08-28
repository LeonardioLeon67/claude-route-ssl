# Redis迁移工具集

本目录包含Claude Route SSL项目的Redis数据迁移相关工具和文档。

## 📁 文件说明

- **REDIS_MIGRATION_GUIDE.md** - 详细的迁移指南文档
- **redis-backup.sh** - Redis数据备份脚本
- **redis-restore.sh** - Redis数据恢复脚本
- **README.md** - 本说明文件

## 🚀 快速使用

### 备份数据（源服务器）

```bash
cd redis-migrate
./redis-backup.sh
```

备份将包含：
- Redis RDB持久化文件
- 所有数据的JSON导出（跨版本兼容）
- Key列表和统计信息
- 项目文件（account/和product/目录）

备份文件默认保存在：`~/claude-route-ssl-backup/`

### 恢复数据（目标服务器）

```bash
cd redis-migrate
./redis-restore.sh ~/claude-route-ssl-backup/redis-backup-20250827_120000
```

或使用最新备份：
```bash
./redis-restore.sh ~/claude-route-ssl-backup/latest
```

## 📊 备份内容

### Redis数据
- 客户端密钥 (client_keys:*)
- 产品记录 (trial/medium/high/supreme_products:*)
- 账户池管理 (*_pool:slots:*, *_pool:permanent_binding)
- 黑名单记录 (account_blacklist:*)
- 请求限制记录 (*_rate_limit:*)
- Token刷新相关数据

### 项目文件
- /account/ 目录（所有级别的账户文件）
- /product/ 目录（产品JSON文件）

## ⚙️ 配置说明

脚本默认使用：
- Redis端口：6380
- 备份目录：~/claude-route-ssl-backup/
- 项目目录：自动检测（脚本父目录）

## 📝 迁移步骤

### 1. 在源服务器上

```bash
# 进入迁移工具目录
cd /home/leon/claude-route-ssl/claude-route-ssl/redis-migrate

# 运行备份脚本
./redis-backup.sh

# 查看备份文件
ls -la ~/claude-route-ssl-backup/
```

### 2. 传输备份文件

```bash
# 打包备份文件
cd ~/claude-route-ssl-backup/
tar -czf claude-route-backup.tar.gz redis-backup-*

# 使用scp传输到目标服务器
scp claude-route-backup.tar.gz user@target-server:~/
```

### 3. 在目标服务器上

```bash
# 解压备份文件
cd ~/
tar -xzf claude-route-backup.tar.gz
mv redis-backup-* ~/claude-route-ssl-backup/

# 进入项目迁移工具目录
cd /home/leon/claude-route-ssl/claude-route-ssl/redis-migrate

# 恢复数据
./redis-restore.sh ~/claude-route-ssl-backup/redis-backup-[timestamp]

# 重启服务
direct restart

# 验证服务状态
direct status
direct pool
```

## 🔍 验证迁移

### 检查Redis数据

```bash
# 查看key总数
redis-cli -p 6380 DBSIZE

# 查看各类key数量
redis-cli -p 6380 --scan --pattern "client_keys:*" | wc -l
redis-cli -p 6380 --scan --pattern "*_products:*" | wc -l
redis-cli -p 6380 --scan --pattern "*_pool:*" | wc -l
```

### 检查项目文件

```bash
# 查看账户文件
ls -la ../account/*/

# 查看产品文件
ls -la ../product/
```

### 测试服务功能

```bash
# 查看池状态
direct pool

# 生成测试密钥
direct trial

# 查看服务日志
direct logs
```

## ⚠️ 注意事项

1. **停止服务**：建议在迁移期间停止源服务器的写入操作
2. **版本兼容**：确保目标服务器Redis版本≥源服务器版本
3. **端口配置**：确保目标服务器Redis配置端口6380
4. **权限问题**：确保Redis用户对数据文件有读写权限
5. **备份保留**：建议保留源服务器备份至少7天

## 🛠️ 故障排除

### Redis连接失败
```bash
# 检查Redis服务状态
systemctl status redis

# 检查端口6380是否监听
netstat -tlnp | grep 6380

# 测试Redis连接
redis-cli -p 6380 ping
```

### 恢复失败
- 检查备份文件完整性
- 确保有足够的磁盘空间
- 查看Redis日志：`tail -f /var/log/redis/redis-server.log`

### 权限错误
```bash
# 修复Redis数据文件权限
sudo chown redis:redis /var/lib/redis/dump.rdb
```

## 📚 更多信息

详细的迁移说明和原理请查看：[REDIS_MIGRATION_GUIDE.md](./REDIS_MIGRATION_GUIDE.md)

## 🆘 获取帮助

如遇到问题，请检查：
1. Redis服务日志
2. 项目日志：`direct logs`
3. 备份/恢复脚本的输出信息