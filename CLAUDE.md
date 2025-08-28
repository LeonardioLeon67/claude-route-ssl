# Claude Route SSL - TypeScript OAuth代理服务器

基于TypeScript的Claude API代理服务器，支持OAuth认证、分级账户池管理和客户端密钥管理。

## 功能特点

- ✅ 自动添加 `anthropic-beta: oauth-2025-04-20` header支持OAuth认证
- ✅ 使用Bearer token (sk-ant-oat01-xxx) 访问Claude API  
- ✅ 客户端密钥管理系统 (sk-cli-v1-xxx格式)
- ✅ 分级账户池管理系统（Medium/High/Supreme）
- ✅ 动态负载均衡和slot分配
- ✅ 持久账户分配（无自动轮换）
- ✅ 完整的请求代理和错误处理
- ✅ 支持所有Claude模型
- ✅ 全局刷新锁机制（防止429错误）

## 快速开始

### 1. 安装依赖

```bash
npm install
```

### 2. 编译TypeScript

```bash
npm run build
```

### 3. 生成客户端密钥

使用 direct 命令生成不同级别的账户池密钥（推荐）：

```bash
direct medium    # 生成Medium级别密钥（账户池模式）
direct high      # 生成High级别密钥（账户池模式）  
direct supreme   # 生成Supreme级别密钥（账户池模式）
```

或者使用传统方式：
```bash
npm run generate-key
# 或
cd shell && ./generate-key.sh
```

输出示例：
```
API Key: sk-cli-v1-vEzwNywPwnZnWXL53bJ8YFv4tuG2vEyZ
```

### 4. 启动服务器

```bash
npm start
```

服务器将在 `http://0.0.0.0:8080` 启动

## 使用方法

### 客户端配置

客户端可以使用生成的密钥 (sk-cli-v1-xxx) 访问代理服务器：

```bash
# 使用 x-api-key header
curl -X POST http://YOUR_SERVER:8080/v1/messages \
  -H "x-api-key: sk-cli-v1-YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-haiku-20241022",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello"}]
  }'

# 或使用 Authorization header
curl -X POST http://YOUR_SERVER:8080/v1/messages \
  -H "Authorization: Bearer sk-cli-v1-YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{...}'
```

## 分级账户池系统

### 概述

系统支持四个级别的账户池，每个级别有不同的slot配置和请求限制：

- **Trial级别**：每账户7个slot，只能使用Sonnet模型（每5小时42次限制），1天有效期
- **Medium级别**：每账户7个slot，只能使用Sonnet模型（每5小时42次限制），30天有效期
- **High级别**：每账户3个slot，有模型请求限制  
- **Supreme级别**：每账户2个slot，有更高的模型请求限制

### 目录结构

账户按级别分目录存储：
```
/account/
├── trial/      # Trial级别账户 (每账户7个slot，只能用Sonnet，42次/5小时，1天有效)
├── medium/     # Medium级别账户 (每账户7个slot，只能用Sonnet，42次/5小时，30天有效)
├── high/       # High级别账户 (每账户3个slot)
└── supreme/    # Supreme级别账户 (每账户2个slot)
```

### 生成产品密钥

#### 方法一：使用 direct 命令（推荐）

```bash
direct medium    # 使用Medium账户池生成密钥
direct high      # 使用High账户池生成密钥  
direct supreme   # 使用Supreme账户池生成密钥
```

#### 方法二：使用脚本命令

```bash
# 默认使用账户池模式
cd shell && ./medium.sh     # Medium级别（账户池）
cd shell && ./high.sh       # High级别（账户池）
cd shell && ./supreme.sh    # Supreme级别（账户池）

# 绑定到特定账户
cd shell && ./medium.sh [account-name]   # 绑定到指定Medium账户
cd shell && ./high.sh [account-name]     # 绑定到指定High账户
cd shell && ./supreme.sh [account-name]  # 绑定到指定Supreme账户
```

### 各级别详细配置

#### Trial级别
- **Slot配置**：每个账户7个位置
- **请求限制**：
  - 只允许使用Sonnet系列模型
  - Sonnet系列：每5小时42次
  - 其他模型：不允许使用
- **有效期**：1天
- **适用场景**：试用体验
- **账户目录**：`/account/trial/`

#### Medium级别
- **Slot配置**：每个账户7个位置
- **请求限制**：
  - 只允许使用Sonnet系列模型
  - Sonnet系列：每5小时42次
  - 其他模型：不允许使用
