# 客户端配置说明

## 重要提示
Claude API 使用 **x-api-key** 认证，**不支持 OAuth 认证**。

## 正确的请求格式

### 必需的请求头
```
Content-Type: application/json
x-api-key: sk-ant-api03-xxxxx  (你的实际API密钥)
anthropic-version: 2023-06-01
```

### 错误的认证方式 ❌
- 不要使用 `Authorization: Bearer xxx`
- 不要使用 OAuth 认证
- 不要使用 `api-key` (应该是 `x-api-key`)

## 客户端配置示例

### 1. 使用 curl
```bash
curl -X POST http://localhost:8080/B6444B4FB0657AC1/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: sk-ant-api03-xxxxx" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-haiku-20240307",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### 2. Python 示例
```python
import requests

url = "http://localhost:8080/B6444B4FB0657AC1/v1/messages"
headers = {
    "Content-Type": "application/json",
    "x-api-key": "sk-ant-api03-xxxxx",  # 你的API密钥
    "anthropic-version": "2023-06-01"
}
data = {
    "model": "claude-3-haiku-20240307",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello"}]
}

response = requests.post(url, headers=headers, json=data)
print(response.json())
```

### 3. JavaScript/Node.js 示例
```javascript
const axios = require('axios');

const url = 'http://localhost:8080/B6444B4FB0657AC1/v1/messages';
const headers = {
    'Content-Type': 'application/json',
    'x-api-key': 'sk-ant-api03-xxxxx',  // 你的API密钥
    'anthropic-version': '2023-06-01'
};
const data = {
    model: 'claude-3-haiku-20240307',
    max_tokens: 100,
    messages: [{ role: 'user', content: 'Hello' }]
};

axios.post(url, data, { headers })
    .then(response => console.log(response.data))
    .catch(error => console.error(error));
```

### 4. 使用第三方工具（如 Postman, Insomnia）
1. 设置请求方法为 `POST`
2. URL: `http://localhost:8080/B6444B4FB0657AC1/v1/messages`
3. Headers:
   - `Content-Type`: `application/json`
   - `x-api-key`: `sk-ant-api03-xxxxx`
   - `anthropic-version`: `2023-06-01`
4. Body (JSON):
```json
{
    "model": "claude-3-haiku-20240307",
    "max_tokens": 100,
    "messages": [
        {
            "role": "user",
            "content": "Hello"
        }
    ]
}
```

## 常见错误及解决方法

### 错误: "OAuth authentication is currently not supported"
**原因**: 使用了 Authorization: Bearer 头
**解决**: 改用 `x-api-key` 头

### 错误: "invalid x-api-key"
**原因**: API密钥无效或格式错误
**解决**: 
- 确保使用正确的Claude API密钥
- 密钥格式应为: `sk-ant-api03-xxxxx`
- 不要在密钥前加 "Bearer " 或其他前缀

### 错误: "missing anthropic-version header"
**原因**: 缺少版本头
**解决**: 添加 `anthropic-version: 2023-06-01`

## 测试你的配置

使用提供的测试脚本：
```bash
./test-api.sh sk-ant-api03-xxxxx
```

## 支持的模型
- claude-3-opus-20240229
- claude-3-sonnet-20240229
- claude-3-haiku-20240307
- claude-2.1
- claude-2.0
- claude-instant-1.2

## 获取API密钥
访问 https://console.anthropic.com/account/keys 获取你的API密钥