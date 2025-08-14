import * as fs from 'fs';
import * as path from 'path';
import axios from 'axios';
import { createClient, RedisClientType } from 'redis';

interface OAuthCredentials {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  scopes?: string; // 存储为字符串格式（如："user:inference user:profile"）
  subscriptionType?: string;
}

interface RefreshMapping {
  [oldToken: string]: string; // Maps old token to new token
}

interface KeyMappings {
  [clientKey: string]: {
    clientName: string;
    createdAt: number;
    createdDate: string;
    active: boolean;
    accessToken?: string;
  };
}

class TokenRefresherRedis {
  private redisClient: RedisClientType;
  private refreshInterval: NodeJS.Timeout | null = null; // 支持setInterval和setTimeout
  private isConnected: boolean = false;
  
  // 🎯 多账户定时器管理
  private accountTimers: Map<string, NodeJS.Timeout> = new Map(); // 每个账户的专用定时器
  private accountManager: any = null; // 多账户管理器引用
  
  // Memory cache for credentials
  private cachedCredentials: OAuthCredentials | null = null;
  private cacheLoadTime: number = 0;
  private readonly CACHE_TTL = 60000; // Cache for 1 minute
  private currentAccountName: string | null = null; // Track current account
  
  // Redis keys
  private readonly REDIS_KEY_CREDENTIALS = 'oauth:credentials';
  private readonly REDIS_KEY_REFRESH_MAP = 'oauth:refresh_mappings';
  private readonly REDIS_ACCOUNTS_PREFIX = 'accounts:';
  private readonly REDIS_REFRESH_SCHEDULE = 'refresh_schedules:'; // 存储每个账户的刷新调度信息
  private readonly REDIS_PORT = 6380;

  constructor() {
    
    // Initialize Redis client
    this.redisClient = createClient({
      socket: {
        port: this.REDIS_PORT,
        host: 'localhost'
      }
    });

    // Set up Redis event handlers
    this.redisClient.on('error', (err) => {
      console.error(`[${new Date().toISOString()}] Redis Client Error:`, err);
      this.isConnected = false;
    });

    this.redisClient.on('connect', () => {
      console.log(`[${new Date().toISOString()}] Connected to Redis on port ${this.REDIS_PORT}`);
      this.isConnected = true;
    });

    // Connect to Redis
    this.connectRedis();
  }

