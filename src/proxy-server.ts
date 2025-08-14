import express from 'express';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
import TokenRefresherRedis from './token-refresher-redis';
import MultiAccountManager from './multi-account-manager';
import { createClient, RedisClientType } from 'redis';

const app = express();
const PORT = 8080;
const tokenRefresher = new TokenRefresherRedis();
const accountManager = new MultiAccountManager();

// Redis client for client key validation
let redisClient: RedisClientType;
const REDIS_PORT = 6380;

// 中间件配置
app.use(express.json({ limit: '50mb' }));
app.use(express.text({ limit: '50mb' }));
app.use(express.raw({ limit: '50mb', type: '*/*' }));

// CORS中间件 - 允许所有来源
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization, x-api-key, anthropic-version, anthropic-beta');
  
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});


// Initialize Redis connection
async function initRedis() {
  redisClient = createClient({
    socket: {
      port: REDIS_PORT,
      host: 'localhost'
    }
  });
  
  redisClient.on('error', (err) => {
    console.error(`[${new Date().toISOString()}] Redis Client Error:`, err);
  });
  
  redisClient.on('connect', () => {
    console.log(`[${new Date().toISOString()}] Proxy server connected to Redis on port ${REDIS_PORT}`);
  });
  
  try {
    await redisClient.connect();
  } catch (error) {
    console.error(`[${new Date().toISOString()}] Failed to connect to Redis:`, error);
  }
}


// 🔥 获取access token - 零延迟，立即同步最新token
async function getAccessToken(accountName?: string): Promise<string> {
  const now = Date.now();
  
  if (accountName) {
    console.log(`[${new Date().toISOString()}] 🔍 获取账户token: ${accountName}`);
    
    // 🔥 步骤1: 获取账户信息，检查是否需要刷新
    const account = await accountManager.getAccount(accountName);
    if (account && account.credentials.accessToken) {
      const oneMinuteBeforeExpiry = account.credentials.expiresAt - 60000;
      const minutesLeft = Math.floor((account.credentials.expiresAt - now) / 60000);
      
      console.log(`[${new Date().toISOString()}] 📊 Token状态检查: ${accountName}`);
      console.log(`  🔑 当前Token: ${account.credentials.accessToken.substring(0, 30)}...`);
      console.log(`  ⏰ 剩余时间: ${minutesLeft} 分钟`);
      console.log(`  🚨 需要刷新: ${now >= oneMinuteBeforeExpiry ? 'YES' : 'NO'}`);
      
      // 🔥 步骤2: 如果需要刷新，立即刷新并强制重载
      if (now >= oneMinuteBeforeExpiry) {
        console.log(`[${new Date().toISOString()}] 🔄 立即刷新token: ${accountName}`);
        const refreshSuccess = await tokenRefresher.refreshToken(accountName);
        
        if (refreshSuccess) {
          // 🔥 强制重新加载以获取最新token - 绝对不能有延迟！
          console.log(`[${new Date().toISOString()}] 🚀 强制重载最新token数据: ${accountName}`);
          const refreshedAccount = await accountManager.getAccount(accountName, true);
          
          if (refreshedAccount?.credentials.accessToken) {
            const newToken = refreshedAccount.credentials.accessToken;
            console.log(`[${new Date().toISOString()}] ✅ 新token已获取: ${newToken.substring(0, 30)}...`);
            console.log(`[${new Date().toISOString()}] 🎯 立即返回新token给新连接`);
            return newToken;
          } else {
            console.error(`[${new Date().toISOString()}] ❌ 刷新后未能获取新token!`);
          }
        } else {
          console.error(`[${new Date().toISOString()}] ❌ Token刷新失败!`);
        }
      }
      
      // 🔥 步骤3: 返回当前token（如果不需要刷新或刷新失败）
      // 再次强制重载以确保获取最新token（可能被其他刷新进程更新了）
      const latestAccount = await accountManager.getAccount(accountName, true);
      const finalToken = latestAccount?.credentials.accessToken || account.credentials.accessToken;
      console.log(`[${new Date().toISOString()}] 📤 返回最新token: ${finalToken.substring(0, 30)}...`);
      return finalToken;
    } else {
      console.error(`[${new Date().toISOString()}] ❌ 未找到账户或token: ${accountName}`);
    }
  }
  
  // 🔥 步骤4: 回退到默认行为（但优先使用最新数据）
  console.log(`[${new Date().toISOString()}] 🔄 回退到默认token获取方式`);
  
  // 先尝试从缓存获取（如果没过期）
  const cachedToken = tokenRefresher.getCachedAccessToken();
  if (cachedToken) {
    console.log(`[${new Date().toISOString()}] 📋 使用缓存token: ${cachedToken.substring(0, 30)}...`);
    return cachedToken;
  }
  
  // 强制获取最新credentials
  const currentToken = await tokenRefresher.getCurrentAccessToken();
  if (currentToken) {
    console.log(`[${new Date().toISOString()}] 📁 使用最新token: ${currentToken.substring(0, 30)}...`);
    return currentToken;
  }
  
  console.error(`[${new Date().toISOString()}] ❌ 无法获取任何有效token!`);
  return '';
}

