import express from 'express';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
// import TokenRefresherRedis from './token-refresher-redis'; // 已删除，由token-refresh-daemon处理
import MultiAccountManager from './multi-account-manager';
import { createClient, RedisClientType } from 'redis';

// 获取北京时间的ISO字符串
function getBeijingTime(): string {
  const now = new Date();
  // 转换为北京时间 (UTC+8)
  const beijingTime = new Date(now.getTime() + (8 * 60 * 60 * 1000));
  // 返回格式：YYYY-MM-DDTHH:mm:ss.sssZ 但显示为北京时间
  const year = beijingTime.getUTCFullYear();
  const month = String(beijingTime.getUTCMonth() + 1).padStart(2, '0');
  const day = String(beijingTime.getUTCDate()).padStart(2, '0');
  const hours = String(beijingTime.getUTCHours()).padStart(2, '0');
  const minutes = String(beijingTime.getUTCMinutes()).padStart(2, '0');
  const seconds = String(beijingTime.getUTCSeconds()).padStart(2, '0');
  const ms = String(beijingTime.getUTCMilliseconds()).padStart(3, '0');
  return `${year}-${month}-${day}T${hours}:${minutes}:${seconds}.${ms}+08:00`;
}


const app = express();
const PORT = 8080;
// const tokenRefresher = new TokenRefresherRedis(); // 已删除
const accountManager = new MultiAccountManager();

// 清理废弃数据和过期密钥
async function cleanupDeprecatedDataAndExpiredKeys() {
  if (!redisClient || !redisClient.isReady) return;
  
  try {
    // 清理废弃的key_rotation数据（一次性清理）
    const keyRotationKeys = await redisClient.keys('key_rotation:*');
    if (keyRotationKeys.length > 0) {
      console.log(`[${getBeijingTime()}] 🧹 Cleaning up deprecated key_rotation keys: ${keyRotationKeys.length} keys`);
      await redisClient.del(keyRotationKeys);
      console.log(`[${getBeijingTime()}] ✅ Removed ${keyRotationKeys.length} deprecated key_rotation keys`);
    }
    
    // 清理过期密钥的slot占用
    await cleanupExpiredClientKeys();
  } catch (error) {
    console.error('Error cleaning up deprecated data and expired keys:', error);
  }
}

// 清理过期密钥的slot占用
async function cleanupExpiredClientKeys() {
  if (!redisClient || !redisClient.isReady) return;
  
  try {
    const now = Date.now();
    let cleanedCount = 0;
    
    // 获取所有客户端密钥
    const clientKeys = await redisClient.keys('client_keys:*');
    
    for (const key of clientKeys) {
      const keyData = await redisClient.hGetAll(key);
      
      // 检查密钥是否过期且活跃
      if (keyData && keyData.active === 'true' && keyData.expires_at) {
        const expiryTime = parseInt(keyData.expires_at);
        
        if (now > expiryTime) {
          const clientKey = key.replace('client_keys:', '');
          console.log(`[${getBeijingTime()}] 🧹 Found expired client key: ${clientKey.substring(0, 20)}...`);
          
          // 清理slot占用（如果使用账户池）
          if (keyData.use_pool === 'true' || keyData.account_name === 'pool' || 
              keyData.account_name === 'trial_pool' || keyData.account_name === 'medium_pool' || 
              keyData.account_name === 'high_pool' || keyData.account_name === 'supreme_pool') {
            
            const permanentBindingKey = `${keyData.tier}_pool:permanent_binding`;
            const assignedAccount = await redisClient.hGet(permanentBindingKey, clientKey);
            
            if (assignedAccount) {
              // 清除永久绑定
              await redisClient.hDel(permanentBindingKey, clientKey);
              
              // 减少账户的slot占用
              const slotKey = `${keyData.tier}_pool:slots:${assignedAccount}`;
              const currentSlots = await redisClient.get(slotKey);
              if (currentSlots && parseInt(currentSlots) > 0) {
                await redisClient.decr(slotKey);
                console.log(`[${getBeijingTime()}] 🧹 Cleaned up slot: ${assignedAccount} (${keyData.tier} tier)`);
              }
            }
          }
          
          // 将密钥设为非活跃状态
          await redisClient.hSet(key, 'active', 'false');
          cleanedCount++;
        }
      }
    }
    
    if (cleanedCount > 0) {
      console.log(`[${getBeijingTime()}] ✅ Cleaned up ${cleanedCount} expired client key slots`);
    }
  } catch (error) {
    console.error('Error cleaning up expired client keys:', error);
  }
}





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
    console.error(`[${getBeijingTime()}] Redis Client Error:`, err);
  });
  
  redisClient.on('connect', () => {
    console.log(`[${getBeijingTime()}] Proxy server connected to Redis on port ${REDIS_PORT}`);
  });
  
  try {
    await redisClient.connect();
  } catch (error) {
    console.error(`[${getBeijingTime()}] Failed to connect to Redis:`, error);
  }
}


