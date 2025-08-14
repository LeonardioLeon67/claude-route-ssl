import * as fs from 'fs';
import * as path from 'path';
import { createClient, RedisClientType } from 'redis';

export interface OAuthCredentials {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  scopes?: string; // 改为字符串格式，与API返回格式一致
  subscriptionType?: string;
}

export interface AccountCredentials {
  claudeAiOauth: OAuthCredentials;
}

export interface AccountInfo {
  credentials: OAuthCredentials;
  lastUsed?: number;
  createdAt?: number;
  lastRefresh?: number;
}

class MultiAccountManager {
  private redisClient: RedisClientType;
  private accountDir: string;
  private isConnected: boolean = false;
  
  // Memory cache for all accounts
  private accountsCache: Map<string, AccountInfo> = new Map();
  private cacheLoadTime: number = 0;
  private readonly CACHE_TTL = 60000; // Cache for 1 minute
  
  // Redis keys
  private readonly REDIS_KEY_PREFIX = 'accounts:';
  private readonly REDIS_ACTIVE_ACCOUNT = 'active_account';
  private readonly REDIS_PORT = 6380;

  constructor() {
    this.accountDir = path.join(__dirname, '..', 'account');
    
    // Ensure account directory exists
    if (!fs.existsSync(this.accountDir)) {
      fs.mkdirSync(this.accountDir, { recursive: true });
    }
    
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
      console.log(`[${new Date().toISOString()}] Multi-Account Manager connected to Redis on port ${this.REDIS_PORT}`);
      this.isConnected = true;
    });

    // Connect to Redis
    this.connectRedis();
  }

  private async connectRedis(): Promise<void> {
    try {
      await this.redisClient.connect();
      // Load all accounts on startup
      await this.loadAllAccounts();
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Failed to connect to Redis:`, error);
    }
  }

  // Load all accounts from the account directory and subdirectories
  private async loadAllAccounts(): Promise<void> {
    try {
      // 递归扫描所有子目录中的JSON文件
      const accountFiles = this.scanAccountFiles(this.accountDir);
      
      for (const accountName of accountFiles) {
        await this.loadAccount(accountName);
      }
      
      console.log(`[${new Date().toISOString()}] Loaded ${this.accountsCache.size} accounts from all directories`);
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error loading accounts:`, error);
    }
  }

  // 递归扫描账户文件
  private scanAccountFiles(dir: string): string[] {
    const accountFiles: string[] = [];
    
    try {
      const items = fs.readdirSync(dir);
      
      for (const item of items) {
        if (item.startsWith('.')) continue; // 跳过隐藏文件
        
        const fullPath = path.join(dir, item);
        const stat = fs.statSync(fullPath);
        
        if (stat.isDirectory()) {
          // 递归扫描子目录
          accountFiles.push(...this.scanAccountFiles(fullPath));
        } else if (item.endsWith('.json')) {
          // 找到账户文件
          const accountName = item.replace('.json', '');
          accountFiles.push(accountName);
        }
      }
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error scanning directory ${dir}:`, error);
    }
    
    return accountFiles;
  }

  // 查找账户文件的完整路径（支持子目录）
  private findAccountFile(accountName: string): string | null {
    const fileName = `${accountName}.json`;
    
    // 递归查找文件
    const findInDir = (dir: string): string | null => {
      try {
        const items = fs.readdirSync(dir);
        
        for (const item of items) {
          if (item.startsWith('.')) continue; // 跳过隐藏文件
          
          const fullPath = path.join(dir, item);
          const stat = fs.statSync(fullPath);
          
          if (stat.isDirectory()) {
            // 递归搜索子目录
            const found = findInDir(fullPath);
            if (found) return found;
          } else if (item === fileName) {
            // 找到文件
            return fullPath;
          }
        }
      } catch (error) {
        console.error(`[${new Date().toISOString()}] Error searching directory ${dir}:`, error);
      }
      
      return null;
    };
    
    return findInDir(this.accountDir);
  }

  // Load a specific account
  async loadAccount(accountName: string, forceReload: boolean = false): Promise<AccountInfo | null> {
    try {
      // 🔥 强制重载时，立即清除缓存，确保获取最新数据
      if (forceReload) {
        console.log(`[${new Date().toISOString()}] 🔄 强制重载账户 ${accountName}，清除缓存`);
        this.accountsCache.delete(accountName);
        this.cacheLoadTime = 0; // 重置缓存时间
      }
      
      // Check cache first (unless forced reload)
      const now = Date.now();
      if (!forceReload && this.accountsCache.has(accountName) && (now - this.cacheLoadTime < this.CACHE_TTL)) {
        const cached = this.accountsCache.get(accountName)!;
        
        // Check if token is still valid (not expired)
        if (cached.credentials.expiresAt > now) {
          console.log(`[${new Date().toISOString()}] 📋 使用缓存数据: ${accountName}`);
          return cached;
        } else {
          console.log(`[${new Date().toISOString()}] ⏰ 缓存token已过期，重新加载: ${accountName}`);
        }
      }
      
      // 🔥 强制从文件系统重新读取最新数据 - 支持在子目录中查找
      const filePath = this.findAccountFile(accountName);
      if (!filePath) {
        console.error(`[${new Date().toISOString()}] Account file not found: ${accountName}`);
        return null;
      }
      
      console.log(`[${new Date().toISOString()}] 📁 从文件重新读取账户数据: ${filePath}`);
      const fileData = fs.readFileSync(filePath, 'utf-8');
      const parsed: AccountCredentials = JSON.parse(fileData);
      
      const accountInfo: AccountInfo = {
        credentials: parsed.claudeAiOauth,
        lastUsed: now,
        createdAt: fs.statSync(filePath).birthtimeMs
      };
      
      // 🔥 立即更新缓存 - 不能有延迟
      this.accountsCache.set(accountName, accountInfo);
      this.cacheLoadTime = now;
      console.log(`[${new Date().toISOString()}] ✓ 内存缓存已立即更新: ${accountName}`);
      
      // 🔥 立即同步到Redis - 确保一致性
      if (this.isConnected) {
        await this.redisClient.set(
          `${this.REDIS_KEY_PREFIX}${accountName}`,
          JSON.stringify(accountInfo)
        );
        console.log(`[${new Date().toISOString()}] ✓ Redis已立即同步: ${this.REDIS_KEY_PREFIX}${accountName}`);
      } else {
        console.log(`[${new Date().toISOString()}] ⚠️ Redis未连接，跳过Redis同步`);
      }
      
      const accessTokenPreview = accountInfo.credentials.accessToken.substring(0, 30);
      const minutesLeft = Math.floor((accountInfo.credentials.expiresAt - now) / 60000);
      console.log(`[${new Date().toISOString()}] ✅ 账户加载完成: ${accountName}`);
      console.log(`  🔑 AccessToken: ${accessTokenPreview}...`);
      console.log(`  ⏰ Token过期时间: ${minutesLeft} 分钟后`);
      console.log(`  🏷️ Scopes: ${accountInfo.credentials.scopes || 'N/A'}`);
      console.log(`  📦 SubscriptionType: ${accountInfo.credentials.subscriptionType || 'N/A'}`);
      
      return accountInfo;
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error loading account ${accountName}:`, error);
      return null;
    }
  }

  // Save account to file and Redis
  async saveAccount(accountName: string, credentials: OAuthCredentials): Promise<void> {
    try {
      const accountInfo: AccountInfo = {
        credentials: credentials,
        lastUsed: Date.now(),
        createdAt: this.accountsCache.get(accountName)?.createdAt || Date.now()
      };
      
      // Update cache
      this.accountsCache.set(accountName, accountInfo);
      this.cacheLoadTime = Date.now();
      
      // Save to file - 如果文件已存在，保存到原位置；否则保存到根目录
      let filePath = this.findAccountFile(accountName);
      if (!filePath) {
        // 文件不存在，保存到根目录
        filePath = path.join(this.accountDir, `${accountName}.json`);
      }
      
      const fileData: AccountCredentials = {
        claudeAiOauth: credentials
      };
      fs.writeFileSync(filePath, JSON.stringify(fileData, null, 2));
      
      // Save to Redis
      if (this.isConnected) {
        await this.redisClient.set(
          `${this.REDIS_KEY_PREFIX}${accountName}`,
          JSON.stringify(accountInfo)
        );
      }
      
      console.log(`[${new Date().toISOString()}] Saved account: ${accountName}`);
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error saving account ${accountName}:`, error);
    }
  }

  // Get all accounts
  async getAllAccounts(): Promise<Map<string, AccountInfo>> {
    // Refresh cache if needed
    const now = Date.now();
    if (now - this.cacheLoadTime > this.CACHE_TTL) {
      await this.loadAllAccounts();
    }
    return this.accountsCache;
  }

  // Get a specific account
  async getAccount(accountName: string, forceReload: boolean = false): Promise<AccountInfo | null> {
    return await this.loadAccount(accountName, forceReload);
  }

  // Set active account
  async setActiveAccount(accountName: string): Promise<boolean> {
    try {
      const account = await this.loadAccount(accountName);
      if (!account) {
        console.error(`[${new Date().toISOString()}] Cannot set active account: ${accountName} not found`);
        return false;
      }
      
      if (this.isConnected) {
        await this.redisClient.set(this.REDIS_ACTIVE_ACCOUNT, accountName);
      }
      
      // Also save to a file for persistence
      const activeFilePath = path.join(this.accountDir, '.active');
      fs.writeFileSync(activeFilePath, accountName);
      
      console.log(`[${new Date().toISOString()}] Set active account: ${accountName}`);
      return true;
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error setting active account:`, error);
      return false;
    }
  }

  // Get active account name
  async getActiveAccountName(): Promise<string | null> {
    try {
      let activeAccountName: string | null = null;
      
      // Try Redis first
      if (this.isConnected) {
        activeAccountName = await this.redisClient.get('active_account');
      }
      
      // Fallback to file
      if (!activeAccountName) {
        const activeFilePath = path.join(this.accountDir, '.active');
        if (fs.existsSync(activeFilePath)) {
          activeAccountName = fs.readFileSync(activeFilePath, 'utf-8').trim();
        }
      }
      
      // Default to first available account
      if (!activeAccountName && this.accountsCache.size > 0) {
        activeAccountName = Array.from(this.accountsCache.keys())[0];
      }
      
      return activeAccountName;
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error getting active account name:`, error);
      return null;
    }
  }

  // Get active account
  async getActiveAccount(): Promise<AccountInfo | null> {
    try {
      let activeAccountName: string | null = null;
      
      // Try Redis first
      if (this.isConnected) {
        activeAccountName = await this.redisClient.get(this.REDIS_ACTIVE_ACCOUNT);
      }
      
      // Fallback to file
      if (!activeAccountName) {
        const activeFilePath = path.join(this.accountDir, '.active');
        if (fs.existsSync(activeFilePath)) {
          activeAccountName = fs.readFileSync(activeFilePath, 'utf-8').trim();
        }
      }
      
      // Default to first available account
      if (!activeAccountName && this.accountsCache.size > 0) {
        activeAccountName = Array.from(this.accountsCache.keys())[0];
        await this.setActiveAccount(activeAccountName);
      }
      
      if (activeAccountName) {
        return await this.loadAccount(activeAccountName);
      }
      
      return null;
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error getting active account:`, error);
      return null;
    }
  }

  // List all accounts with their status
  async listAccounts(): Promise<Array<{name: string, active: boolean, expiresIn: number}>> {
    const accounts = await this.getAllAccounts();
    const activeAccount = await this.getActiveAccount();
    const now = Date.now();
    
    const activeAccountName = await this.getActiveAccountName();
    const list = Array.from(accounts.entries()).map(([name, info]) => ({
      name,
      active: name === activeAccountName,
      expiresIn: Math.floor((info.credentials.expiresAt - now) / 60000) // minutes
    }));
    
    return list;
  }

  // Get account that needs refresh soonest
  async getAccountNeedingRefresh(): Promise<{name: string, account: AccountInfo} | null> {
    const accounts = await this.getAllAccounts();
    const now = Date.now();
    
    let soonestExpiry = Infinity;
    let accountToRefresh: {name: string, account: AccountInfo} | null = null;
    
    for (const [name, account] of accounts) {
      const oneMinuteBeforeExpiry = account.credentials.expiresAt - 60000;
      if (now >= oneMinuteBeforeExpiry && account.credentials.expiresAt < soonestExpiry) {
        soonestExpiry = account.credentials.expiresAt;
        accountToRefresh = {name, account};
      }
    }
    
    return accountToRefresh;
  }

  // Disconnect from Redis
  async disconnect(): Promise<void> {
    if (this.isConnected) {
      await this.redisClient.quit();
      this.isConnected = false;
      console.log(`[${new Date().toISOString()}] Disconnected from Redis`);
    }
  }
}

export default MultiAccountManager;