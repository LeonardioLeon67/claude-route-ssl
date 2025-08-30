# Redis数据迁移工具

Claude Route SSL项目的Redis数据备份和恢复工具集，用于6380端口Redis实例的数据迁移。

## 📂 目录结构

```
redis-migrate/
├── redis-backup.sh          # 备份脚本
├── redis-restore.sh         # 恢复脚本
├── redis-backup-file/       # 备份文件存储目录
│   ├── redis_backup_*.rdb  # RDB备份文件
│   ├── backup_info_*.json  # 备份信息文件
│   └── backup_keys_*.txt   # 键名列表文件
└── README.md               # 本说明文档
```

## 🚀 快速开始

### 备份数据

```bash
cd /home/leon/claude-route-ssl/claude-route-ssl/redis-migrate
./redis-backup.sh
```

### 恢复数据

```bash
cd /home/leon/claude-route-ssl/claude-route-ssl/redis-migrate
./redis-restore.sh
```

## 📦 redis-backup.sh 备份脚本

### 功能特点

- ✅ 自动连接6380端口的Redis实例
- ✅ 创建带时间戳的RDB快照备份
- ✅ 导出所有键名列表供参考
- ✅ 生成详细的JSON格式备份信息
- ✅ 统计各类业务键的数量分布
- ✅ 自动清理旧备份（保留最近10个）
- ✅ 使用相对路径存储，便于项目整体迁移

### 备份内容统计

脚本会统计以下类型的键：
- 客户端密钥 (`client_keys:*`)
- Trial级别产品 (`trial_products:*`)
- Medium级别产品 (`medium_products:*`)
- High级别产品 (`high_products:*`)
- Supreme级别产品 (`supreme_products:*`)
- 各级别Slot占用 (`*_pool:slots:*`)
- 黑名单记录 (`account_blacklist:*`)
- Token刷新相关 (`refresh_*`)
- 永久绑定关系 (`permanent_binding:*`)

### 生成的备份文件

每次备份会生成3个文件（时间戳格式：YYYYMMDD_HHMMSS）：

1. **redis_backup_[时间戳].rdb**
   - Redis数据库的完整RDB快照
   - 包含所有键值对数据
   - 可直接用于恢复

2. **backup_info_[时间戳].json**
   - 备份的元信息
   - 包含备份时间、键数量、内存使用等
   - 各类键的详细统计

3. **backup_keys_[时间戳].txt**
   - 所有键名的列表
   - 用于数据验证和参考

### 使用示例

```bash
# 执行备份
./redis-backup.sh

# 输出示例：
===========================================
     Redis Backup Script for Claude Route SSL
===========================================

[1/6] 检查Redis连接...
✅ Redis连接成功 (端口: 6380)
[2/6] 创建备份目录...
✅ 备份目录已存在
[3/6] 收集Redis统计信息...
  📊 键总数: 132
  💾 内存使用: 2.15M
[4/6] 导出所有键名列表...
✅ 已导出 132 个键名
[5/6] 分析键类型统计...
[6/6] 创建RDB备份快照...
✅ RDB文件已备份到: redis_backup_20250829_054156.rdb

===========================================
        🎉 备份完成！
===========================================
```

## 🔄 redis-restore.sh 恢复脚本

### 功能特点

- ✅ 交互式选择要恢复的备份文件
- ✅ 显示每个备份的详细信息
- ✅ 恢复前自动创建安全备份
- ✅ 完整恢复所有Redis数据
- ✅ 验证恢复后的数据完整性
- ✅ 可选自动重启Claude Route SSL应用
- ✅ 智能处理Redis服务状态

### 恢复流程

1. **选择备份** - 列出所有可用备份，显示创建时间、键数、文件大小
2. **确认操作** - 显示警告信息，需要输入yes确认
3. **安全备份** - 自动备份当前数据（如有）
4. **清空数据** - 使用FLUSHALL清空当前数据库
5. **恢复数据** - 复制备份RDB文件并重启Redis加载
6. **验证结果** - 显示恢复后的键数量和类型统计
7. **重启应用** - 可选重启Claude Route SSL应用