// 验证客户端密钥格式
function isValidClientKey(key: string): boolean {
  return Boolean(key && key.startsWith('sk-cli-v1-'));
}

// 代理处理 - 参考 forward-monitor.ts 的实现
async function proxyRequest(req: express.Request, res: express.Response) {
  const startTime = Date.now();
  
  try {
    // 获取客户端密钥
    const clientKey = req.headers['x-api-key'] as string || 
                     req.headers['authorization']?.replace('Bearer ', '') as string;
    
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl || req.url}`);
    console.log('Client headers:', {
      'x-api-key': req.headers['x-api-key'] ? 'sk-cli-v1-...' : undefined,
      'authorization': req.headers['authorization'] ? req.headers['authorization'].substring(0, 30) + '...' : undefined,
    });
    
    if (!clientKey) {
      return res.status(401).json({
        type: 'error',
        error: {
          type: 'authentication_error',
          message: 'Missing API key. Please provide x-api-key header or Authorization header.'
        }
      });
    }

    // 验证密钥格式
    if (!isValidClientKey(clientKey)) {
      return res.status(401).json({
        type: 'error',
        error: {
          type: 'authentication_error',
          message: 'Invalid API key format. Expected format: sk-cli-v1-...'
        }
      });
    }

    // 检查密钥映射 - 优先从Redis获取
    let accountName: string | null = null;
    let keyValid = false;
    let keyData: any = {};
    
    // Try Redis first
    if (redisClient && redisClient.isReady) {
      try {
        const redisKey = `client_keys:${clientKey}`;
        keyData = await redisClient.hGetAll(redisKey);
        
        if (keyData && keyData.account_name && keyData.active === 'true') {
          accountName = keyData.account_name;
          keyValid = true;
          console.log(`[${new Date().toISOString()}] Client key validated from Redis, bound to account: ${accountName}`);
        }
      } catch (error) {
        console.error('Error checking Redis for client key:', error);
      }
    }
    
    
    if (!keyValid) {
      return res.status(403).json({
        type: 'error',
        error: {
          type: 'authentication_error',
          message: 'Unauthorized API key. Please contact administrator for access.'
        }
      });
    }

    // 获取请求模型以进行模型特定的限制检查
    let requestModel = '';
    if (req.body && req.body.model) {
      requestModel = req.body.model;
    }
    
    // 确定模型类型用于限制检查 - 使用更广泛的模糊匹配
    let modelType = '';
    let limitKey = '';
    let countKey = '';
    let windowStartKey = '';
    
    if (requestModel.includes('opus')) {
      modelType = 'opus_4';
    } else if (requestModel.includes('sonnet')) {
      modelType = 'sonnet_4';
    }
    
    // 基于模型的5小时时间窗口请求限制检查
    if (modelType && (keyData.tier === 'high' || keyData.tier === 'supreme')) {
      limitKey = `${modelType}_per_5_hours`;
      countKey = `${modelType}_current_window_requests`;
      windowStartKey = `${modelType}_current_window_start`;
      
      if (keyData[limitKey]) {
        const now = Date.now();
        // 5小时时间窗口 (生产环境标准配置)
        const windowSize = 5 * 60 * 60 * 1000; // 5小时 = 18000000毫秒
        const maxRequests = parseInt(keyData[limitKey]);
        let currentWindowStart = parseInt(keyData[windowStartKey] || now.toString());
        let currentWindowRequests = parseInt(keyData[countKey] || '0');
        
        
        // 检查是否需要重置时间窗口
        if (now - currentWindowStart >= windowSize) {
          // 重置时间窗口
          const newWindowStart = now;
          currentWindowRequests = 0;  // 🔥 重要：重置本地计数器
          
          try {
            await redisClient.hSet(`client_keys:${clientKey}`, {
              [windowStartKey]: newWindowStart.toString(),
              [countKey]: '0'
            });
            console.log(`[${new Date().toISOString()}] 🔄 Reset ${modelType} 5-hour window for key: ${clientKey.substring(0, 20)}... (New window starts now)`);
          } catch (error) {
            console.error(`Error resetting ${modelType} time window:`, error);
          }
          
          // 🔥 关键修复：更新窗口开始时间，确保后续计算正确
          currentWindowStart = newWindowStart;
        }
        
        // 检查是否超过限制
        if (currentWindowRequests >= maxRequests) {
          const remainingTime = windowSize - (now - currentWindowStart);
          const modelDisplayName = modelType === 'opus_4' ? 'Opus 4.1' : 'Sonnet 4';
          
          const hoursLeft = Math.floor(remainingTime / (60 * 60 * 1000));
          const minutesLeft = Math.floor((remainingTime % (60 * 60 * 1000)) / (60 * 1000));
          const timeMessage = `Usage will be reset in ${hoursLeft}h ${minutesLeft}m`;
          
          return res.status(429).json({
            type: 'error',
            error: {
              type: 'rate_limit_error',
              message: `Rate limit exceeded for ${modelDisplayName}. ${timeMessage}.`
            }
          });
        }
        
        const modelDisplayName = modelType === 'opus_4' ? 'Opus 4.1' : 'Sonnet 4';
        console.log(`[${new Date().toISOString()}] ${modelDisplayName} rate limit check passed: ${currentWindowRequests + 1}/${maxRequests} requests in 5-hour window`);
      }
    }
    
    // Medium级别无请求限制，直接跳过限制检查
    else if (keyData.tier === 'medium') {
      console.log(`[${new Date().toISOString()}] Medium tier - no rate limits applied`);
    }

    // 获取真实的access token (使用绑定的账户)
    let accessToken = await getAccessToken(accountName || undefined);
    if (!accessToken) {
      return res.status(500).json({
        type: 'error',
        error: {
          type: 'server_error',
          message: 'Unable to retrieve access token'
        }
      });
    }
    
    // 检查token是否已被映射到新token
    const mappedToken = await tokenRefresher.getTokenMapping(accessToken);
    if (mappedToken) {
      console.log('Using mapped token (token was refreshed)');
      accessToken = mappedToken;
    }

    // 构建目标URL - 使用 originalUrl 获取完整路径和查询参数
    const targetUrl = `https://api.anthropic.com${req.originalUrl || req.url}`;
    
    // 准备请求头 - 保留原有逻辑，只替换认证部分
    const forwardHeaders: any = {
      'authorization': `Bearer ${accessToken}`,
      'anthropic-version': '2023-06-01',
      'anthropic-beta': 'claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14',
      'user-agent': 'claude-cli/1.0.77 (external, cli)',
      'content-type': req.headers['content-type'] || 'application/json'
    };

    // 如果客户端有accept header，保留它
    if (req.headers['accept']) {
      forwardHeaders['accept'] = req.headers['accept'];
    }

    console.log(`Proxying to: ${targetUrl}`);
    console.log('Header mapping: sk-cli-v1-... → Bearer token');

    // 构建请求配置 - 参考 forward-monitor.ts
    const config: any = {
      method: req.method,
      url: targetUrl,
      headers: forwardHeaders,
      maxRedirects: 5,
      validateStatus: () => true, // 接受所有状态码
      responseType: 'stream', // 重要：使用流式响应
      timeout: 120000, // 2分钟超时
      maxBodyLength: Infinity,
      maxContentLength: Infinity,
    };

    // 添加请求体
    if (req.body && ['POST', 'PUT', 'PATCH'].includes(req.method)) {
      config.data = req.body;
    }

    // 发送请求到官方API
    const response = await axios(config);
    
    console.log(`Response status: ${response.status}`);
    
    // 设置响应状态码
    res.status(response.status);
    
    // 转发所有响应头
    Object.entries(response.headers).forEach(([key, value]) => {
      // 跳过一些会导致问题的headers
      if (key.toLowerCase() !== 'connection' && 
          key.toLowerCase() !== 'content-encoding' &&
          key.toLowerCase() !== 'transfer-encoding') {
        res.setHeader(key, value as string);
      }
    });
    
    // 对于流式响应，确保正确的headers
    if (response.headers['content-type']?.includes('text/event-stream')) {
      res.setHeader('content-type', 'text/event-stream; charset=utf-8');
      res.setHeader('cache-control', 'no-cache');
      res.setHeader('connection', 'keep-alive');
      res.setHeader('x-accel-buffering', 'no'); // 禁用缓冲
    }
    
    // 直接管道传输响应流
    response.data.pipe(res);
    
    // 监听流结束
    response.data.on('end', async () => {
      const responseTime = Date.now() - startTime;
      console.log(`Request completed in ${responseTime}ms`);
      
      // 成功完成请求后递增计数器
      if (response.status >= 200 && response.status < 400) {
        try {
          // 基于模型的计数（High和Supreme级别）
          if (modelType && (keyData.tier === 'high' || keyData.tier === 'supreme') && keyData[limitKey]) {
            const newCount = await redisClient.hIncrBy(`client_keys:${clientKey}`, countKey, 1);
            const modelDisplayName = modelType === 'opus_4' ? 'Opus 4.1' : 'Sonnet 4';
            console.log(`[${new Date().toISOString()}] ${modelDisplayName} request count updated: ${newCount}/${keyData[limitKey]} for key ${clientKey.substring(0, 20)}...`);
          }
          // Medium级别无限制，不需要计数
          else if (keyData.tier === 'medium') {
            console.log(`[${new Date().toISOString()}] Medium tier request completed - no counting needed for key ${clientKey.substring(0, 20)}...`);
          }
        } catch (error) {
          console.error('Error updating request count:', error);
        }
      }
    });
    
    // 错误处理
    response.data.on('error', (error: any) => {
      console.error('Stream error:', error.message);
      if (!res.headersSent) {
        res.status(500).json({
          type: 'error',
          error: {
            type: 'stream_error',
            message: 'Error streaming response: ' + error.message
          }
        });
      }
    });

  } catch (error: any) {
    const responseTime = Date.now() - startTime;
    console.error('Proxy error:', error.message);
    
    // 如果是axios错误并且有响应
    if (error.response) {
      // 转发原始错误响应
      res.status(error.response.status);
      
      // 转发错误响应头
      Object.entries(error.response.headers).forEach(([key, value]) => {
        if (key.toLowerCase() !== 'connection' && 
            key.toLowerCase() !== 'transfer-encoding') {
          res.setHeader(key, value as string);
        }
      });
      
      // 转发错误响应体
      if (error.response.data) {
        // 如果是流，管道传输
        if (error.response.data.pipe) {
          error.response.data.pipe(res);
        } else {
          // 否则直接发送
          res.send(error.response.data);
        }
      } else {
        res.end();
      }
    } else if (error.request) {
      // 请求发出但没有收到响应
      res.status(502).json({
        type: 'error',
        error: {
          type: 'network_error',
          message: 'Failed to reach Claude API'
        }
      });
    } else {
      // 其他错误
      res.status(500).json({
        type: 'error',
        error: {
          type: 'server_error',
          message: error.message || 'An unknown error occurred'
        }
      });
    }
    
    console.log(`Request failed after ${responseTime}ms`);
  }
}

// 路由配置 - 处理所有请求
app.use('*', proxyRequest);

// 启动服务器
app.listen(PORT, '0.0.0.0', async () => {
  // Initialize Redis connection
  await initRedis();
  
  console.log(`[${new Date().toISOString()}] Claude Proxy Server (Full Stream v2) started on http://0.0.0.0:${PORT}`);
  console.log('Ready to proxy requests to Claude API with complete streaming support');
  console.log('Features:');
  console.log('- Full request/response streaming');
  console.log('- SSE (Server-Sent Events) support');
  console.log('- Error response forwarding');
  console.log('- 2-minute timeout');
  console.log('- Auto token refresh (checks every 30 minutes)');
  
  
  // 🔗 设置多账户管理器引用，确保刷新后立即同步
  tokenRefresher.setAccountManager(accountManager);
  
  // 🎯 启动多账户精确时间事件触发的token刷新机制
  await tokenRefresher.startMultiAccountPreciseRefresh();
  console.log('✅ 多账户精确时间触发的token刷新机制已启动 (每个账户独立管理)');
  
  // Redis版本不需要文件监听，因为直接从Redis读取
  console.log('Using Redis for token storage (port 6380) - token updates will be applied immediately');
});