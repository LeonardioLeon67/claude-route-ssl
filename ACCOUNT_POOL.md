# Medium账户池功能使用指南

## 功能概述

Medium级别密钥支持智能账户池模式：
- 每个账户有**2个占用位置**上限
- 密钥首次使用时自动分配到未满的账户
- 每24小时轮换时，重新选择可用账户
- 自动管理账户占用状态，确保负载均衡

## 使用方法

### 1. 生成账户池密钥

#### 默认方式（推荐）
```bash
cd shell
./medium.sh
# 或
./medium.sh pool
```

#### 指定有效期
```bash
./medium.sh pool 60  # 生成60天有效期的账户池密钥
```

### 2. 生成绑定特定账户的密钥（传统方式）

如果您仍想将密钥绑定到特定账户：
```bash
./medium.sh jasonlucy8160-outlook      # 绑定到特定账户
./medium.sh jasonlucy8160-outlook 30   # 绑定到特定账户，30天有效期
```

## 账户池工作原理

1. **密钥识别**：系统检测到密钥的`use_pool`标记为`true`时，启用账户池模式

2. **占用位置管理**：
   - 每个账户最多被2个密钥同时占用
   - Redis中记录每个账户的占用数：`medium_pool:slots:{account_name}`
   - 新密钥或轮换时，选择占用最少的账户

3. **24小时轮换机制**：
   - 每个密钥独立计时，24小时后触发轮换
   - 轮换时释放旧账户的占用位置
   - 重新选择占用最少的可用账户
   - 更新占用计数

4. **智能分配算法**：
   - 优先选择占用数为0的账户
   - 其次选择占用数为1的账户
   - 所有账户满载时返回503错误

5. **自动故障恢复**：
   - 账户文件删除时自动释放占用并选择新账户
   - 透明切换，客户端无感知

## 配置账户池

### 添加账户到池中
将账户JSON文件放入`/account/medium/`目录：
```bash
cp /path/to/account.json /home/leon/claude-route-ssl/claude-route-ssl/account/medium/
```

### 查看池中账户
```bash
ls -la /home/leon/claude-route-ssl/claude-route-ssl/account/medium/
```

## 优势

- **负载均衡**：每24小时自动轮换账户，均衡使用
- **统一管理**：同级别密钥使用相同账户，便于管理
- **高可用性**：账户故障时自动切换到下一个
- **简化配置**：无需为每个密钥指定账户
- **可预测性**：24小时固定周期，便于维护

## 监控日志

账户池使用情况会记录在日志中：
```
# 首次选择或轮换账户时
[2025-08-14T14:00:00.000Z] 🔄 Pool: Rotated to account: account-name (will rotate in 24 hours)
[2025-08-14T14:00:00.100Z] 📝 Previous account was: previous-account

# 继续使用当前账户时
[2025-08-14T15:00:00.000Z] 📌 Pool: Using current account: account-name (23 hours until rotation)
[2025-08-14T15:00:00.100Z] ✅ Successfully obtained token from pool account: account-name
```

## 查看账户池状态

### 使用监控脚本（推荐）
```bash
cd shell
./pool-status.sh
```

显示：
- 每个账户的占用状态（可视化进度条）
- 总体使用统计
- 活跃密钥的轮换倒计时

### 手动查询Redis

查看账户占用情况：
```bash
# 查看特定账户的占用数
redis-cli -p 6380 get "medium_pool:slots:account_name"

# 查看所有账户占用
redis-cli -p 6380 keys "medium_pool:slots:*" | xargs -I {} sh -c 'echo -n "{}: "; redis-cli -p 6380 get "{}"'
```

查看密钥轮换状态：
```bash
# 查看特定密钥的轮换信息
redis-cli -p 6380 hgetall "key_rotation:sk-cli-v1-xxxxx"
```

返回信息：
- `account`: 当前使用的账户
- `next_rotation`: 下次轮换时间（毫秒时间戳）
- `last_rotation`: 上次轮换时间
- `previous_account`: 上一个账户

## 限制

- 仅Medium级别支持账户池
- High和Supreme级别仍需绑定特定账户（因为有请求限制）
- 账户池要求`/account/medium/`目录至少有一个有效账户

## 示例场景

### 场景1：开发团队共享密钥
生成一个账户池密钥，团队成员共享使用，系统自动从多个账户中轮换。

### 场景2：API服务负载均衡
为API服务生成账户池密钥，实现请求自动分散到多个Claude账户。

### 场景3：避免单点故障
使用账户池，即使某个账户token过期或出现问题，其他账户仍可正常服务。