- **有效期**：30天
- **适用场景**：标准使用
- **账户目录**：`/account/medium/`

#### High级别  
- **Slot配置**：每个账户3个位置
- **请求限制**：
  - Opus系列：每5小时10次
  - Sonnet系列：每5小时50次
  - 其他模型：无限制
- **适用场景**：中等强度使用
- **账户目录**：`/account/high/`

#### Supreme级别
- **Slot配置**：每个账户2个位置  
- **请求限制**：
  - Opus系列：每5小时15次
  - Sonnet系列：每5小时75次
  - 其他模型：无限制
- **适用场景**：高强度使用
- **账户目录**：`/account/supreme/`

### 模型识别规则

- **Opus系列**：模型名包含`opus`的所有模型（如 claude-opus-4、claude-3-opus、opus-latest等）
- **Sonnet系列**：模型名包含`sonnet`的所有模型（如 claude-sonnet-4、claude-3-sonnet、sonnet-preview等）
- **其他模型**：Haiku、Instant等（Trial和Medium级别不可用）

### 账户池分配机制

- **分配策略**：优先选择slot占用最少的账户
- **负载均衡**：动态分配，确保各账户负载均匀
- **持久分配**：密钥一旦分配账户后永久绑定，不会自动轮换
- **黑名单管理**：当账户被标记为黑名单时，已绑定的密钥将在下次请求时重新分配

### 数据存储位置

- **产品文件**：`/product/medium.json`、`/product/high.json`、`/product/supreme.json`
- **Redis存储**：
  - 客户端密钥：`client_keys:[key]`
  - 产品记录：`medium_products:[key]`、`high_products:[key]`、`supreme_products:[key]`
  - Slot计数：`medium_pool:slots:[account]`、`high_pool:slots:[account]`、`supreme_pool:slots:[account]`
  - 永久绑定：`permanent_binding:[tier]` - 存储密钥与账户的绑定关系
  - 黑名单记录：`account_blacklist:[tier]:[account]` - 账户黑名单状态

## 管理命令

### Direct 命令工具

全局管理工具，位于 `/home/leon/bin/direct`：

```bash
direct run        # 启动Claude Route SSL项目
direct restart    # 重启Claude Route SSL项目  
direct stop       # 停止Claude Route SSL项目
direct status     # 查看项目状态
direct medium     # 生成Medium级别产品密钥（账户池）
direct high       # 生成High级别产品密钥（账户池）
direct supreme    # 生成Supreme级别产品密钥（账户池）
direct pool       # 查看账户池状态和slot使用情况
direct recover    # 恢复黑名单账户：direct recover <account_name>
direct sync       # 手动触发完全同步机制
direct logs       # 查看PM2日志
direct monitor    # 打开PM2监控面板
direct help       # 显示帮助信息
```

### 账户Token管理

账户token按级别分目录存储：
- Medium级别：`/account/medium/[账户名].json`
- High级别：`/account/high/[账户名].json`  
- Supreme级别：`/account/supreme/[账户名].json`

**更新方式：**
1. 直接编辑对应级别目录下的账户JSON文件
2. 系统会自动刷新即将过期的token（过期前1分钟）
3. 支持分级目录结构的自动搜索和加载

## 工作原理

### 账户池模式流程

1. **客户端请求**：使用 sk-cli-v1-xxx 格式的密钥
2. **密钥验证**：服务器验证客户端密钥并识别级别（Medium/High/Supreme）
3. **账户分配**：
   - 检查密钥是否已永久绑定到某个账户
   - 如已绑定，检查该账户是否被列入黑名单
   - 如未绑定或账户被黑名单，从对应级别账户池中选择slot占用最少的账户
   - 更新slot计数和永久绑定记录
4. **请求限制检查**：根据级别检查5小时窗口内的模型请求次数（High/Supreme）
5. **Token获取**：从分配的账户获取有效的OAuth Bearer token
6. **添加Beta Header**：自动添加 `anthropic-beta: oauth-2025-04-20`
7. **代理请求**：转发到Claude API
8. **返回响应**：将Claude API响应返回给客户端

### 分配机制

- **分配原则**：首次使用时分配账户，之后永久绑定
- **持续性**：密钥一旦分配账户后永久绑定，不会自动轮换
- **负载均衡**：新密钥优先分配到slot占用较少的账户
- **故障转移**：当绑定的账户被黑名单时，系统会自动重新分配到可用账户

## 端口配置

默认端口：8080

如需修改，编辑 `src/proxy-server.ts` 中的 `PORT` 常量

