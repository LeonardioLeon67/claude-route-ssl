#!/usr/bin/env node

/**
 * Token刷新守护进程
 * 由PM2管理的持续运行服务，每分钟检查所有即将过期的账户并触发刷新
 * 替代原有的Cron任务方案
 */

const fs = require('fs');
const path = require('path');
const Redis = require('ioredis');
const axios = require('axios');

function getBeijingTime() {
  return new Date().toLocaleString('zh-CN', { 
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit', 
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  });
}

class TokenRefreshDaemon {
  constructor() {
    this.redis = new Redis({ 
      port: 6380,
      retryDelayOnFailover: 100,
      maxRetriesPerRequest: 3,
      lazyConnect: true
    });
    this.logFile = path.join(__dirname, 'logs', 'token-refresh-daemon.log');
    this.running = false;
    this.checkInterval = 60000; // 60秒检查一次
    this.ensureLogDirectory();
    
    // 优雅关闭处理
    process.on('SIGTERM', () => this.shutdown());
    process.on('SIGINT', () => this.shutdown());
  }

  // 确保日志目录存在
  ensureLogDirectory() {
    const logDir = path.dirname(this.logFile);
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }
  }

  // 写入日志
  log(message) {
    const timestamp = getBeijingTime();
    const logMessage = `[${timestamp}] ${message}\n`;
    
    // 同时输出到控制台和文件
    console.log(logMessage.trim());
    try {
      fs.appendFileSync(this.logFile, logMessage);
    } catch (error) {
      console.error('写入日志文件失败:', error.message);
    }
  }

  // 错误日志
  error(message, error = null) {
    const timestamp = getBeijingTime();
    let logMessage = `[${timestamp}] ❌ ${message}`;
    if (error) {
      logMessage += `: ${error.message}`;
    }
    logMessage += '\n';
    
    console.error(logMessage.trim());
    try {
      fs.appendFileSync(this.logFile, logMessage);
    } catch (err) {
      console.error('写入错误日志失败:', err.message);
    }
  }

  // 启动守护进程
  async start() {
    this.log('🚀 Token刷新守护进程启动...');
    this.running = true;
    
    try {
      // 连接Redis
      await this.redis.connect();
      this.log('📡 Redis连接成功');
    } catch (error) {
      this.error('Redis连接失败', error);
      process.exit(1);
    }
    
    // 开始循环检查
    this.runLoop();
  }

  // 主循环
  async runLoop() {
    while (this.running) {
      try {
        await this.checkAndRefreshAccounts();
        
        // 等待下次检查
        if (this.running) {
          await this.sleep(this.checkInterval);
        }
      } catch (error) {
        this.error('检查循环出错', error);
        // 出错后等待30秒再重试
        if (this.running) {
          await this.sleep(30000);
        }
      }
    }
  }

  // 睡眠函数
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  // 检查并刷新账户
  async checkAndRefreshAccounts() {
    this.log('🔍 开始检查账户刷新需求...');
    
    const accountDir = path.join(__dirname, '..', 'account');
    const tiers = ['medium', 'high', 'supreme', 'trial'];
    const now = Date.now();
    let totalChecked = 0;
    let needsRefresh = 0;
    let refreshAttempted = 0;
    let refreshSucceeded = 0;
    
    for (const tier of tiers) {
      const tierDir = path.join(accountDir, tier);
      if (!fs.existsSync(tierDir)) continue;
      
      const files = fs.readdirSync(tierDir).filter(f => f.endsWith('.json'));
      if (files.length > 0) {
        this.log(`📂 ${tier}级别: 发现${files.length}个账户`);
      }
      
      for (const file of files) {
        const accountName = path.basename(file, '.json');
        const filePath = path.join(tierDir, file);
        totalChecked++;
        
        try {
          // 检查是否在黑名单
          const blacklistKey = `account_blacklist:${tier}:${accountName}`;
          const isBlacklisted = await this.redis.exists(blacklistKey);
          if (isBlacklisted) {
            continue; // 静默跳过黑名单账户
          }
          
          // 检查冷却状态
          const cooldownKey = `token_refresh_cooldown:${accountName}`;
          const inCooldown = await this.redis.exists(cooldownKey);
          if (inCooldown) {
            continue; // 静默跳过冷却中的账户
          }
          
          // 读取账户文件
          const content = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
          const expiresAt = content.claudeAiOauth?.expiresAt;
          
          if (!expiresAt) {
            continue; // 跳过缺少过期时间的账户
          }
          
          const oneMinuteBeforeExpiry = expiresAt - 60000;
          const minutesLeft = Math.floor((expiresAt - now) / 60000);
          
          // 记录详细的时间信息（仅在距离过期小于8小时时显示）
          if (minutesLeft < 480) {
            const expiryBeijing = new Date(expiresAt).toLocaleString('zh-CN', { 
              timeZone: 'Asia/Shanghai',
              year: 'numeric',
              month: '2-digit',
              day: '2-digit',
              hour: '2-digit',
              minute: '2-digit',
              second: '2-digit',
              hour12: false
            });
            this.log(`  📍 ${accountName}: 过期时间 ${expiryBeijing} (北京), 剩余 ${minutesLeft} 分钟`);
          }
          
          // 如果应该刷新（过期前1分钟内或已过期10分钟内）
          if (now >= oneMinuteBeforeExpiry && minutesLeft >= -10) {
            needsRefresh++;
            this.log(`⚠️ ${accountName} 需要刷新！剩余${minutesLeft}分钟`);
            
            // 检查最近是否已经尝试过
            const lastAttemptKey = `daemon_refresh_last_attempt:${accountName}`;
            const lastAttempt = await this.redis.get(lastAttemptKey);
            
            if (lastAttempt) {
              const timeSinceLastAttempt = now - parseInt(lastAttempt);
              if (timeSinceLastAttempt < 120000) { // 2分钟内尝试过
                continue; // 静默跳过最近尝试过的
              }
            }
            
            // 记录尝试时间
            await this.redis.set(lastAttemptKey, now, 'EX', 300); // 5分钟过期
            
            // 触发刷新
            refreshAttempted++;
            const success = await this.triggerRefresh(accountName, content.claudeAiOauth);
            if (success) {
              refreshSucceeded++;
              this.log(`✅ ${accountName} 刷新成功`);
            }
          }
          
        } catch (error) {
          this.error(`处理账户 ${accountName} 失败`, error);
        }
      }
    }
    
    // 只在有活动时输出摘要
    if (needsRefresh > 0 || refreshAttempted > 0) {
      this.log(`📊 检查完成 - 总计:${totalChecked}, 需刷新:${needsRefresh}, 已尝试:${refreshAttempted}, 成功:${refreshSucceeded}`);
    }
  }

  // 触发刷新
  async triggerRefresh(accountName, credentials) {
    try {
      // 检查全局刷新锁
      const globalLockKey = 'global_refresh_success_lock';
      const hasGlobalLock = await this.redis.exists(globalLockKey);
      
      if (hasGlobalLock) {
        const ttl = await this.redis.ttl(globalLockKey);
        this.log(`🔒 ${accountName} 全局锁激活中，等待${ttl}秒`);
        return false;
      }
      
      this.log(`🔄 触发 ${accountName} 的刷新...`);
      
      // 调用刷新API - 使用标准OAuth端点
      const refreshResponse = await axios.post('https://console.anthropic.com/v1/oauth/token', {
        grant_type: 'refresh_token',
        refresh_token: credentials.refreshToken,
        client_id: '9d1c250a-e61b-44d9-88ed-5944d1962f5e'
      }, {
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/plain, */*',
          'User-Agent': 'claude-cli/1.0.77 (external, cli)',
          'Accept-Language': 'en-US,en;q=0.9',
          'Referer': 'https://claude.ai/',
          'Origin': 'https://claude.ai'
        },
        timeout: 30000
      });
      
      if (refreshResponse.data?.access_token) {
        // 更新文件 - 处理标准OAuth响应格式
        const updatedCredentials = {
          ...credentials,
          accessToken: refreshResponse.data.access_token,
          refreshToken: refreshResponse.data.refresh_token || credentials.refreshToken,
          expiresAt: Date.now() + (refreshResponse.data.expires_in * 1000),
          scopes: typeof refreshResponse.data.scope === 'string' 
            ? refreshResponse.data.scope.split(' ') 
            : (refreshResponse.data.scope || credentials.scopes)
        };
        
        // 找到并更新文件
        const accountFiles = [
          path.join(__dirname, '..', 'account', 'medium', `${accountName}.json`),
          path.join(__dirname, '..', 'account', 'high', `${accountName}.json`),
          path.join(__dirname, '..', 'account', 'supreme', `${accountName}.json`),
          path.join(__dirname, '..', 'account', 'trial', `${accountName}.json`)
        ];
        
        let fileUpdated = false;
        for (const filePath of accountFiles) {
          if (fs.existsSync(filePath)) {
            fs.writeFileSync(filePath, JSON.stringify({
              claudeAiOauth: updatedCredentials
            }, null, 2));
            this.log(`💾 ${accountName} 文件已更新: ${path.basename(filePath)}`);
            
            // 设置全局锁
            await this.redis.set(globalLockKey, Date.now(), 'EX', 60);
            this.log(`🔒 设置60秒全局刷新锁`);
            fileUpdated = true;
            break;
          }
        }
        
        if (fileUpdated) {
          this.log(`🎉 ${accountName} 刷新成功! 新过期时间: ${new Date(updatedCredentials.expiresAt).toISOString()}`);
          return true;
        } else {
          this.error(`${accountName} 找不到对应的账户文件`);
          return false;
        }
      } else {
        this.error(`${accountName} API响应中缺少access_token`);
        return false;
      }
      
    } catch (error) {
      this.error(`刷新 ${accountName} 失败`, error);
      if (error.response) {
        this.log(`响应状态: ${error.response.status}`);
        if (error.response.status === 403) {
          this.log(`遇到Cloudflare保护，这是正常现象`);
        }
      }
      return false;
    }
  }

  // 优雅关闭
  async shutdown() {
    this.log('📴 接收到关闭信号，正在优雅关闭...');
    this.running = false;
    
    try {
      await this.redis.quit();
      this.log('📡 Redis连接已关闭');
    } catch (error) {
      this.error('关闭Redis连接失败', error);
    }
    
    this.log('✅ Token刷新守护进程已停止');
    process.exit(0);
  }
}

// 启动守护进程
if (require.main === module) {
  const daemon = new TokenRefreshDaemon();
  daemon.start().catch((error) => {
    console.error('启动守护进程失败:', error);
    process.exit(1);
  });
}

module.exports = TokenRefreshDaemon;