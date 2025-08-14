import express from 'express';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
import cors from 'cors';

const app = express();
const PORT = 8079;

// 日志文件路径
const LOG_DIR = path.join(process.cwd(), 'logs');
const FORWARD_LOG = path.join(LOG_DIR, 'forward-monitor.log');
const REQUEST_DETAIL_LOG = path.join(LOG_DIR, 'request-details.json');

// 确保日志目录存在
if (!fs.existsSync(LOG_DIR)) {
  fs.mkdirSync(LOG_DIR, { recursive: true });
}

// 中间件
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.text({ limit: '50mb' }));
app.use(express.raw({ limit: '50mb' }));

// 格式化日期时间
function formatTimestamp(): string {
  return new Date().toISOString();
}

// 写入日志
function writeLog(message: string): void {
  const logEntry = `[${formatTimestamp()}] ${message}\n`;
  fs.appendFileSync(FORWARD_LOG, logEntry);
  console.log(logEntry.trim());
}

// 写入详细请求日志
function writeDetailedLog(data: any): void {
  const logEntry = {
    timestamp: formatTimestamp(),
    ...data
  };
  
  // 读取现有日志
  let logs = [];
  if (fs.existsSync(REQUEST_DETAIL_LOG)) {
    try {
      const content = fs.readFileSync(REQUEST_DETAIL_LOG, 'utf-8');
      logs = JSON.parse(content);
    } catch (e) {
      logs = [];
    }
  }
  
  // 添加新日志
  logs.push(logEntry);
  
  // 保留最近1000条记录
  if (logs.length > 1000) {
    logs = logs.slice(-1000);
  }
  
  // 写入文件
  fs.writeFileSync(REQUEST_DETAIL_LOG, JSON.stringify(logs, null, 2));
}

// 提取重要headers
function extractImportantHeaders(headers: any): any {
  const important = [
    'authorization',
    'x-api-key',
    'anthropic-version',
    'anthropic-beta',
    'anthropic-client-name',
    'anthropic-client-version',
    'user-agent',
    'content-type'
  ];
  
  const extracted: any = {};
  for (const key of important) {
    if (headers[key]) {
      // 脱敏处理
      if (key === 'authorization' || key === 'x-api-key') {
        const value = headers[key];
        if (value.length > 20) {
          extracted[key] = value.substring(0, 20) + '...';
        } else {
          extracted[key] = value;
        }
      } else {
        extracted[key] = headers[key];
      }
    }
  }
  return extracted;
}

// 全量转发中间件
app.use('*', async (req, res) => {
  const startTime = Date.now();
  const clientIp = req.ip || req.socket.remoteAddress;
  const method = req.method;
  const originalUrl = req.originalUrl;
  const targetUrl = `https://api.anthropic.com${originalUrl}`;

  writeLog(`===============================================`);
  writeLog(`新请求: ${method} ${originalUrl}`);
  writeLog(`客户端IP: ${clientIp}`);
  writeLog(`目标URL: ${targetUrl}`);
  
  // 记录客户端headers
  const clientHeaders = extractImportantHeaders(req.headers);
  writeLog(`客户端Headers: ${JSON.stringify(clientHeaders, null, 2)}`);

  try {
    // 准备转发headers
    const forwardHeaders: any = {};
    
    // 复制所有headers，除了一些需要特殊处理的
    for (const [key, value] of Object.entries(req.headers)) {
      if (key.toLowerCase() !== 'host' && 
          key.toLowerCase() !== 'connection' &&
          key.toLowerCase() !== 'content-length') {
        forwardHeaders[key] = value;
      }
    }

    // 构建请求配置
    const config: any = {
      method: req.method,
      url: targetUrl,
      headers: forwardHeaders,
      maxRedirects: 5,
      validateStatus: () => true // 接受所有状态码
    };

    // 添加请求体
    if (req.body && ['POST', 'PUT', 'PATCH'].includes(method)) {
      config.data = req.body;
      writeLog(`请求体大小: ${JSON.stringify(req.body).length} 字节`);
      
      // 如果是messages API，记录模型信息
      if (originalUrl.includes('/v1/messages') && req.body.model) {
        writeLog(`使用模型: ${req.body.model}`);
      }
    }

    // 发送请求到官方API
    writeLog(`正在转发到官方API...`);
    const response = await axios(config);
    
    const responseTime = Date.now() - startTime;
    writeLog(`官方API响应状态: ${response.status}`);
    writeLog(`响应时间: ${responseTime}ms`);
    
    // 记录官方响应headers
    const responseHeaders = extractImportantHeaders(response.headers);
    writeLog(`官方响应Headers: ${JSON.stringify(responseHeaders, null, 2)}`);

    // 写入详细日志
    writeDetailedLog({
      request: {
        method,
        url: originalUrl,
        headers: clientHeaders,
        bodySize: req.body ? JSON.stringify(req.body).length : 0,
        model: req.body?.model
      },
      response: {
        status: response.status,
        headers: responseHeaders,
        time: responseTime
      },
      clientIp,
      forwardedTo: targetUrl
    });

    // 设置响应headers
    for (const [key, value] of Object.entries(response.headers)) {
      if (key.toLowerCase() !== 'connection' && 
          key.toLowerCase() !== 'transfer-encoding') {
        res.setHeader(key, value as string);
      }
    }

    // 返回响应给客户端
    res.status(response.status).send(response.data);
    
    // 记录响应内容摘要
    if (response.data) {
      const dataStr = typeof response.data === 'string' 
        ? response.data 
        : JSON.stringify(response.data);
      
      if (dataStr.length < 500) {
        writeLog(`响应内容: ${dataStr}`);
      } else {
        writeLog(`响应内容长度: ${dataStr.length} 字节`);
        
        // 如果是错误响应，记录完整错误
        if (response.status >= 400 && response.data.error) {
          writeLog(`错误详情: ${JSON.stringify(response.data.error)}`);
        }
      }
    }
    
    writeLog(`请求完成，总耗时: ${responseTime}ms`);

  } catch (error: any) {
    const responseTime = Date.now() - startTime;
    writeLog(`转发失败: ${error.message}`);
    writeLog(`失败耗时: ${responseTime}ms`);
    
    // 写入错误日志
    writeDetailedLog({
      request: {
        method,
        url: originalUrl,
        headers: clientHeaders
      },
      error: {
        message: error.message,
        code: error.code,
        time: responseTime
      },
      clientIp,
      forwardedTo: targetUrl
    });

    // 返回错误给客户端
    res.status(500).json({
      error: {
        type: 'forward_error',
        message: error.message || 'Failed to forward request'
      }
    });
  }
});

// 启动服务器
app.listen(PORT, '0.0.0.0', () => {
  writeLog(`===============================================`);
  writeLog(`全量转发监控服务器启动成功`);
  writeLog(`监听端口: ${PORT}`);
  writeLog(`转发目标: https://api.anthropic.com`);
  writeLog(`日志文件: ${FORWARD_LOG}`);
  writeLog(`详细日志: ${REQUEST_DETAIL_LOG}`);
  writeLog(`===============================================`);
  console.log(`\n转发服务器运行在: http://0.0.0.0:${PORT}`);
  console.log(`所有请求将被转发到: https://api.anthropic.com`);
  console.log(`查看日志: tail -f ${FORWARD_LOG}`);
});

// 优雅关闭
process.on('SIGTERM', () => {
  writeLog('收到SIGTERM信号，正在关闭服务器...');
  process.exit(0);
});

process.on('SIGINT', () => {
  writeLog('收到SIGINT信号，正在关闭服务器...');
  process.exit(0);
});