// 🔥 获取access token - 零延迟，立即同步最新token
async function getAccessToken(accountName?: string): Promise<string> {
  const now = Date.now();
  
  if (accountName) {
    console.log(`[${getBeijingTime()}] 🔍 获取账户token: ${accountName}`);
    
    // 🔥 步骤1: 获取账户信息，检查是否需要刷新
    const account = await accountManager.getAccount(accountName);
    if (account && account.credentials.accessToken) {
      const oneMinuteBeforeExpiry = account.credentials.expiresAt - 60000;
      const minutesLeft = Math.floor((account.credentials.expiresAt - now) / 60000);
      
      console.log(`[${getBeijingTime()}] 📊 Token状态检查: ${accountName}`);
      console.log(`  🔑 当前Token: ${account.credentials.accessToken.substring(0, 30)}...`);
      console.log(`  ⏰ 剩余时间: ${minutesLeft} 分钟`);
      console.log(`  🚨 需要刷新: ${now >= oneMinuteBeforeExpiry ? 'YES' : 'NO'}`);
      
      // 🔥 步骤2: 如果需要刷新，立即刷新并强制重载
      if (now >= oneMinuteBeforeExpiry) {
        console.log(`[${getBeijingTime()}] 🔄 立即刷新token: ${accountName}`);
        // const refreshSuccess = await tokenRefresher.refreshToken(accountName); // 已由daemon处理
        
        // Token刷新已由daemon处理，这里跳过刷新逻辑
        console.log(`[${getBeijingTime()}] 🔄 Token刷新已由daemon处理`);
      }
      
      // 🔥 步骤3: 返回当前token（如果不需要刷新或刷新失败）
      // 再次强制重载以确保获取最新token（可能被其他刷新进程更新了）
      const latestAccount = await accountManager.getAccount(accountName, true);
      const finalToken = latestAccount?.credentials.accessToken || account.credentials.accessToken;
      console.log(`[${getBeijingTime()}] 📤 返回最新token: ${finalToken.substring(0, 30)}...`);
      return finalToken;
    } else {
      console.error(`[${getBeijingTime()}] ❌ 未找到账户或token: ${accountName}`);
    }
  }
  
  // 🔥 步骤4: 回退到默认行为（但优先使用最新数据）
  console.log(`[${getBeijingTime()}] 🔄 回退到默认token获取方式`);
  
  // 先尝试从缓存获取（如果没过期）- 已由daemon处理
  // const cachedToken = tokenRefresher.getCachedAccessToken();
  // if (cachedToken) {
  //   console.log(`[${getBeijingTime()}] 📋 使用缓存token: ${cachedToken.substring(0, 30)}...`);
  //   return cachedToken;
  // }
  
  // 强制获取最新credentials - 已由daemon处理
  // const currentToken = await tokenRefresher.getCurrentAccessToken();
  // if (currentToken) {
  //   console.log(`[${getBeijingTime()}] 📁 使用最新token: ${currentToken.substring(0, 30)}...`);
  //   return currentToken;
  // }
  
  console.error(`[${getBeijingTime()}] ❌ 无法获取任何有效token!`);
  return '';
}

// 验证客户端密钥格式
function isValidClientKey(key: string): boolean {
  return Boolean(key && key.startsWith('sk-cli-v1-'));
}