### 使用示例

```bash
# 执行恢复
./redis-restore.sh

# 交互示例：
===========================================
     Redis Restore Script for Claude Route SSL
===========================================

可用的备份文件:

  [ 1] redis_backup_20250829_054156.rdb
       时间: 2025-08-29 05:41:56 | 键数: 132 | 大小: 40K

  [ 2] redis_backup_20250829_050000.rdb
       时间: 2025-08-29 05:00:00 | 键数: 128 | 大小: 38K

请选择要恢复的备份文件编号 (1-2):
> 1

⚠️  警告: 恢复操作将会清空当前Redis的所有数据！
是否继续? (yes/no):
> yes

[恢复过程...]

===========================================
        🎉 数据恢复完成！
===========================================
  📦 恢复的备份: redis_backup_20250829_054156.rdb
  📊 恢复的键数: 132
  💾 内存使用: 2.15M

是否现在重启Claude Route SSL应用? (yes/no):
> yes
```

## 🔐 安全注意事项

1. **数据覆盖警告**
   - 恢复操作会清空目标Redis的所有数据
   - 恢复前会自动创建安全备份
   - 需要明确输入yes确认操作

2. **权限要求**
   - 需要Redis访问权限
   - 需要文件系统读写权限
   - 重启应用需要相应的进程管理权限

3. **端口配置**
   - 脚本固定使用6380端口
   - 如需修改端口，编辑脚本中的`REDIS_PORT`变量

## 📝 迁移到其他服务器

### 步骤1：打包备份文件

在源服务器上：
```bash
cd /home/leon/claude-route-ssl/claude-route-ssl
tar -czf redis-migrate-backup.tar.gz redis-migrate/
```

### 步骤2：传输到目标服务器

使用scp或其他方式传输：
```bash
scp redis-migrate-backup.tar.gz user@target-server:/path/to/claude-route-ssl/
```

### 步骤3：在目标服务器恢复

在目标服务器上：
```bash
cd /path/to/claude-route-ssl
tar -xzf redis-migrate-backup.tar.gz
cd redis-migrate
./redis-restore.sh
```

## 🛠 故障排除

### Redis连接失败

```bash
# 检查Redis是否运行在6380端口
redis-cli -p 6380 ping

# 如果未运行，启动Redis
redis-server --port 6380 --daemonize yes
```

### 备份目录不存在

脚本会自动创建备份目录，如果失败请检查：
- 当前用户的写入权限
- 磁盘空间是否充足

### 恢复后数据不完整

1. 检查备份文件完整性
2. 查看backup_info_*.json确认备份时的键数量
3. 确保Redis有足够的内存加载所有数据

## 📊 备份策略建议

### 定期备份

建议使用cron定时任务：
```bash
# 每天凌晨3点自动备份
0 3 * * * cd /home/leon/claude-route-ssl/claude-route-ssl/redis-migrate && ./redis-backup.sh
```

### 备份保留策略

- 脚本自动保留最近10个备份
- 重要版本发布前建议手动备份
- 定期将备份文件归档到其他存储

## 🔧 自定义配置

如需修改默认配置，编辑脚本中的以下变量：

```bash
# Redis端口
REDIS_PORT=6380

# Redis主机
REDIS_HOST="localhost"

# 保留的备份数量（默认10个）
# 在redis-backup.sh中修改第236行的数字
if [ $BACKUP_COUNT -gt 10 ]; then
```

## 📞 技术支持

如遇到问题，请检查：
1. Redis服务状态：`redis-cli -p 6380 ping`
2. 项目运行状态：`direct status`
3. 查看PM2日志：`pm2 logs`

---

*本工具是Claude Route SSL项目的一部分，用于简化Redis数据的备份和迁移操作。*