# Claude Route SSL - TypeScript OAuth代理服务器

基于TypeScript的Claude API代理服务器，支持OAuth认证和客户端密钥管理。

## 功能特点

- ✅ 自动添加 `anthropic-beta: oauth-2025-04-20` header支持OAuth认证
- ✅ 使用Bearer token (sk-ant-oat01-xxx) 访问Claude API  
- ✅ 客户端密钥管理系统 (sk-cli-v1-xxx格式)
- ✅ 完整的请求代理和错误处理
- ✅ 支持所有Claude模型

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

## 密钥管理

### 生成产品密钥

生成不同级别的产品密钥：
```bash
cd shell && ./medium.sh [account-name]   # 生成Medium级别密钥（无限制）
cd shell && ./high.sh [account-name]     # 生成High级别密钥（模型限制）
cd shell && ./supreme.sh [account-name]  # 生成Supreme级别密钥（更高限制）
```

#### 各级别限制说明：
- **Medium级别**：无请求次数限制，适合轻度使用
- **High级别**：Opus系列每5小时45次，Sonnet系列每5小时180次
- **Supreme级别**：Opus系列每5小时60次，Sonnet系列每5小时240次

#### 模型识别规则：
- **Opus系列**：模型名包含`opus`的所有模型（如 claude-opus-4、claude-3-opus、opus-latest等）
- **Sonnet系列**：模型名包含`sonnet`的所有模型（如 claude-sonnet-4、claude-3-sonnet、sonnet-preview等）
- **其他模型**：无限制（如 claude-3-5-haiku、claude-instant等）

密钥数据存储位置：
- 产品：`/product/medium.json` 和 `/product/high.json`
- Redis：`client_keys:[key]` 和 `medium_products:[key]` / `high_products:[key]`

## 更新Account Token

账户token现在存储在 `/account/` 目录中，每个账户一个JSON文件。
更新方式：
1. 直接编辑 `/account/[账户名].json` 文件
2. 系统会自动刷新即将过期的token（过期前1分钟）

## 工作原理

1. **客户端请求**：使用 sk-cli-v1-xxx 格式的密钥
2. **密钥验证**：服务器验证客户端密钥是否有效
3. **Token转换**：将请求转换为使用OAuth Bearer token
4. **添加Beta Header**：自动添加 `anthropic-beta: oauth-2025-04-20`
5. **代理请求**：转发到Claude API
6. **返回响应**：将Claude API响应返回给客户端

## 端口配置

默认端口：8080

如需修改，编辑 `src/proxy-server.ts` 中的 `PORT` 常量

## 故障排除

### "Unauthorized API key"
- 检查客户端密钥是否已注册
- 使用 `medium.sh` 或 `high.sh` 生成新密钥
- 确保密钥状态为 Active

### "OAuth token has expired"  
- 编辑 `/account/[账户名].json` 更新token
- 重启服务器以应用新token

### "Invalid API key format"
- 确保使用 sk-cli-v1-xxx 格式的密钥
- 不要使用原始的 sk-ant-oat01-xxx token

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
│   └── proxy-server.ts     # TypeScript代理服务器主程序
├── shell/
│   ├── medium.sh           # Medium级别产品密钥生成
│   ├── high.sh             # High级别产品密钥生成
│   └── supreme.sh          # Supreme级别产品密钥生成
├── account/                # 多账户管理目录
│   └── [账户名].json       # 各账户OAuth凭证
├── product/                # 产品管理目录
│   ├── medium.json         # Medium级别产品记录
│   ├── high.json           # High级别产品记录
│   └── supreme.json        # Supreme级别产品记录
├── dist/                   # 编译后的JavaScript文件
├── logs/                   # 日志目录
│   └── forward-monitor.log # 转发监控日志
├── package.json
└── tsconfig.json
```

## 安全注意事项

- 保护好 `/account/` 目录中的账户文件
- 定期轮换客户端密钥
- 不要暴露原始的OAuth token
- 定期监控访问日志检查异常访问
- 使用防火墙限制访问来源

## 快速恢复服务

运行 `npm start` 启动代理服务器

## 重要说明

- 不要在文件中创建不必要的文档
- 只编辑现有文件，不要创建新文件
- 遵循现有的代码风格和约定