## 故障排除

### 密钥相关问题

#### "Unauthorized API key"
- 检查客户端密钥是否已注册
- 使用 `direct medium/high/supreme` 生成新密钥
- 确保密钥状态为 Active
- 检查密钥是否已过期

#### "Invalid API key format"  
- 确保使用 sk-cli-v1-xxx 格式的密钥
- 不要使用原始的 sk-ant-oat01-xxx token

### 账户池相关问题

#### "Trial/Medium tier can only use Sonnet models"
- Trial和Medium级别只能使用包含"sonnet"的模型
- 如需使用其他模型（如Opus、Haiku等），请升级到High或Supreme级别

#### "All [Tier] accounts are at capacity"
- 说明该级别所有账户都达到了slot上限
- 等待其他客户端释放slot（密钥过期或主动释放）
- 考虑添加更多账户到对应级别目录

#### "No [Tier] accounts available in pool"
- 对应级别目录中没有账户文件
- 检查 `/account/medium/`、`/account/high/`、`/account/supreme/` 目录
- 确保账户JSON文件包含有效的OAuth凭证

### Token相关问题

#### "OAuth token has expired"
- 编辑对应级别目录下的账户JSON文件更新token
- 重启服务器以应用新token：`direct restart`
- 系统会自动刷新即将过期的token（过期前1分钟）

### 限制相关问题

#### "Rate limit exceeded for [Model]"
- High/Supreme级别达到了5小时窗口限制
- 等待时间窗口重置或使用其他模型
- Opus系列和Sonnet系列有独立的限制计数

### 黑名单相关问题

#### 账户被自动加入黑名单
- **触发条件**：当账户返回authentication_error、Invalid bearer token或revoke等认证错误时
- **处理方式**：系统会自动将该账户加入黑名单，已绑定的密钥会在下次请求时重新分配
- **恢复方法**：使用 `direct recover <account_name>` 命令从黑名单中移除账户

#### 检查黑名单状态
- 使用 `direct pool` 查看当前黑名单账户列表
- 黑名单账户不会参与新的slot分配
- 系统会显示"Refresh Failed Status"部分显示刷新失败的账户

### 刷新锁机制

系统实现了全局刷新锁机制，防止因同时刷新多个账户导致的Cloudflare 429错误。

#### 🔒 全局成功锁（60秒保护期）
- **工作原理**：只有当某个账户刷新**成功**时，才设置60秒全局锁
- **锁目的**：防止刚刚成功刷新后，其他账户立即又发起刷新请求
- **锁超时**：60秒自动释放
- **Redis键名**：`global_refresh_success_lock`

#### 📊 失败计数机制
刷新失败包括以下所有情况，每种都计为一次尝试：
1. **被全局成功锁阻止** - 60秒内已有其他账户刷新成功
2. **官方API连接失败** - 网络错误或服务器异常
3. **凭证加载失败** - 账户文件问题
4. **API响应异常** - 响应格式错误等

#### 🧊 冷却和限制策略
- **最大尝试次数**：每个账户24小时内最多3次
- **冷却时间**：失败后3分钟内不允许再次尝试
- **计数重置**：刷新成功后重置该账户的失败计数

#### 🔄 工作流程
```
1. 检查账户尝试次数 (≤3次/24小时)
2. 检查账户冷却时间 (≥3分钟间隔)
3. 检查全局成功锁 (60秒内是否有成功刷新)
   ├─ 无锁 → 发送刷新请求到官方API
   └─ 有锁 → 计数+1，设置3分钟冷却
4. API请求处理
   ├─ 刷新成功 → 重置失败计数，设置60秒全局成功锁
   └─ 刷新失败 → 计数+1，设置3分钟冷却（不设置全局锁）
```

#### ⚡ 关键优势
- **防止429错误**：成功刷新后给官方API 60秒缓冲时间
- **智能节流**：只有成功才设锁，失败不影响其他账户立即尝试
- **自动降级**：失败账户自动进入冷却，不阻塞其他账户
- **避免浪费**：成功后短期内不再发起无意义的刷新请求

### 完全同步机制

系统实现了完全同步机制，确保Redis中的账户调度数据与文件系统中的账户文件保持一致。

#### 🔄 同步工作流程
```
服务启动时
    ↓
执行首次完全同步
    ↓
┌─────────────────────────────────┐
│  每4小时自动触发：              │
│  1. 扫描 /account/ 目录树       │
│  2. 获取文件系统中的账户列表    │
│  3. 获取Redis中的调度记录       │
│  4. 清理Redis中多余的账户数据   │
│  5. 为所有文件系统账户设置定时器│
└─────────────────────────────────┘
    ↓
继续4小时循环...
```

