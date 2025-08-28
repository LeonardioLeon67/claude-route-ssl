# Redis数据迁移指南

## 概述
本指南详细说明如何将Claude Route SSL项目的Redis数据从一台服务器迁移到另一台服务器。

## Redis数据结构说明

### 关键数据类型
```
1. 客户端密钥数据
   - client_keys:[key] (Hash)
   
2. 产品记录
   - trial_products:[key] (Hash)
   - medium_products:[key] (Hash)
   - high_products:[key] (Hash)
   - supreme_products:[key] (Hash)
   
3. 账户池管理
   - trial_pool:slots:[account] (String)
   - medium_pool:slots:[account] (String)
   - high_pool:slots:[account] (String)
   - supreme_pool:slots:[account] (String)
   
4. 永久绑定关系
   - trial_pool:permanent_binding (Hash)
   - medium_pool:permanent_binding (Hash)
   - high_pool:permanent_binding (Hash)
   - supreme_pool:permanent_binding (Hash)
   
5. 黑名单记录
   - account_blacklist:trial:[account] (String)
   - account_blacklist:medium:[account] (String)
   - account_blacklist:high:[account] (String)
   - account_blacklist:supreme:[account] (String)
   
6. 请求限制记录
   - high_rate_limit:[key]:[model]:window (String)
   - high_rate_limit:[key]:[model]:count (String)
   - supreme_rate_limit:[key]:[model]:window (String)
   - supreme_rate_limit:[key]:[model]:count (String)
   
7. Token刷新相关
   - refresh_attempts:[tier]:[account] (String)
   - refresh_cooldown:[tier]:[account] (String)
   - global_refresh_success_lock (String)
```

## 迁移方法

### 方法1：使用RDB持久化文件（推荐）

#### 在源服务器上备份
```bash
# 1. 手动触发RDB快照
redis-cli -p 6380 BGSAVE

# 2. 等待备份完成
redis-cli -p 6380 LASTSAVE

# 3. 找到RDB文件位置
redis-cli -p 6380 CONFIG GET dir
redis-cli -p 6380 CONFIG GET dbfilename

# 4. 复制RDB文件（通常在 /var/lib/redis/dump.rdb）
cp /var/lib/redis/dump.rdb ~/claude-route-ssl-backup.rdb
```

#### 在目标服务器上恢复
```bash
# 1. 停止Redis服务
sudo systemctl stop redis

# 2. 备份原有RDB文件（如果有）
sudo mv /var/lib/redis/dump.rdb /var/lib/redis/dump.rdb.bak

# 3. 复制新的RDB文件
sudo cp ~/claude-route-ssl-backup.rdb /var/lib/redis/dump.rdb

# 4. 设置正确的权限
sudo chown redis:redis /var/lib/redis/dump.rdb

# 5. 启动Redis服务
sudo systemctl start redis

# 6. 验证数据
redis-cli -p 6380 DBSIZE
```

### 方法2：使用AOF持久化文件

#### 在源服务器上
```bash
# 1. 启用AOF（如果未启用）
redis-cli -p 6380 CONFIG SET appendonly yes

# 2. 手动触发AOF重写
redis-cli -p 6380 BGREWRITEAOF

# 3. 找到AOF文件
redis-cli -p 6380 CONFIG GET dir
# 通常是 appendonly.aof
```

#### 在目标服务器上
```bash
# 1. 复制AOF文件到目标服务器
# 2. 配置Redis使用AOF
# 3. 重启Redis加载AOF文件
```

### 方法3：使用redis-dump工具

#### 安装redis-dump
```bash
gem install redis-dump
```

#### 导出数据
```bash
redis-dump -u redis://localhost:6380 > claude-route-ssl-redis.json
```

#### 导入数据
```bash
cat claude-route-ssl-redis.json | redis-load -u redis://localhost:6380
```

### 方法4：使用MIGRATE命令（在线迁移）

```bash
# 对每个key执行迁移
redis-cli -p 6380 --scan --pattern "*" | while read key; do
    redis-cli -p 6380 MIGRATE target_host 6380 "$key" 0 5000 COPY REPLACE
done
```

### 方法5：使用专用备份脚本

创建备份和恢复脚本（见下文）。

## 迁移前检查清单

- [ ] 确认源Redis版本和目标Redis版本兼容
- [ ] 检查目标服务器Redis配置（端口、内存等）
- [ ] 备份当前数据
- [ ] 记录数据量大小：`redis-cli -p 6380 INFO memory`
- [ ] 记录key数量：`redis-cli -p 6380 DBSIZE`

## 迁移后验证

```bash
# 1. 检查key数量
redis-cli -p 6380 DBSIZE

# 2. 验证关键数据
redis-cli -p 6380 keys "client_keys:*" | wc -l
redis-cli -p 6380 keys "*_products:*" | wc -l
redis-cli -p 6380 keys "*_pool:*" | wc -l

# 3. 测试一个具体的key
redis-cli -p 6380 hgetall "client_keys:sk-cli-v1-8d561c011ce7d096f759b23c1663dcb1aaec6a8f2750f79dd3d88ea3f8dd76cd"

# 4. 检查内存使用
redis-cli -p 6380 INFO memory
```

## 注意事项

1. **端口配置**：项目使用端口6380，确保目标服务器配置相同
2. **持久化策略**：建议同时启用RDB和AOF
3. **内存限制**：检查目标服务器Redis内存配置
4. **防火墙规则**：确保端口6380在目标服务器可访问
5. **数据一致性**：迁移期间停止写入操作

## 快速迁移命令

### 完整备份（源服务器）
```bash
# 创建备份目录
mkdir -p ~/redis-backup

# 触发备份
redis-cli -p 6380 BGSAVE

# 等待完成后复制文件
cp /var/lib/redis/dump.rdb ~/redis-backup/claude-route-$(date +%Y%m%d).rdb

# 导出key列表用于验证
redis-cli -p 6380 --scan --pattern "*" > ~/redis-backup/all-keys.txt
```

### 完整恢复（目标服务器）
```bash
# 停止Redis
sudo systemctl stop redis

# 备份原数据
sudo mv /var/lib/redis/dump.rdb /var/lib/redis/dump.rdb.old

# 复制新数据
sudo cp ~/claude-route-*.rdb /var/lib/redis/dump.rdb
sudo chown redis:redis /var/lib/redis/dump.rdb

# 启动Redis
sudo systemctl start redis

# 验证
redis-cli -p 6380 DBSIZE
```

## 故障排除

### 问题1：RDB文件版本不兼容
解决：使用redis-dump导出为JSON格式

### 问题2：内存不足
解决：增加Redis maxmemory配置或清理过期数据

### 问题3：端口冲突
解决：修改Redis配置文件中的端口设置

### 问题4：权限问题
解决：确保Redis用户对数据文件有读写权限

## 推荐迁移流程

1. **准备阶段**
   - 在目标服务器安装相同版本Redis
   - 配置Redis端口为6380
   - 测试Redis连接

2. **备份阶段**
   - 使用RDB备份当前数据
   - 导出key列表用于验证
   - 备份项目文件（/account/, /product/等）

3. **迁移阶段**
   - 停止源服务器上的服务
   - 传输RDB文件到目标服务器
   - 恢复Redis数据

4. **验证阶段**
   - 检查key数量
   - 测试关键功能
   - 监控日志

5. **切换阶段**
   - 更新DNS或负载均衡器
   - 监控新服务器运行状态
   - 保留源服务器备份一段时间