// 代理处理 - 参考 forward-monitor.ts 的实现
async function proxyRequest(req: express.Request, res: express.Response) {
  const startTime = Date.now();
  
  // 将变量定义移到try块外部，以便错误处理部分也能访问
  let clientKey: string = '';
  let accountName: string | null = null;
  let currentAccount: string | null = null;
  let keyValid = false;
  let keyData: any = {};
  let usePool = false;
  
  try {
    // 获取客户端密钥
    clientKey = req.headers['x-api-key'] as string || 
                req.headers['authorization']?.replace('Bearer ', '') as string;
    
    console.log(`[${getBeijingTime()}] ${req.method} ${req.originalUrl || req.url}`);
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
    // 变量已在函数开始处定义
    
    // Try Redis first
    if (redisClient && redisClient.isReady) {
      try {
        const redisKey = `client_keys:${clientKey}`;
        keyData = await redisClient.hGetAll(redisKey);
        
        if (keyData && keyData.account_name && keyData.active === 'true') {
          // 检查密钥状态（未售出的密钥不能使用）
          if (keyData.status === 'unsold') {
            console.log(`[${getBeijingTime()}] Client key is unsold and cannot be used: ${clientKey.substring(0, 20)}...`);
            // 未售出的密钥可以正常使用（相当于预激活状态）
            // 如果需要禁止未售出密钥使用，可以取消注释以下代码：
            /*
            return res.status(403).json({
              type: 'error',
              error: {
                type: 'permission_error',
                message: 'This API key is not yet activated. Please contact administrator.'
              }
            });
            */
          }
          
          // 对于已售出的密钥，动态计算过期时间
          let effectiveExpiryTime = 0;
          const now = Date.now();
          
          if (keyData.status === 'sold') {
            // 从产品文件获取soldAt和计算的过期时间
            try {
              const productFile = `/home/leon/claude-route-ssl/claude-route-ssl/product/${keyData.tier}.json`;
              const fs = require('fs');
              if (fs.existsSync(productFile)) {
                const products = JSON.parse(fs.readFileSync(productFile, 'utf-8'));
                const product = products[clientKey];
                if (product && product.soldAt && product.expiresAt) {
                  effectiveExpiryTime = product.expiresAt;
                  console.log(`[${getBeijingTime()}] Using calculated expiry from product file: ${new Date(effectiveExpiryTime).toISOString()}`);
                }
              }
            } catch (error) {
              console.error('Error reading product file for expiry:', error);
            }
          }
          
          // 如果没有从产品文件获取到，使用Redis中的expires_at作为备用
          if (!effectiveExpiryTime && keyData.expires_at && keyData.expires_at !== '') {
            effectiveExpiryTime = parseInt(keyData.expires_at);
          }
          
          // 检查密钥是否过期
          if (effectiveExpiryTime > 0) {
            const expiryTime = effectiveExpiryTime;
            if (now > expiryTime) {
              console.log(`[${getBeijingTime()}] Client key expired at ${new Date(expiryTime).toISOString()}: ${clientKey.substring(0, 20)}...`);
              
              // 🔥 新增：清理过期密钥的slot占用
              try {
                if (keyData.use_pool === 'true' || keyData.account_name === 'pool' || 
                    keyData.account_name === 'trial_pool' || keyData.account_name === 'medium_pool' || 
                    keyData.account_name === 'high_pool' || keyData.account_name === 'supreme_pool') {
                  
                  // 获取永久绑定的账户
                  const permanentBindingKey = `${keyData.tier}_pool:permanent_binding`;
                  const assignedAccount = await redisClient.hGet(permanentBindingKey, clientKey);
                  
                  if (assignedAccount) {
                    // 清除永久绑定
                    await redisClient.hDel(permanentBindingKey, clientKey);
                    
                    // 减少账户的slot占用
                    const slotKey = `${keyData.tier}_pool:slots:${assignedAccount}`;
                    const currentSlots = await redisClient.get(slotKey);
                    if (currentSlots && parseInt(currentSlots) > 0) {
                      await redisClient.decr(slotKey);
                      console.log(`[${getBeijingTime()}] 🧹 Cleaned up slot for expired key: ${assignedAccount} (${keyData.tier} tier)`);
                    }
                  }
                }
                
                // 将密钥设为非活跃状态
                await redisClient.hSet(`client_keys:${clientKey}`, 'active', 'false');
                
              } catch (cleanupError) {
                console.error('Error cleaning up expired key slot:', cleanupError);
              }
              
              return res.status(401).json({
                type: 'error',
                error: {
                  type: 'authentication_error',
                  message: `API key has expired on ${new Date(expiryTime).toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, '')}. Please contact administrator for a new key.`
                }
              });
            }
            const daysLeft = Math.ceil((expiryTime - now) / (24 * 60 * 60 * 1000));
            console.log(`[${getBeijingTime()}] Key expires in ${daysLeft} days (${new Date(expiryTime).toISOString().split('T')[0]})`);
          }
          
          // 检查是否使用账户池
          if (keyData.use_pool === 'true' || 
              keyData.account_name === 'trial_pool' || 
              keyData.account_name === 'medium_pool' || 
              keyData.account_name === 'high_pool' || 
              keyData.account_name === 'supreme_pool' || 
              keyData.account_name === 'pool') {
            usePool = true;
            accountName = null; // 不设置accountName，让后续逻辑处理
            console.log(`[${getBeijingTime()}] ${keyData.tier.charAt(0).toUpperCase() + keyData.tier.slice(1)} tier key uses account pool mode`);
          } else {
            accountName = keyData.account_name;
          }
          keyValid = true;
          
          if (!usePool) {
            console.log(`[${getBeijingTime()}] Client key validated from Redis, bound to account: ${accountName}`);
          } else {
            console.log(`[${getBeijingTime()}] Client key validated from Redis, using ${keyData.tier.charAt(0).toUpperCase() + keyData.tier.slice(1)} account pool`);
          }
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
    
    // Trial和Medium级别特殊处理：只能使用Sonnet模型
    if ((keyData.tier === 'trial' || keyData.tier === 'medium') && !requestModel.includes('sonnet')) {
      const tierName = keyData.tier.charAt(0).toUpperCase() + keyData.tier.slice(1);
      return res.status(403).json({
        type: 'error',
        error: {
          type: 'permission_error',
          message: `${tierName} tier can only use Sonnet models. Please upgrade to use other models.`
        }
      });
    }
    
    // 基于模型的5小时时间窗口请求限制检查
    if (modelType && (keyData.tier === 'high' || keyData.tier === 'supreme' || keyData.tier === 'trial' || keyData.tier === 'medium')) {
      limitKey = `${modelType}_per_5_hours`;
      countKey = `${modelType}_current_window_requests`;
      windowStartKey = `${modelType}_current_window_start`;
      
      // Trial/Medium级别或其他级别的限制处理
      let hasLimit = false;
      let maxRequests = 0;
      
      if ((keyData.tier === 'trial' || keyData.tier === 'medium') && modelType === 'sonnet_4') {
        // Trial和Medium级别只对Sonnet模型有限制
        hasLimit = true;
        maxRequests = 42;
      } else if (keyData[limitKey]) {
        // High和Supreme级别根据配置限制
        hasLimit = true;
        maxRequests = parseInt(keyData[limitKey]);
      }
      
      if (hasLimit) {
        const now = Date.now();
        // 5小时时间窗口 (生产环境标准配置)
        const windowSize = 5 * 60 * 60 * 1000; // 5小时 = 18000000毫秒
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
            console.log(`[${getBeijingTime()}] 🔄 Reset ${modelType} 5-hour window for key: ${clientKey.substring(0, 20)}... (New window starts now)`);
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
          
          // 添加不重试的响应头
          res.setHeader('retry-after', '0');
          res.setHeader('x-retry-forbidden', 'true');
          res.setHeader('x-no-retry', 'true');
          console.log(`🚫 429错误：${modelDisplayName} 超过限制，已告知客户端不要重试`);
          
          return res.status(429).json({
            type: 'error',
            error: {
              type: 'rate_limit_error',
              message: `Rate limit exceeded for ${modelDisplayName}. ${timeMessage}.`
            }
          });
        }
        
        const modelDisplayName = modelType === 'opus_4' ? 'Opus 4.1' : 'Sonnet 4';
        const tierInfo = (keyData.tier === 'trial' || keyData.tier === 'medium') ? ` (${keyData.tier.charAt(0).toUpperCase() + keyData.tier.slice(1)} tier)` : '';
        console.log(`[${getBeijingTime()}] ${modelDisplayName}${tierInfo} rate limit check passed: ${currentWindowRequests + 1}/${maxRequests} requests in 5-hour window`);
      }
    }
    

    // 获取真实的access token
    let accessToken: string = '';
    
    if (usePool) {
      // 账户池模式：根据slot占用情况分配账户
      const accountDir = path.join(__dirname, '..', 'account', keyData.tier);
      try {
        // 读取对应级别目录下的所有JSON文件
        const files = fs.readdirSync(accountDir).filter(f => f.endsWith('.json'));
        
        if (files.length === 0) {
          console.error(`[${getBeijingTime()}] No accounts found in ${accountDir}`);
          return res.status(500).json({
            type: 'error',
            error: {
              type: 'server_error',
              message: `No ${keyData.tier.charAt(0).toUpperCase() + keyData.tier.slice(1)} accounts available in pool`
            }
          });
        }
        
        // 使用永久绑定key（不含日期，实现真正的持久绑定）
        const now = Date.now();
        const permanentBindingKey = `${keyData.tier}_pool:permanent_binding`;
        
        // currentAccount 已在外部定义，这里直接使用
        
        // 从Redis获取该密钥永久绑定的账户
        if (redisClient && redisClient.isReady) {
          try {
            const assignedAccount = await redisClient.hGet(permanentBindingKey, clientKey);
            
            // 检查分配的账户是否仍然存在且未被加入黑名单
            if (assignedAccount && files.includes(`${assignedAccount}.json`)) {
              // 检查该账户是否在黑名单中
              const blacklistKey = `account_blacklist:${keyData.tier}:${assignedAccount}`;
              const isBlacklisted = await redisClient.exists(blacklistKey);
              
              if (isBlacklisted) {
                // 已绑定的账户在黑名单中，需要清除绑定并重新分配
                console.log(`[${keyData.tier.toUpperCase()} Pool] 永久绑定的账户 ${assignedAccount} 已被加入黑名单，清除绑定`);
                await redisClient.hDel(permanentBindingKey, clientKey);
                
                // 减少该账户的slot占用
                const slotKey = `${keyData.tier}_pool:slots:${assignedAccount}`;
                const currentSlots = await redisClient.get(slotKey);
                if (currentSlots && parseInt(currentSlots) > 0) {
                  await redisClient.decr(slotKey);
                }
                // currentAccount 保持为空，稍后重新分配
              } else {
                currentAccount = assignedAccount;
                console.log(`[${keyData.tier.toUpperCase()} Pool] 使用永久绑定账户: ${currentAccount}`);
              }
            } else if (assignedAccount && !files.includes(`${assignedAccount}.json`)) {
              // 账户文件不存在，清除绑定
              console.log(`[${keyData.tier.toUpperCase()} Pool] 永久绑定的账户 ${assignedAccount} 已不可用，清除绑定`);
              await redisClient.hDel(permanentBindingKey, clientKey);
              
              // 同时清除该账户的slot占用
              const slotKey = `${keyData.tier}_pool:slots:${assignedAccount}`;
              const currentSlots = await redisClient.get(slotKey);
              if (currentSlots && parseInt(currentSlots) > 0) {
                await redisClient.decr(slotKey);
              }
            }
          } catch (error) {
            console.error('Error reading permanent binding from Redis:', error);
          }
        }
        
        // 如果没有分配账户，需要分配一个
        if (!currentAccount) {
          // 查找可用账户（未达到占用上限）- 不同级别有不同的slot配置
          let MAX_SLOTS = 1; // 默认1个
          if (keyData.tier === 'trial' || keyData.tier === 'medium') {
            MAX_SLOTS = 7; // Trial和Medium级别每个账户7个位置
          } else if (keyData.tier === 'high') {
            MAX_SLOTS = 3; // High级别每个账户3个位置
          } else if (keyData.tier === 'supreme') {
            MAX_SLOTS = 2; // Supreme级别每个账户2个位置
          }
          let availableAccounts: string[] = [];
          
          for (const file of files) {
            const accountName = file.replace('.json', '');
            
            // 检查是否在黑名单中
            const blacklistKey = `account_blacklist:${keyData.tier}:${accountName}`;
            const isBlacklisted = await redisClient.exists(blacklistKey);
            if (isBlacklisted) {
              console.log(`[${keyData.tier.toUpperCase()} Pool] 跳过黑名单账户: ${accountName}`);
              continue;
            }
            
            const slotKey = `${keyData.tier}_pool:slots:${accountName}`;
            const currentSlots = await redisClient.get(slotKey);
            const slots = currentSlots ? parseInt(currentSlots) : 0;
            
            if (slots < MAX_SLOTS) {
              availableAccounts.push(accountName);
            }
          }
          
          if (availableAccounts.length === 0) {
            console.error(`[${getBeijingTime()}] All ${keyData.tier.charAt(0).toUpperCase() + keyData.tier.slice(1)} accounts have reached maximum slot limit`);
            return res.status(503).json({
              type: 'error',
              error: {
                type: 'capacity_error',
                message: `All ${keyData.tier.charAt(0).toUpperCase() + keyData.tier.slice(1)} accounts are at capacity. Please try again later.`
              }
            });
          }
          
          // 选择占用最少的账户
          let selectedAccount = availableAccounts[0];
          let minSlots = MAX_SLOTS;
          
          for (const account of availableAccounts) {
            const slotKey = `${keyData.tier}_pool:slots:${account}`;
            const currentSlots = await redisClient.get(slotKey);
            const slots = currentSlots ? parseInt(currentSlots) : 0;
            
            if (slots < minSlots) {
              minSlots = slots;
              selectedAccount = account;
            }
          }
          
          currentAccount = selectedAccount;
          
          // 增加账户的占用位置
          await redisClient.incr(`${keyData.tier}_pool:slots:${currentAccount}`);
          const newSlots = await redisClient.get(`${keyData.tier}_pool:slots:${currentAccount}`);
          
          // 保存永久绑定关系（不再使用cycle key）
          await redisClient.hSet(permanentBindingKey, clientKey, currentAccount);
          
          console.log(`[${getBeijingTime()}] 🔒 Key ${clientKey.substring(0, 20)}... 永久绑定到账户: ${currentAccount} (slots: ${newSlots}/${MAX_SLOTS})`);
          console.log(`[${getBeijingTime()}] ⚡ 此绑定将持续直到账户不可用`);
        } else {
          // 使用已分配的账户
          const slotKey = `${keyData.tier}_pool:slots:${currentAccount}`;
          const currentSlots = await redisClient.get(slotKey);
          let maxSlots = 1; // 默认1个
          if (keyData.tier === 'trial' || keyData.tier === 'medium') {
            maxSlots = 7; // Trial和Medium级别7个位置
          } else if (keyData.tier === 'high') {
            maxSlots = 3; // High级别3个位置
          } else if (keyData.tier === 'supreme') {
            maxSlots = 2; // Supreme级别2个位置
          }
          console.log(`[${getBeijingTime()}] 📌 Key ${clientKey.substring(0, 20)}... 使用永久绑定账户: ${currentAccount} (slots: ${currentSlots}/${maxSlots})`);
        }
        
        // 获取该账户的token
        accessToken = await getAccessToken(currentAccount);
        
        if (!accessToken) {
          console.error(`[${getBeijingTime()}] Failed to get token from account: ${currentAccount}`);
          return res.status(500).json({
            type: 'error',
            error: {
              type: 'server_error',
              message: 'Unable to retrieve access token from account pool'
            }
          });
        }
        
        console.log(`[${getBeijingTime()}] ✅ Successfully obtained token from account: ${currentAccount}`);
      } catch (error) {
        console.error(`[${getBeijingTime()}] Error accessing Medium account pool:`, error);
        return res.status(500).json({
          type: 'error',
          error: {
            type: 'server_error',
            message: 'Failed to access account pool'
          }
        });
      }
    } else {
      // 普通模式：使用指定账户
      accessToken = await getAccessToken(accountName || undefined);
      if (!accessToken) {
        return res.status(500).json({
          type: 'error',
          error: {
            type: 'server_error',
            message: 'Unable to retrieve access token'
          }
        });
      }
    }
    
    // 检查token是否已被映射到新token - 已由daemon处理
    // const mappedToken = await tokenRefresher.getTokenMapping(accessToken);
    // if (mappedToken) {
    //   console.log('Using mapped token (token was refreshed)');
    //   accessToken = mappedToken;
    // }

    // 构建目标URL - 使用 originalUrl 获取完整路径和查询参数
    const targetUrl = `https://api.anthropic.com${req.originalUrl || req.url}`;
    
    // 准备请求头 - 保留原有逻辑，只替换认证部分
    const forwardHeaders: any = {
      'authorization': `Bearer ${accessToken}`,
      'anthropic-version': '2023-06-01',
      'anthropic-beta': 'oauth-2025-04-20',
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
      responseType: 'stream', // 使用流式响应
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
    
    // 🔥 检查认证错误关键词并实现故障转移（仅在错误状态码时检查）
    if (keyData && keyData.tier && currentAccount && clientKey && redisClient && redisClient.isReady && 
        (response.status === 401 || response.status === 403)) {
      try {
        // 读取响应内容检查认证错误（兼容流式和非流式响应）
        let responseBody = '';
        if (response.data) {
          if (typeof response.data.on === 'function') {
            // 流式响应：收集所有数据块
            const chunks: Buffer[] = [];
            response.data.on('data', (chunk: Buffer) => chunks.push(chunk));
            await new Promise((resolve, reject) => {
              response.data.on('end', resolve);
              response.data.on('error', reject);
            });
            responseBody = Buffer.concat(chunks).toString();
          } else if (typeof response.data === 'object') {
            // 非流式对象响应
            responseBody = JSON.stringify(response.data);
          } else {
            // 字符串响应
            responseBody = response.data.toString();
          }
        }
        
        const responseText = responseBody.toLowerCase();
        const shouldBlacklist = responseText.includes('authentication_error') || 
                               responseText.includes('invalid bearer token') || 
                               responseText.includes('revoke');
        
        if (shouldBlacklist) {
          console.log(`[${keyData.tier.toUpperCase()} Pool] 🚨 检测到认证错误关键词，账户 ${currentAccount} 需要列入黑名单`);
          console.log(`[${keyData.tier.toUpperCase()} Pool] 响应内容: ${responseBody.substring(0, 200)}...`);
          
          const now = Date.now();
          
          // 1. 清除永久绑定
          const permanentBindingKey = `${keyData.tier}_pool:permanent_binding`;
          await redisClient.hDel(permanentBindingKey, clientKey);
          
          // 2. 减少原账户的slot占用
          const oldSlotKey = `${keyData.tier}_pool:slots:${currentAccount}`;
          const oldSlots = await redisClient.get(oldSlotKey);
          if (oldSlots && parseInt(oldSlots) > 0) {
            await redisClient.decr(oldSlotKey);
          }
          
          // 3. 设置账户黑名单
          const blacklistKey = `account_blacklist:${keyData.tier}:${currentAccount}`;
          await redisClient.set(blacklistKey, `auth_error_at_${now}`);
          
          console.log(`[${keyData.tier.toUpperCase()} Pool] 🚫 账户 ${currentAccount} 已加入黑名单（认证错误关键词匹配）`);
          
          // 4. 故障转移：重新分配新账户
          console.log(`[${keyData.tier.toUpperCase()} Pool] 🔄 开始故障转移，寻找其他可用账户...`);
          
          // 重新加载账户列表
          const accountDir = `/home/leon/claude-route-ssl/claude-route-ssl/account/${keyData.tier}`;
          const files = fs.readdirSync(accountDir).filter(file => file.endsWith('.json'));
          
          // 查找可用账户（复用现有逻辑）
          let MAX_SLOTS = (keyData.tier === 'trial' || keyData.tier === 'medium') ? 7 : keyData.tier === 'high' ? 3 : keyData.tier === 'supreme' ? 2 : 1; // 默认1个
          let availableAccounts: string[] = [];
          
          for (const file of files) {
            const accountName = file.replace('.json', '');
            
            // 跳过黑名单账户
            const accountBlacklistKey = `account_blacklist:${keyData.tier}:${accountName}`;
            const isBlacklisted = await redisClient.exists(accountBlacklistKey);
            if (isBlacklisted) {
              continue;
            }
            
            const slotKey = `${keyData.tier}_pool:slots:${accountName}`;
            const currentSlots = await redisClient.get(slotKey);
            const slots = currentSlots ? parseInt(currentSlots) : 0;
            
            if (slots < MAX_SLOTS) {
              availableAccounts.push(accountName);
            }
          }
          
          if (availableAccounts.length === 0) {
            console.error(`[${keyData.tier.toUpperCase()} Pool] ❌ 故障转移失败：所有账户都已达到容量上限或被加入黑名单`);
            return res.status(503).json({
              type: 'error',
              error: {
                type: 'failover_failed',
                message: `All ${keyData.tier} accounts are at capacity or blacklisted. Please try again later.`
              }
            });
          }
          
          // 选择占用最少的账户
          let selectedAccount = availableAccounts[0];
          let minSlots = MAX_SLOTS;
          
          for (const account of availableAccounts) {
            const slotKey = `${keyData.tier}_pool:slots:${account}`;
            const currentSlots = await redisClient.get(slotKey);
            const slots = currentSlots ? parseInt(currentSlots) : 0;
            
            if (slots < minSlots) {
              minSlots = slots;
              selectedAccount = account;
            }
          }
          
          console.log(`[${keyData.tier.toUpperCase()} Pool] 🎯 故障转移到账户: ${selectedAccount} (slots: ${minSlots}/${MAX_SLOTS})`);
          
          // 5. 使用新账户重新发送请求
          const newAccountPath = path.join(accountDir, `${selectedAccount}.json`);
          const newAccountData = JSON.parse(fs.readFileSync(newAccountPath, 'utf8'));
          
          // 获取新账户的token
          let newBearerToken = newAccountData.access_token;
          
          // 检查token是否即将过期
          if (newAccountData.expires_at) {
            const expiresAt = new Date(newAccountData.expires_at).getTime();
            const timeToExpiry = expiresAt - Date.now();
            
            if (timeToExpiry < 60000) { // 1分钟内过期
              try {
                const refreshedAccount = await accountManager.getAccount(selectedAccount, true);
                if (refreshedAccount && refreshedAccount.credentials.accessToken) {
                  newBearerToken = refreshedAccount.credentials.accessToken;
                  console.log(`[${keyData.tier.toUpperCase()} Pool] 🔄 新账户token已刷新`);
                }
              } catch (refreshError) {
                console.error('Failed to refresh new account token:', refreshError);
              }
            }
          }
          
          // 更新配置使用新账户
          config.headers.Authorization = `Bearer ${newBearerToken}`;
          
          // 增加新账户的slot占用
          const newSlotKey = `${keyData.tier}_pool:slots:${selectedAccount}`;
          await redisClient.incr(newSlotKey);
          
          // 设置新的永久绑定
          await redisClient.hSet(permanentBindingKey, clientKey, selectedAccount);
          
          console.log(`[${keyData.tier.toUpperCase()} Pool] 🔄 使用新账户重新发送请求...`);
          
          // 递归调用重新发送请求（使用新的Bearer token）
          const retryResponse = await axios(config);
          
          console.log(`[${keyData.tier.toUpperCase()} Pool] ✅ 故障转移成功，新响应状态: ${retryResponse.status}`);
          
          // 设置新的响应状态码和数据
          res.status(retryResponse.status);
          
          // 转发所有响应头
          Object.entries(retryResponse.headers).forEach(([key, value]) => {
            if (key.toLowerCase() !== 'connection' && 
                key.toLowerCase() !== 'content-encoding' &&
                key.toLowerCase() !== 'transfer-encoding') {
              res.setHeader(key, value as string);
            }
          });
          
          // 对于流式响应，确保正确的headers
          if (retryResponse.headers['content-type']?.includes('text/event-stream')) {
            res.setHeader('content-type', 'text/event-stream; charset=utf-8');
            res.setHeader('cache-control', 'no-cache');
            res.setHeader('connection', 'keep-alive');
            res.setHeader('x-accel-buffering', 'no');
          }
          
          // 检查是否是流式数据还是已解析的数据
          if (retryResponse.data && typeof retryResponse.data.pipe === 'function') {
            // 如果是流，直接管道传输
            retryResponse.data.pipe(res);
          } else {
            // 如果是已解析的数据，直接发送
            res.send(retryResponse.data);
          }
          
          // 只在流式响应时监听流结束事件
          if (retryResponse.data && typeof retryResponse.data.on === 'function') {
            retryResponse.data.on('end', async () => {
              const responseTime = Date.now() - startTime;
              console.log(`[${keyData.tier.toUpperCase()} Pool] Request completed with failover in ${responseTime}ms`);
            });
          } else {
            // 非流式响应，立即记录完成时间
            const responseTime = Date.now() - startTime;
            console.log(`[${keyData.tier.toUpperCase()} Pool] Request completed with failover in ${responseTime}ms`);
            
            // 成功完成请求后递增计数器
            if (retryResponse.status >= 200 && retryResponse.status < 400) {
              try {
                // Trial和Medium级别对Sonnet模型进行计数
                if ((keyData.tier === 'trial' || keyData.tier === 'medium') && modelType === 'sonnet_4') {
                  const newCount = await redisClient.hIncrBy(`client_keys:${clientKey}`, countKey, 1);
                  console.log(`[${keyData.tier.toUpperCase()} Pool] Sonnet 4 requests: ${newCount}/35 (next 5h)`);
                }
                // High/Supreme级别计数
                else if (modelType && (keyData.tier === 'high' || keyData.tier === 'supreme') && keyData[limitKey]) {
                  const newCount = await redisClient.hIncrBy(`client_keys:${clientKey}`, countKey, 1);
                  const modelDisplayName = modelType === 'opus_4' ? 'Opus 4.1' : 'Sonnet 4';
                  console.log(`[${keyData.tier.toUpperCase()} Pool] ${modelDisplayName} requests: ${newCount}/${keyData[limitKey]} (next 5h)`);
                }
                // 不需要计数的情况
                else {
                  console.log(`[${keyData.tier.toUpperCase()} Pool] Request completed - no counting needed`);
                }
              } catch (countError) {
                console.error('Failed to increment request count:', countError);
              }
            }
          }
          
          // 只在流式响应时监听错误事件
          if (retryResponse.data && typeof retryResponse.data.on === 'function') {
            retryResponse.data.on('error', (error: any) => {
              console.error('Retry stream error:', error.message);
              if (!res.headersSent) {
                res.status(500).json({
                  type: 'error',
                  error: {
                    type: 'stream_error',
                    message: 'Error streaming retry response: ' + error.message
                  }
                });
              }
            });
          }
          
          return; // 重要：故障转移成功后直接返回，不继续执行原来的响应处理
        }
      } catch (failoverError) {
        console.error('Failover error:', failoverError);
        // 如果故障转移失败，继续使用原响应
      }
    }
    
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
    
    // 异步收集响应数据用于黑名单检测
    const responseChunks: Buffer[] = [];
    response.data.on('data', (chunk: Buffer) => {
      responseChunks.push(chunk);
    });
    
    // 监听流结束
    response.data.on('end', async () => {
      const responseTime = Date.now() - startTime;
      console.log(`Request completed in ${responseTime}ms`);
      
      // 异步黑名单检测（不影响响应性能）
      if (keyData && keyData.tier && currentAccount && clientKey && redisClient && redisClient.isReady) {
        setImmediate(async () => {
          try {
            const responseBuffer = Buffer.concat(responseChunks).toString();
            const responseText = responseBuffer.toLowerCase();
            
            const shouldBlacklist = responseText.includes('authentication_error') || 
                                   responseText.includes('invalid bearer token') || 
                                   responseText.includes('revoke');
            
            if (shouldBlacklist) {
              console.log(`[${keyData.tier.toUpperCase()} Pool] 🚨 异步检测到认证错误关键词，账户 ${currentAccount} 需要列入黑名单`);
              console.log(`[${keyData.tier.toUpperCase()} Pool] 响应内容: ${responseBuffer.substring(0, 200)}...`);
              
              const now = Date.now();
              
              // 1. 清除永久绑定
              const permanentBindingKey = `${keyData.tier}_pool:permanent_binding`;
              await redisClient.hDel(permanentBindingKey, clientKey);
              
              // 2. 减少原账户的slot占用
              const oldSlotKey = `${keyData.tier}_pool:slots:${currentAccount}`;
              const oldSlots = await redisClient.get(oldSlotKey);
              if (oldSlots && parseInt(oldSlots) > 0) {
                await redisClient.decr(oldSlotKey);
              }
              
              // 3. 设置账户黑名单
              const blacklistKey = `account_blacklist:${keyData.tier}:${currentAccount}`;
              await redisClient.set(blacklistKey, `auth_error_at_${now}`);
              
              console.log(`[${keyData.tier.toUpperCase()} Pool] 🚫 账户 ${currentAccount} 已异步加入黑名单（认证错误关键词匹配）`);
            }
          } catch (error) {
            console.error('异步黑名单检测错误:', error);
          }
        });
      }
      
      // 成功完成请求后递增计数器
      if (response.status >= 200 && response.status < 400) {
        try {
          // Trial和Medium级别对Sonnet模型进行计数
          if ((keyData.tier === 'trial' || keyData.tier === 'medium') && modelType === 'sonnet_4') {
            const newCount = await redisClient.hIncrBy(`client_keys:${clientKey}`, countKey, 1);
            console.log(`[${getBeijingTime()}] [${keyData.tier.toUpperCase()}] Sonnet 4 request count updated: ${newCount}/35 for key ${clientKey.substring(0, 20)}...`);
          }
          // High和Supreme级别基于模型的计数
          else if (modelType && (keyData.tier === 'high' || keyData.tier === 'supreme') && keyData[limitKey]) {
            const newCount = await redisClient.hIncrBy(`client_keys:${clientKey}`, countKey, 1);
            const modelDisplayName = modelType === 'opus_4' ? 'Opus 4.1' : 'Sonnet 4';
            console.log(`[${getBeijingTime()}] [${keyData.tier.toUpperCase()}] ${modelDisplayName} request count updated: ${newCount}/${keyData[limitKey]} for key ${clientKey.substring(0, 20)}...`);
          }
          // 不需要计数的情况
          else {
            console.log(`[${getBeijingTime()}] [${keyData.tier.toUpperCase()}] Request completed - no counting needed for key ${clientKey.substring(0, 20)}...`);
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
    
    // 🔥 基于认证错误的账户黑名单机制
    if (keyData && keyData.tier && currentAccount && clientKey && redisClient && redisClient.isReady) {
      try {
        const now = Date.now();
        let shouldBlacklist = false;
        let errorReason = '';
        
        // 检查是否为认证相关错误
        if (error.response && error.response.data) {
          const responseData = error.response.data;
          const errorMessage = error.message || '';
          const responseText = JSON.stringify(responseData).toLowerCase();
          
          // 检查特定的认证错误标识
          if (responseText.includes('authentication_error') || 
              responseText.includes('invalid bearer token') || 
              responseText.includes('revoke')) {
            shouldBlacklist = true;
            errorReason = `Authentication error: ${responseData.error?.message || errorMessage}`;
          }
        } else if (error.message) {
          const errorMessage = error.message.toLowerCase();
          if (errorMessage.includes('authentication_error') || 
              errorMessage.includes('invalid bearer token') || 
              errorMessage.includes('revoke')) {
            shouldBlacklist = true;
            errorReason = `Authentication error: ${error.message}`;
          }
        }
        
        if (shouldBlacklist) {
          console.log(`[${keyData.tier.toUpperCase()} Pool] 🚨 检测到认证错误，账户 ${currentAccount} 需要列入黑名单`);
          console.log(`[${keyData.tier.toUpperCase()} Pool] 错误原因: ${errorReason}`);
          
          // 1. 清除永久绑定
          const permanentBindingKey = `${keyData.tier}_pool:permanent_binding`;
          await redisClient.hDel(permanentBindingKey, clientKey);
          
          // 2. 减少原账户的slot占用
          const oldSlotKey = `${keyData.tier}_pool:slots:${currentAccount}`;
          const oldSlots = await redisClient.get(oldSlotKey);
          if (oldSlots && parseInt(oldSlots) > 0) {
            await redisClient.decr(oldSlotKey);
          }
          
          // 3. 设置账户黑名单（永久，直到手动清除）
          const blacklistKey = `account_blacklist:${keyData.tier}:${currentAccount}`;
          await redisClient.set(blacklistKey, `auth_error_at_${now}`);
          // 不设置过期时间，永久黑名单
          
          console.log(`[${keyData.tier.toUpperCase()} Pool] 🚫 账户 ${currentAccount} 已加入黑名单（认证错误）`);
          console.log(`[${keyData.tier.toUpperCase()} Pool] 🔄 所有绑定到此账户的密钥下次请求时将自动重新分配`);
        }
      } catch (switchError) {
        console.error('Error during authentication error handling:', switchError);
      }
    }
    
    // 如果是axios错误并且有响应
    if (error.response) {
      // 转发原始错误响应
      res.status(error.response.status);
      
      // 对于429错误，添加不重试的响应头
      if (error.response.status === 429) {
        res.setHeader('retry-after', '0');
        res.setHeader('x-retry-forbidden', 'true');
        res.setHeader('x-no-retry', 'true');
        console.log('🚫 429错误：已告知客户端不要重试');
      }
      
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
  
  // 清理废弃数据和过期密钥
  await cleanupDeprecatedDataAndExpiredKeys();
  
  console.log(`[${getBeijingTime()}] Claude Proxy Server (Full Stream v2) started on http://0.0.0.0:${PORT}`);
  console.log('Ready to proxy requests to Claude API with complete streaming support');
  console.log('Features:');
  console.log('- Full request/response streaming');
  console.log('- SSE (Server-Sent Events) support');
  console.log('- Error response forwarding');
  console.log('- 2-minute timeout');
  console.log('- Auto token refresh (checks every 30 minutes)');
  
  
  // Token刷新由独立的token-refresh-daemon.js处理
  console.log('✅ Token刷新由token-refresh-daemon.js独立管理');
  
  // Redis版本不需要文件监听，因为直接从Redis读取
  console.log('Using Redis for token storage (port 6380) - token updates will be applied immediately');
});