  private async connectRedis(): Promise<void> {
    try {
      await this.redisClient.connect();
      // Migrate existing credentials to Redis if they exist in file
      await this.migrateCredentialsToRedis();
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Failed to connect to Redis:`, error);
    }
  }

  private async migrateCredentialsToRedis(): Promise<void> {
    try {
      // Find account files in /account directory
      const accountDir = path.join(__dirname, '..', 'account');
      if (fs.existsSync(accountDir)) {
        const files = fs.readdirSync(accountDir);
        const accountFiles = files.filter(f => f.endsWith('.json') && !f.startsWith('.'));
        
        for (const file of accountFiles) {
          const accountName = file.replace('.json', '');
          const redisKey = `${this.REDIS_ACCOUNTS_PREFIX}${accountName}`;
          
          // Check if already in Redis
          const existing = await this.redisClient.get(redisKey);
          if (existing) {
            console.log(`[${new Date().toISOString()}] Account ${accountName} already in Redis`);
            continue;
          }
          
          // Load and migrate
          const filePath = path.join(accountDir, file);
          const fileData = fs.readFileSync(filePath, 'utf-8');
          const credentials = JSON.parse(fileData);
          
          if (credentials.claudeAiOauth) {
            await this.redisClient.set(redisKey, JSON.stringify({
              credentials: credentials.claudeAiOauth,
              lastUsed: Date.now(),
              createdAt: fs.statSync(filePath).birthtimeMs
            }));
            console.log(`[${new Date().toISOString()}] Migrated account ${accountName} to Redis`);
          }
        }
        
        // Set first account as current if not set
        if (accountFiles.length > 0 && !this.currentAccountName) {
          this.currentAccountName = accountFiles[0].replace('.json', '');
          console.log(`[${new Date().toISOString()}] Set current account: ${this.currentAccountName}`);
        }
      }
      
      // Also check old location for compatibility
      const existingCreds = await this.redisClient.get(this.REDIS_KEY_CREDENTIALS);
      if (existingCreds) {
        console.log(`[${new Date().toISOString()}] Legacy credentials exist in Redis`);
      }
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error migrating credentials:`, error);
    }
  }
  
  // Get current account name from active file or first available
  private getCurrentAccountName(): string | null {
    try {
      // Check .active file
      const activeFile = path.join(__dirname, '..', 'account', '.active');
      if (fs.existsSync(activeFile)) {
        return fs.readFileSync(activeFile, 'utf-8').trim();
      }
      
      // Get first account
      const accountDir = path.join(__dirname, '..', 'account');
      if (fs.existsSync(accountDir)) {
        const files = fs.readdirSync(accountDir);
        const accountFile = files.find(f => f.endsWith('.json') && !f.startsWith('.'));
        if (accountFile) {
          return accountFile.replace('.json', '');
        }
      }
      
      return null;
    } catch (error) {
      console.error('Error getting account name:', error);
      return null;
    }
  }

  private async loadCredentials(forceRefresh: boolean = false): Promise<OAuthCredentials | null> {
    try {
      const now = Date.now();
      
      // Check if we should use cached credentials
      if (!forceRefresh && this.cachedCredentials) {
        // Check if cache is still valid (within TTL)
        if (now - this.cacheLoadTime < this.CACHE_TTL) {
          // Check if token is about to expire (within 1 minute)
          const oneMinuteFromNow = now + 60000;
          if (this.cachedCredentials.expiresAt > oneMinuteFromNow) {
            // Cache is valid and token not expiring soon
            return this.cachedCredentials;
          }
        }
      }
      
      // Load fresh credentials from Redis or file
      let credentials: OAuthCredentials | null = null;
      
      if (!this.isConnected) {
        // Fallback to file if Redis is not connected
        credentials = this.loadCredentialsFromFile();
      } else {
        const data = await this.redisClient.get(this.REDIS_KEY_CREDENTIALS);
        if (data) {
          credentials = JSON.parse(data);
        } else {
          // If not in Redis, try file as fallback
          credentials = this.loadCredentialsFromFile();
        }
      }
      
      // Update cache
      if (credentials) {
        this.cachedCredentials = credentials;
        this.cacheLoadTime = now;
        
        // Check if token needs refresh (1 minute before expiry)
        const oneMinuteBeforeExpiry = credentials.expiresAt - 60000;
        if (now >= oneMinuteBeforeExpiry) {
          console.log(`[${new Date().toISOString()}] Token expiring within 1 minute, triggering refresh...`);
          // Don't await here, let it refresh in background
          this.refreshToken();
        }
      }
      
      return credentials;
    } catch (error) {
      console.error('Error loading credentials:', error);
      return this.loadCredentialsFromFile();
    }
  }

  private loadCredentialsFromFile(): OAuthCredentials | null {
    try {
      // 从account目录加载活动账户
      const accountName = this.getCurrentAccountName();
      if (!accountName) return null;
      
      const accountPath = path.join(__dirname, '..', 'account', `${accountName}.json`);
      const data = fs.readFileSync(accountPath, 'utf-8');
      const parsed = JSON.parse(data);
      if (parsed.claudeAiOauth) {
        return {
          accessToken: parsed.claudeAiOauth.accessToken,
          refreshToken: parsed.claudeAiOauth.refreshToken,
          expiresAt: parsed.claudeAiOauth.expiresAt,
          scopes: parsed.claudeAiOauth.scopes,
          subscriptionType: parsed.claudeAiOauth.subscriptionType
        };
      }
      return null;
    } catch (error) {
      console.error('Error loading credentials from account file:', error);
      return null;
    }
  }

  private async saveCredentials(credentials: OAuthCredentials): Promise<void> {
    try {
      // Update cache immediately
      this.cachedCredentials = credentials;
      this.cacheLoadTime = Date.now();
      
      if (!this.isConnected) {
        // Fallback to file if Redis is not connected
        this.saveCredentialsToFile(credentials);
        return;
      }

      // Save to Redis
      await this.redisClient.set(
        this.REDIS_KEY_CREDENTIALS, 
        JSON.stringify(credentials)
      );
      
      // Also save to file as backup
      this.saveCredentialsToFile(credentials);
      
      console.log(`[${new Date().toISOString()}] Credentials saved to Redis and file`);
    } catch (error) {
      console.error('Error saving credentials to Redis:', error);
      // Fallback to file
      this.saveCredentialsToFile(credentials);
    }
  }

  private saveCredentialsToFile(credentials: OAuthCredentials): void {
    try {
      // 保存到当前活动账户文件
      const accountName = this.getCurrentAccountName();
      if (!accountName) return;
      
      const accountPath = path.join(__dirname, '..', 'account', `${accountName}.json`);
      const fileFormat = {
        claudeAiOauth: credentials
      };
      fs.writeFileSync(accountPath, JSON.stringify(fileFormat, null, 2));
    } catch (error) {
      console.error('Error saving credentials to account file:', error);
    }
  }

  // Key mappings 现在主要存储在Redis中，不再依赖文件

  private async loadRefreshMappings(): Promise<RefreshMapping> {
    try {
      if (!this.isConnected) {
        return {};
      }

      const data = await this.redisClient.get(this.REDIS_KEY_REFRESH_MAP);
      if (data) {
        return JSON.parse(data);
      }
      return {};
    } catch (error) {
      return {};
    }
  }

  private async saveRefreshMappings(mappings: RefreshMapping): Promise<void> {
    try {
      if (this.isConnected) {
        await this.redisClient.set(
          this.REDIS_KEY_REFRESH_MAP,
          JSON.stringify(mappings)
        );
      }
    } catch (error) {
      console.error('Error saving refresh mappings to Redis:', error);
    }
  }

  async refreshToken(accountName?: string): Promise<boolean> {
    // Get account name
    const targetAccount = accountName || this.getCurrentAccountName();
    if (!targetAccount) {
      console.error('No account name specified or found');
      return false;
    }
    
    console.log(`[${new Date().toISOString()}] Refreshing token for account: ${targetAccount}`);
    
    const credentials = await this.loadCredentials();
    if (!credentials) {
      console.error('No credentials found');
      return false;
    }

    const { refreshToken, accessToken: oldAccessToken } = credentials;
    
    console.log(`[${new Date().toISOString()}] Attempting to refresh token via Anthropic Console API...`);

    try {
      // Use the correct Anthropic Console OAuth endpoint with proper headers
      const response = await axios.post(
        'https://console.anthropic.com/v1/oauth/token',
        {
          grant_type: 'refresh_token',
          refresh_token: refreshToken,
          client_id: '9d1c250a-e61b-44d9-88ed-5944d1962f5e'  // Claude OAuth Client ID
        },
        {
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/plain, */*',
            'User-Agent': 'claude-cli/1.0.77 (external, cli)',  // Mimic official CLI
            'Accept-Language': 'en-US,en;q=0.9',
            'Referer': 'https://claude.ai/',
            'Origin': 'https://claude.ai'
          },
          timeout: 30000  // 30 second timeout
        }
      );

      if (response.data) {
        console.log(`[${new Date().toISOString()}] OAuth token response received`);
        
        // Extract ALL fields from response
        const newAccessToken = response.data.access_token;
        const newRefreshToken = response.data.refresh_token;
        const expiresIn = response.data.expires_in;
        const scopes = response.data.scope || credentials.scopes || ''; // 直接使用API返回的字符串格式
        const subscriptionType = credentials.subscriptionType || 'unknown'; // API不返回，保持原值
        
        // Validate required fields
        if (!newAccessToken) {
          console.error('No access_token in response');
          return false;
        }
        if (!newRefreshToken) {
          console.error('No refresh_token in response');
          return false;
        }
        
        // Calculate expiration time
        const newExpiresAt = Date.now() + ((expiresIn || 3600) * 1000);

        // Create complete updated credentials with ALL fields
        const updatedCredentials: OAuthCredentials = {
          accessToken: newAccessToken,
          refreshToken: newRefreshToken,
          expiresAt: newExpiresAt,
          scopes: scopes || credentials.scopes || [],
          subscriptionType: subscriptionType || credentials.subscriptionType || 'unknown'
        };
        
        // 检测是否有变化 - 只有真正改变时才更新文件
        const hasChanges = (
          credentials.accessToken !== newAccessToken ||
          credentials.refreshToken !== newRefreshToken ||
          Math.abs(credentials.expiresAt - newExpiresAt) > 1000 || // 允许1秒误差
          credentials.scopes !== updatedCredentials.scopes || // 现在是字符串比较
          credentials.subscriptionType !== updatedCredentials.subscriptionType
        );
        
        if (!hasChanges) {
          console.log(`[${new Date().toISOString()}] ⚠️ API returned same data, skipping file update to avoid Cloudflare detection`);
          console.log(`  - Same accessToken: ${credentials.accessToken === newAccessToken ? '✓' : '✗'}`);
          console.log(`  - Same refreshToken: ${credentials.refreshToken === newRefreshToken ? '✓' : '✗'}`);
          console.log(`  - Same expiresAt: ${Math.abs(credentials.expiresAt - newExpiresAt) <= 1000 ? '✓' : '✗'}`);
          console.log(`  - Same scopes: ${credentials.scopes === updatedCredentials.scopes ? '✓' : '✗'}`);
          console.log(`  - Same subscriptionType: ${credentials.subscriptionType === updatedCredentials.subscriptionType ? '✓' : '✗'}`);
          return true; // 成功但不更新文件
        }
        
        // Log what we're updating
        console.log(`[${new Date().toISOString()}] 🔄 Detected changes, updating ALL OAuth fields:`);
        console.log(`  ✓ accessToken: ${newAccessToken.substring(0, 20)}... ${credentials.accessToken !== newAccessToken ? '[CHANGED]' : '[SAME]'}`);
        console.log(`  ✓ refreshToken: ${newRefreshToken.substring(0, 20)}... ${credentials.refreshToken !== newRefreshToken ? '[CHANGED]' : '[SAME]'}`);
        console.log(`  ✓ expiresAt: ${new Date(newExpiresAt).toISOString()} (in ${expiresIn} seconds) ${Math.abs(credentials.expiresAt - newExpiresAt) > 1000 ? '[CHANGED]' : '[SAME]'}`);
        console.log(`  ✓ scopes: "${scopes || credentials.scopes}" ${credentials.scopes !== updatedCredentials.scopes ? '[CHANGED]' : '[SAME]'}`);
        console.log(`  ✓ subscriptionType: ${subscriptionType || credentials.subscriptionType} ${credentials.subscriptionType !== updatedCredentials.subscriptionType ? '[CHANGED]' : '[SAME]'}`);
        
        // 🔥 关键：立即强制同步所有存储位置，确保不延误
        console.log(`[${new Date().toISOString()}] 🚀 开始立即同步更新所有存储位置...`);
        
        // 1. 立即更新内存缓存 
        this.cachedCredentials = updatedCredentials;
        this.cacheLoadTime = Date.now();
        console.log(`[${new Date().toISOString()}] ✓ 内存缓存已更新`);
        
        // 2. 立即保存到Redis（多个key确保完整覆盖）
        if (this.isConnected) {
          const savePromises = [];
          
          // 保存到通用credentials key
          savePromises.push(
            this.redisClient.set(this.REDIS_KEY_CREDENTIALS, JSON.stringify(updatedCredentials))
          );
          
          // 保存到账户专用key
          const accountRedisKey = `${this.REDIS_ACCOUNTS_PREFIX}${targetAccount}`;
          const accountData = {
            credentials: updatedCredentials,
            lastUsed: Date.now(),
            lastRefresh: Date.now()
          };
          savePromises.push(
            this.redisClient.set(accountRedisKey, JSON.stringify(accountData))
          );
          
          // 并行执行所有Redis保存操作
          await Promise.all(savePromises);
          console.log(`[${new Date().toISOString()}] ✓ Redis同步完成 (通用key + 账户key: ${accountRedisKey})`);
        } else {
          console.log(`[${new Date().toISOString()}] ⚠️ Redis未连接，跳过Redis保存`);
        }
        
        // 3. 立即保存到JSON文件（确保文件系统同步）
        const accountFilePath = path.join(__dirname, '..', 'account', `${targetAccount}.json`);
        const fileData = {
          claudeAiOauth: updatedCredentials
        };
        fs.writeFileSync(accountFilePath, JSON.stringify(fileData, null, 2));
        
        // 强制文件系统同步，确保数据立即写入磁盘
        const fd = fs.openSync(accountFilePath, 'r');
        fs.fsyncSync(fd);
        fs.closeSync(fd);
        console.log(`[${new Date().toISOString()}] ✓ JSON文件同步完成并强制写入磁盘: ${accountFilePath}`);

        // 4. 立即更新token映射关系（用于追踪token变化）
        if (oldAccessToken !== newAccessToken) {
          const refreshMappings = await this.loadRefreshMappings();
          refreshMappings[oldAccessToken] = newAccessToken;
          await this.saveRefreshMappings(refreshMappings);
          console.log(`[${new Date().toISOString()}] ✓ Token映射关系已更新: ${oldAccessToken.substring(0, 20)}... → ${newAccessToken.substring(0, 20)}...`);
        }

        // 5. 立即验证所有存储位置的同步状态 - 确保万无一失
        console.log(`[${new Date().toISOString()}] 🔍 立即验证所有存储位置同步状态...`);
        
        // 验证JSON文件
        try {
          const verifyFileData = fs.readFileSync(accountFilePath, 'utf-8');
          const verifyFile = JSON.parse(verifyFileData);
          const fileToken = verifyFile.claudeAiOauth?.accessToken;
          if (fileToken === newAccessToken) {
            console.log(`[${new Date().toISOString()}] ✓ JSON文件验证通过: accessToken已同步`);
          } else {
            console.error(`[${new Date().toISOString()}] ❌ JSON文件验证失败: accessToken不匹配!`);
          }
        } catch (error) {
          console.error(`[${new Date().toISOString()}] ❌ JSON文件验证失败:`, error);
        }
        
        // 验证Redis
        if (this.isConnected) {
          try {
            const accountRedisKey = `${this.REDIS_ACCOUNTS_PREFIX}${targetAccount}`;
            const verifyRedisData = await this.redisClient.get(accountRedisKey);
            if (verifyRedisData) {
              const verified = JSON.parse(verifyRedisData);
              const redisToken = verified.credentials?.accessToken;
              if (redisToken === newAccessToken) {
                console.log(`[${new Date().toISOString()}] ✓ Redis验证通过: accessToken已同步`);
              } else {
                console.error(`[${new Date().toISOString()}] ❌ Redis验证失败: accessToken不匹配!`);
              }
              
              // 详细验证所有字段
              console.log(`[${new Date().toISOString()}] Redis完整验证 ${targetAccount}:`);
              console.log(`  - accessToken: ${verified.credentials?.accessToken === newAccessToken ? '✓' : '❌'}`);
              console.log(`  - refreshToken: ${verified.credentials?.refreshToken === newRefreshToken ? '✓' : '❌'}`);
              console.log(`  - expiresAt: ${verified.credentials?.expiresAt === newExpiresAt ? '✓' : '❌'}`);
              console.log(`  - scopes: ${verified.credentials?.scopes === scopes ? '✓' : '❌'}`);
              console.log(`  - subscriptionType: ${verified.credentials?.subscriptionType === subscriptionType ? '✓' : '❌'}`);
            } else {
              console.error(`[${new Date().toISOString()}] ❌ Redis验证失败: 未找到账户数据!`);
            }
          } catch (error) {
            console.error(`[${new Date().toISOString()}] ❌ Redis验证失败:`, error);
          }
        }

        console.log(`[${new Date().toISOString()}] 🎉 Token刷新完成，所有存储位置已立即同步: ${targetAccount}`);
        console.log(`[${new Date().toISOString()}] 💡 新连接将立即使用新的accessToken: ${newAccessToken.substring(0, 30)}...`);
        
        // 🔥 刷新成功后立即清除所有缓存，确保新会话使用新token
        console.log(`[${new Date().toISOString()}] 🧹 清除所有缓存，强制使用新token...`);
        this.cachedCredentials = null;
        this.cacheLoadTime = 0;
        
        // 🔥 通知多账户管理器强制重载该账户，确保JSON文件和Redis信息完全同步
        if (this.accountManager) {
          try {
            // 强制重载账户（同时会更新Redis）
            await this.accountManager.loadAccount(targetAccount, true);
            
            // 额外确保Redis中账户信息已更新
            await this.accountManager.saveAccount(targetAccount, updatedCredentials);
            
            console.log(`[${new Date().toISOString()}] ✅ 多账户管理器已强制重载并同步Redis: ${targetAccount}`);
          } catch (error) {
            console.error(`[${new Date().toISOString()}] ❌ 通知多账户管理器失败:`, error);
          }
        } else {
          console.log(`[${new Date().toISOString()}] ⚠️ 多账户管理器未设置，跳过通知`);
        }
        
        // 🔥 发送全局刷新事件通知（如果有其他模块监听）
        console.log(`[${new Date().toISOString()}] 📢 发送token刷新完成事件: ${targetAccount}`);
        this.emitTokenRefreshEvent(targetAccount, newAccessToken);
        
        return true;
      } else {
        console.error('No data in OAuth response');
        return false;
      }
    } catch (error: any) {
      console.error(`[${new Date().toISOString()}] Error refreshing token:`, error.message);
      if (error.response) {
        console.error('Response status:', error.response.status);
        console.error('Response data:', error.response.data);
      }
      return false;
    }

    return false;
  }

  async checkAndRefresh(): Promise<void> {
    const credentials = await this.loadCredentials();
    if (!credentials) return;

    const { expiresAt } = credentials;
    const now = Date.now();
    const oneMinuteBeforeExpiry = expiresAt - (1 * 60 * 1000); // 过期前1分钟刷新

    if (now >= oneMinuteBeforeExpiry) {
      console.log(`[${new Date().toISOString()}] Token expiring within 1 minute, refreshing...`);
      await this.refreshToken();
    } else {
      const minutesUntilRefresh = Math.ceil((oneMinuteBeforeExpiry - now) / 60000);
      console.log(`[${new Date().toISOString()}] Token valid for ${minutesUntilRefresh} more minutes (will refresh 1 minute BEFORE expiry)`);
    }
  }

  // 🎯 多账户精确时间事件触发机制 - 为每个账户独立管理定时器
  async startMultiAccountPreciseRefresh(): Promise<void> {
    console.log(`[${new Date().toISOString()}] 🎯 启动多账户精确时间触发的token刷新机制`);
    
    // 停止所有现有定时器
    this.stopAllAccountTimers();
    
    // 为所有账户设置独立的定时器
    await this.scheduleRefreshForAllAccounts();
  }
  
  // 🔍 为所有账户设置独立的精确定时器
  async scheduleRefreshForAllAccounts(): Promise<void> {
    try {
      console.log(`[${new Date().toISOString()}] 🔍 扫描所有账户，为每个账户设置独立定时器...`);
      
      // 从account目录扫描所有账户文件
      const accountDir = path.join(__dirname, '..', 'account');
      if (!fs.existsSync(accountDir)) {
        console.log(`[${new Date().toISOString()}] ⚠️ 账户目录不存在: ${accountDir}`);
        return;
      }
      
      const files = fs.readdirSync(accountDir);
      const accountFiles = files.filter(f => f.endsWith('.json') && !f.startsWith('.'));
      
      console.log(`[${new Date().toISOString()}] 📋 发现 ${accountFiles.length} 个账户文件`);
      
      let activeTimers = 0;
      
      for (const file of accountFiles) {
        try {
          const accountName = file.replace('.json', '');
          await this.scheduleAccountRefresh(accountName);
          activeTimers++;
        } catch (error) {
          console.error(`[${new Date().toISOString()}] ❌ 设置账户 ${file} 定时器失败:`, error);
        }
      }
      
      console.log(`[${new Date().toISOString()}] ✅ 已为 ${activeTimers} 个账户设置独立定时器`);
      
    } catch (error) {
      console.error(`[${new Date().toISOString()}] ❌ 扫描账户失败:`, error);
      // 出错时回退到30分钟轮询
      console.log(`[${new Date().toISOString()}] 🔄 回退到30分钟轮询模式`);
      this.startAutoRefresh(30);
    }
  }

  // 🎯 为单个账户设置精确定时器
  async scheduleAccountRefresh(accountName: string, skipRefreshCheck: boolean = false): Promise<void> {
    try {
      // 清除该账户现有定时器
      this.clearAccountTimer(accountName);
      
      // 从JSON文件读取账户信息
      const filePath = path.join(__dirname, '..', 'account', `${accountName}.json`);
      if (!fs.existsSync(filePath)) {
        console.log(`[${new Date().toISOString()}] ⚠️ 账户文件不存在: ${accountName}`);
        return;
      }
      
      const fileData = fs.readFileSync(filePath, 'utf-8');
      const parsed = JSON.parse(fileData);
      
      if (!parsed.claudeAiOauth?.expiresAt) {
        console.log(`[${new Date().toISOString()}] ⚠️ 账户 ${accountName} 缺少过期时间信息`);
        return;
      }
      
      const expiresAt = parsed.claudeAiOauth.expiresAt;
      const oneMinuteBeforeExpiry = expiresAt - 60000; // 过期前1分钟
      const now = Date.now();
      const minutesLeft = Math.floor((expiresAt - now) / 60000);
      const refreshIn = Math.floor((oneMinuteBeforeExpiry - now) / 60000);
      
      console.log(`[${new Date().toISOString()}] 📊 账户: ${accountName}`);
      console.log(`  🔑 过期时间: ${new Date(expiresAt).toISOString()}`);
      console.log(`  ⏰ 剩余时间: ${minutesLeft} 分钟`);
      console.log(`  🚨 下次刷新: ${refreshIn > 0 ? refreshIn + '分钟后' : '立即刷新'}`);
      console.log(`  ⌛ 精确触发时间: ${new Date(oneMinuteBeforeExpiry).toISOString()}`);
      
      // 如果已经到了刷新时间且不跳过检查，立即刷新
      if (!skipRefreshCheck && now >= oneMinuteBeforeExpiry) {
        console.log(`[${new Date().toISOString()}] 🔄 ${accountName} 需要立即刷新!`);
        await this.refreshToken(accountName);
        // 刷新后会在refreshToken成功回调中重新设置定时器，此处返回避免重复
        return;
      }
      
      // 设置该账户的专用定时器
      const delayMs = oneMinuteBeforeExpiry - now;
      const delayMinutes = Math.floor(delayMs / 60000);
      const delaySeconds = Math.floor((delayMs % 60000) / 1000);
      
      console.log(`[${new Date().toISOString()}] ⏰ 为账户 ${accountName} 设置定时器`);
      console.log(`  🕒 触发时间: ${new Date(oneMinuteBeforeExpiry).toISOString()}`);
      console.log(`  ⌛ 等待时间: ${delayMinutes} 分钟 ${delaySeconds} 秒`);
      
      const timer = setTimeout(async () => {
        console.log(`[${new Date().toISOString()}] 🎯 账户 ${accountName} 定时器触发: 开始刷新`);
        
        // 更新Redis中的状态为正在刷新
        await this.saveAccountRefreshSchedule(accountName, {
          accountName,
          expiresAt,
          refreshAt: oneMinuteBeforeExpiry,
          scheduledAt: now,
          delayMs,
          status: 'refreshing'
        });
        
        const refreshSuccess = await this.refreshToken(accountName);
        
        if (refreshSuccess) {
          console.log(`[${new Date().toISOString()}] ✅ 账户 ${accountName} 刷新成功`);
          
          // 🔄 基于新的过期时间重新计算并设置下一次触发时间
          console.log(`[${new Date().toISOString()}] 🔄 读取新的过期时间，重新计算触发时间...`);
          
          // 读取刷新后的新过期时间
          const newFilePath = path.join(__dirname, '..', 'account', `${accountName}.json`);
          if (fs.existsSync(newFilePath)) {
            const newFileData = fs.readFileSync(newFilePath, 'utf-8');
            const newParsed = JSON.parse(newFileData);
            
            if (newParsed.claudeAiOauth?.expiresAt) {
              const newExpiresAt = newParsed.claudeAiOauth.expiresAt;
              const newRefreshAt = newExpiresAt - 60000; // 新过期时间提前1分钟
              const currentTime = Date.now();
              const newDelayMs = newRefreshAt - currentTime;
              
              const hoursLeft = Math.floor((newExpiresAt - currentTime) / (60 * 60 * 1000));
              const minutesLeft = Math.floor(((newExpiresAt - currentTime) % (60 * 60 * 1000)) / (60 * 1000));
              const refreshInMinutes = Math.floor(newDelayMs / (60 * 1000));
              
              console.log(`[${new Date().toISOString()}] 📊 新的时间信息:`);
              console.log(`  🔑 新过期时间: ${new Date(newExpiresAt).toISOString()}`);
              console.log(`  ⏰ Token有效期: ${hoursLeft}小时${minutesLeft}分钟`);
              console.log(`  🚨 下次触发时间: ${new Date(newRefreshAt).toISOString()}`);
              console.log(`  ⌛ 距离下次刷新: ${refreshInMinutes}分钟`);
              
              // 🔥 更新Redis中的调度信息
              await this.saveAccountRefreshSchedule(accountName, {
                accountName,
                expiresAt: newExpiresAt,
                refreshAt: newRefreshAt,
                scheduledAt: currentTime,
                delayMs: newDelayMs,
                status: 'completed'
              });
              
              // 🔄 基于新的触发时间设置下一次定时器 (跳过刷新检查避免递归)
              console.log(`[${new Date().toISOString()}] 🔄 基于新过期时间为账户 ${accountName} 重新设置定时器...`);
              await this.scheduleAccountRefresh(accountName, true);
              
            } else {
              console.error(`[${new Date().toISOString()}] ❌ 无法读取新的过期时间`);
            }
          } else {
            console.error(`[${new Date().toISOString()}] ❌ 账户文件不存在: ${newFilePath}`);
          }
        } else {
          console.error(`[${new Date().toISOString()}] ❌ 账户 ${accountName} 刷新失败，1分钟后重试`);
          
          // 刷新失败，1分钟后重试
          setTimeout(async () => {
            console.log(`[${new Date().toISOString()}] 🔄 账户 ${accountName} 重试刷新...`);
            await this.scheduleAccountRefresh(accountName);
          }, 60000);
          
          // 更新状态为失败
          await this.saveAccountRefreshSchedule(accountName, {
            accountName,
            expiresAt,
            refreshAt: oneMinuteBeforeExpiry,
            scheduledAt: now,
            delayMs,
            status: 'failed'
          });
        }
      }, delayMs);
      
      // 保存到账户定时器Map
      this.accountTimers.set(accountName, timer);
      
      // 保存定时器信息到Redis
      await this.saveAccountRefreshSchedule(accountName, {
        accountName,
        expiresAt,
        refreshAt: oneMinuteBeforeExpiry,
        scheduledAt: now,
        delayMs,
        status: 'scheduled'
      });
      
      console.log(`[${new Date().toISOString()}] ✅ 账户 ${accountName} 定时器设置完成`);
      
    } catch (error) {
      console.error(`[${new Date().toISOString()}] ❌ 为账户 ${accountName} 设置定时器失败:`, error);
    }
  }

  // 💾 保存账户刷新调度信息到Redis
  async saveAccountRefreshSchedule(accountName: string, schedule: {
    accountName: string;
    expiresAt: number;
    refreshAt: number;
    scheduledAt: number;
    delayMs: number;
    status: 'scheduled' | 'refreshing' | 'completed' | 'failed';
  }): Promise<void> {
    try {
      if (this.isConnected) {
        const key = `${this.REDIS_REFRESH_SCHEDULE}${accountName}`;
        await this.redisClient.set(key, JSON.stringify(schedule));
        console.log(`[${new Date().toISOString()}] 📝 已保存账户 ${accountName} 的刷新调度信息到Redis`);
      }
    } catch (error) {
      console.error(`[${new Date().toISOString()}] ❌ 保存刷新调度信息失败:`, error);
    }
  }

  // 🧹 清除单个账户的定时器
  clearAccountTimer(accountName: string): void {
    const timer = this.accountTimers.get(accountName);
    if (timer) {
      clearTimeout(timer);
      this.accountTimers.delete(accountName);
      console.log(`[${new Date().toISOString()}] 🧹 已清除账户 ${accountName} 的定时器`);
    }
  }

  // 🧹 停止所有账户定时器
  stopAllAccountTimers(): void {
    console.log(`[${new Date().toISOString()}] 🧹 停止所有账户定时器...`);
    for (const [accountName, timer] of this.accountTimers) {
      clearTimeout(timer);
      console.log(`[${new Date().toISOString()}] 🧹 已清除账户 ${accountName} 的定时器`);
    }
    this.accountTimers.clear();
    console.log(`[${new Date().toISOString()}] ✅ 所有账户定时器已清除`);
  }

  // 📊 获取所有账户的定时器状态
  async getAccountTimerStatus(): Promise<Array<{
    accountName: string;
    hasTimer: boolean;
    schedule?: any;
  }>> {
    const status = [];
    
    // 获取所有在内存中的定时器
    for (const [accountName] of this.accountTimers) {
      let schedule = null;
      try {
        if (this.isConnected) {
          const key = `${this.REDIS_REFRESH_SCHEDULE}${accountName}`;
          const data = await this.redisClient.get(key);
          if (data) {
            schedule = JSON.parse(data);
          }
        }
      } catch (error) {
        console.error(`获取账户 ${accountName} 调度信息失败:`, error);
      }
      
      status.push({
        accountName,
        hasTimer: true,
        schedule
      });
    }
    
    return status;
  }

  // 🔗 设置多账户管理器引用
  setAccountManager(accountManager: any): void {
    this.accountManager = accountManager;
    console.log(`[${new Date().toISOString()}] 🔗 已设置多账户管理器引用`);
  }

  // 📢 发送token刷新完成事件
  emitTokenRefreshEvent(accountName: string, newAccessToken: string): void {
    // 这里可以添加事件发射逻辑，比如WebSocket通知等
    console.log(`[${new Date().toISOString()}] 📢 账户 ${accountName} token已刷新，新token: ${newAccessToken.substring(0, 30)}...`);
    
    // 可以在这里添加更多的通知机制，比如：
    // - WebSocket广播
    // - Redis发布订阅
    // - 事件发射器等
  }

  // 保留原有的轮询方式作为备用
  startAutoRefresh(intervalMinutes: number = 30): void {
    console.log(`[${new Date().toISOString()}] Starting auto-refresh with ${intervalMinutes} minute interval`);
    
    // Initial check
    this.checkAndRefresh();

    // Set up interval
    this.refreshInterval = setInterval(() => {
      this.checkAndRefresh();
    }, intervalMinutes * 60 * 1000);
  }

  // 🎯 兼容旧接口，启动多账户精确时间触发机制
  async startPreciseAutoRefresh(): Promise<void> {
    return await this.startMultiAccountPreciseRefresh();
  }

  stopAutoRefresh(): void {
    // 停止旧的轮询定时器
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
      clearTimeout(this.refreshInterval);
      this.refreshInterval = null;
      console.log(`[${new Date().toISOString()}] Legacy auto-refresh stopped`);
    }
    
    // 停止所有账户定时器
    this.stopAllAccountTimers();
  }

  async getCurrentAccessToken(): Promise<string | null> {
    // This uses the cached credentials if available and valid
    const credentials = await this.loadCredentials();
    return credentials ? credentials.accessToken : null;
  }
  
  async getCurrentCredentials(): Promise<OAuthCredentials | null> {
    // This uses the cached credentials if available and valid
    return await this.loadCredentials();
  }
  
  // Get cached token without any Redis/file access (for maximum performance)
  getCachedAccessToken(): string | null {
    if (this.cachedCredentials) {
      const now = Date.now();
      // 只要token还没过期就继续使用
      if (now < this.cachedCredentials.expiresAt) {
        return this.cachedCredentials.accessToken;
      }
    }
    return null;
  }

  async getTokenMapping(oldToken: string): Promise<string | null> {
    const mappings = await this.loadRefreshMappings();
    return mappings[oldToken] || null;
  }

  async disconnect(): Promise<void> {
    if (this.isConnected) {
      await this.redisClient.quit();
      this.isConnected = false;
      console.log(`[${new Date().toISOString()}] Disconnected from Redis`);
    }
  }
}

export default TokenRefresherRedis;

// If run directly, perform a manual refresh
if (require.main === module) {
  const refresher = new TokenRefresherRedis();
  
  setTimeout(async () => {
    const success = await refresher.refreshToken();
    if (success) {
      console.log('Token refresh completed successfully');
    } else {
      console.log('Token refresh failed');
    }
    await refresher.disconnect();
    process.exit(success ? 0 : 1);
  }, 1000); // Wait for Redis connection
}