#### 🧹 同步操作详解
1. **文件系统扫描**：递归扫描所有级别目录(medium/high/supreme)下的.json文件
2. **Redis数据清理**：删除不存在于文件系统的账户的所有Redis记录
   - 清理slot计数：`${tier}_pool:slots:${account}`
   - 清理黑名单记录：`account_blacklist:${tier}:${account}`
   - 清理永久绑定：从`${tier}_pool:permanent_binding`中移除不存在账户的绑定
3. **定时器重置**：清除现有定时器，为所有文件系统账户重新设置刷新定时器
4. **完全一致性**：确保Redis调度记录与文件系统账户完全匹配

#### 🔧 手动同步命令
```bash
direct sync       # 手动触发完全同步（可立即查看效果）
```

#### ⚡ 关键优势
- **数据一致性**：Redis与文件系统100%同步，杜绝不一致状态
- **自动清理**：删除的账户文件会自动清理对应的Redis数据和永久绑定关系
- **新账户检测**：新添加的账户文件会自动设置刷新定时器
- **定期维护**：每4小时自动执行，无需人工干预
- **资源优化**：清理无效数据，避免资源浪费
- **即时生效**：支持手动触发，立即查看同步效果

## 支持的Claude模型

- claude-3-5-haiku-20241022
- claude-opus-4-20250101 (Opus 4.1)
- claude-3-opus-20240229
- claude-3-sonnet-20240229
- claude-3-haiku-20240307
- 其他Claude API支持的模型

## NPM Scripts

- `npm run build` - 编译TypeScript
- `npm start` - 启动服务器
- `npm run dev` - 开发模式（使用ts-node）
- `npm run watch` - 监视模式编译

## 文件结构

```
claude-route-ssl/
├── src/
│   ├── proxy-server.ts         # TypeScript代理服务器主程序
│   ├── token-refresher-redis.ts # Redis Token管理器
│   └── multi-account-manager.ts # 多账户管理器
├── shell/
│   ├── medium.sh               # Medium级别产品密钥生成（账户池）
│   ├── high.sh                 # High级别产品密钥生成（账户池）
│   ├── supreme.sh              # Supreme级别产品密钥生成（账户池）
│   ├── pool.sh                 # 账户池状态监控脚本
│   ├── recover.sh              # 黑名单账户恢复脚本
│   ├── run.sh                  # 启动服务器脚本
│   ├── restart.sh              # 重启服务器脚本
│   ├── stop.sh                 # 停止服务器脚本
│   └── status.sh               # 状态检查脚本
├── account/                    # 分级账户管理目录
│   ├── medium/                 # Medium级别账户 (1 slot/account)
│   │   └── [账户名].json       
│   ├── high/                   # High级别账户 (4 slots/account)  
│   │   └── [账户名].json       
│   └── supreme/                # Supreme级别账户 (3 slots/account)
│       └── [账户名].json       
├── product/                    # 产品管理目录
│   ├── medium.json             # Medium级别产品记录
│   ├── high.json               # High级别产品记录
│   └── supreme.json            # Supreme级别产品记录
├── dist/                       # 编译后的JavaScript文件
├── logs/                       # 日志目录
│   ├── forward-monitor.log     # 转发监控日志
│   ├── pm2-out.log             # PM2输出日志
│   ├── pm2-error.log           # PM2错误日志
│   └── pm2-combined.log        # PM2合并日志
├── package.json
├── tsconfig.json
└── CLAUDE.md                   # 项目说明文档
```

### 全局管理工具

```
/home/leon/bin/direct           # 全局管理命令
```

## 监控和日志

### 日志查看

```bash
direct logs              # 查看PM2日志
direct monitor           # 打开PM2监控面板
direct status            # 查看服务状态（包含定时器状态）
tail -f logs/pm2-combined.log # 实时查看完整日志（推荐）
tail -f logs/pm2-out.log # 实时查看输出日志
```

### Token刷新日志监控

```bash
# 实时监控刷新活动（推荐）
tail -f logs/pm2-combined.log | grep -E "(🎯|✅.*刷新|❌.*刷新|Token刷新完成)"

# 查看最近刷新历史
grep -E "(🎯.*定时器触发|✅.*刷新成功|Token刷新完成)" logs/pm2-combined.log | tail -20

# 查看刷新失败记录
grep -E "(❌.*刷新|失败|🔒.*全局锁|🧊.*冷却)" logs/pm2-combined.log | tail -10

# 按账户查看刷新状态
grep "账户名" logs/pm2-combined.log | grep -E "(刷新|refresh)"
```

### 关键日志信息

#### 业务日志
- **账户池分配**：`assigned to account: [account] (slots: X/Y)`
- **slot使用情况**：`using assigned account: [account] (slots: X/Y)`  
- **请求限制检查**：`rate limit check passed: X/Y requests`
- **黑名单检测**：`永久绑定的账户 [account] 已被加入黑名单，清除绑定`
- **黑名单触发**：`Adding [account] to blacklist: [reason]`

#### 刷新机制日志
- **定时器触发**：`🎯 账户 [account] 定时器触发: 开始刷新`
- **刷新成功**：`✅ 刷新成功，重置计数器，设置60秒全局成功锁`
- **刷新完成**：`🎉 Token刷新完成，所有存储位置已立即同步: [account]`
- **全局锁阻止**：`🔒 60秒内已有账户刷新成功，还需等待 X 秒`
- **冷却期阻止**：`🧊 冷却中，还需等待 X 秒`
- **下轮定时器**：`⏰ 为账户 [account] 设置定时器`

### 定时器状态检查

定时器状态已集成到 `direct status` 命令中：

```bash
direct status
```

显示信息包括：
- **活跃定时器数量**：当前设置的自动刷新定时器个数
- **下次刷新时间**：最近一个账户的刷新计划
- **服务运行状态**：PM2进程、Redis、Nginx等状态

### 性能监控

- 请求响应时间通常在800-1500ms
- Medium级别无请求计数开销
- High/Supreme级别有5小时窗口限制检查
- 刷新过程通常在200-500ms内完成

## 安全注意事项

- 保护好 `/account/` 目录中的分级账户文件
- 定期轮换客户端密钥
- 不要暴露原始的OAuth token
- 定期监控访问日志检查异常访问
- 使用防火墙限制访问来源
- 监控各级别账户池的slot使用情况

## 快速恢复服务

```bash
direct restart           # 重启服务（推荐）
# 或
npm start               # 传统启动方式
```

## 系统架构总结

### 核心特性

1. **分级账户池系统**：Trial(7)/Medium(7)/High(3)/Supreme(2) slot配置
2. **智能负载均衡**：基于slot占用的动态分配算法
3. **永久绑定机制**：密钥与账户永久绑定，不会自动轮换
4. **黑名单故障转移**：账户故障时自动重新分配，保证服务连续性
5. **分级请求限制**：High/Supreme有5小时窗口模型限制
6. **实时监控工具**：`direct pool` 显示slot使用和黑名单状态
7. **全局管理工具**：direct命令简化操作
8. **自动token刷新**：过期前1分钟自动刷新OAuth token
9. **完全同步机制**：每4小时扫描文件系统，确保Redis与账户文件夹完全一致，支持手动触发

### 最佳实践

- **推荐使用**：`direct medium/high/supreme` 生成账户池密钥
- **账户分布**：不同级别账户放在对应级别目录下
- **监控方式**：使用 `direct pool` 查看实时slot使用和黑名单状态
- **日志监控**：使用 `direct logs` 查看详细分配和错误日志
- **容量规划**：根据slot数量规划账户数量和并发用户
- **故障处理**：定期检查黑名单状态，及时恢复可用账户

### 升级亮点

✅ **从单一Medium级别扩展到三级别系统**  
✅ **从固定slot到多级别可配置slot数量**  
✅ **从单一模式扩展到账户池+单账户双模式**  
✅ **从手动管理升级到全自动化管理**  
✅ **从基础功能升级到企业级负载均衡**  
✅ **从定时轮换升级到永久绑定机制**  
✅ **增加黑名单管理和故障转移能力**  
✅ **完善的实时监控和恢复工具**

## 重要说明

- **优先使用账户池模式**：提供更好的负载均衡和故障转移能力
- **永久绑定机制**：密钥与账户保持稳定的绑定关系，无需担心频繁轮换
- **自动故障转移**：黑名单账户会被自动跳过，保证服务连续性
- **实时监控**：使用 `direct pool` 随时查看系统状态
- **分级目录结构**：便于账户管理和扩展
- **系统已支持生产环境的高并发需求**
- **自动化运维**：定时器自动循环，服务启动后无需人工干预