# 🎯 Direct 全局命令使用指南

## 📋 概述

`direct` 是 Claude Route SSL 项目的全局管理命令，可以在任何目录下使用，无需进入项目目录。

## 🛠️ 安装完成

✅ **direct 命令已安装到**: `/home/leon/bin/direct`
✅ **PATH 环境变量**: 已配置 (通过 ~/.bashrc)
✅ **全局访问**: 可在任何目录使用

## 🚀 基本命令

### 项目管理
```bash
# 启动 Claude Route SSL 项目
direct run

# 重启项目 (代码更新后)
direct restart

# 停止项目
direct stop

# 查看项目状态
direct status
```

### 密钥生成
```bash
# 生成 Medium 级别产品密钥
direct medium 'testuser'

# 生成 High 级别产品密钥
direct high 'production'
```

### 监控和日志
```bash
# 查看实时日志
direct logs

# 打开 PM2 监控面板
direct monitor

# 查看帮助信息
direct help

# 查看版本信息
direct version
```

## 📊 命令详解

### `direct status` - 状态检查
检查所有核心服务：
- ✅ PM2进程状态
- ✅ Redis服务状态
- ✅ Nginx代理状态
- ✅ 端口监听状态
- ✅ HTTPS连通性测试
- ✅ SSL证书状态
- ✅ 系统资源使用

### `direct run` - 启动项目
完整启动流程：
1. 编译 TypeScript 代码
2. 启动 Redis 服务 (端口6380)
3. 启动 PM2 进程 (端口8080)
4. 配置 Nginx 反向代理
5. 验证所有服务状态

### `direct restart` - 重启项目
快速重启流程：
1. 重新编译最新代码
2. 重启 Redis 服务
3. 重启 PM2 进程
4. 重载 Nginx 配置
5. 清理 PM2 日志

### `direct stop` - 停止项目
安全停止流程：
1. 停止 PM2 进程
2. 交互式选择删除进程
3. 保持 Nginx/Redis 运行
4. 显示端口释放状态

## 🔑 密钥生成使用

### Medium 级别密钥
```bash
direct medium 'account_name'
```
- 适用于：中等级别的API访问
- 存储位置：`/product/medium.json`
- Redis存储：`medium_products:[key]`

### High 级别密钥
```bash
direct high 'account_name'
```
- 适用于：高级API访问和生产环境
- 存储位置：`/product/high.json`
- Redis存储：`high_products:[key]`

## 🌐 访问信息

- **HTTPS访问**: https://direct.816981.xyz
- **本地访问**: http://127.0.0.1:8080
- **项目目录**: `/home/leon/claude-route-ssl/claude-route-ssl`

## 📝 使用示例

### 日常开发工作流
```bash
# 1. 检查项目状态
direct status

# 2. 如果服务未运行，启动项目
direct run

# 3. 代码更新后重启
direct restart

# 4. 查看运行日志
direct logs

# 5. 生成测试密钥
direct medium 'development'
```

### 生产环境部署
```bash
# 1. 完整启动项目
direct run

# 2. 验证所有服务正常
direct status

# 3. 生成生产环境密钥
direct high 'production'

# 4. 监控服务状态
direct monitor
```

### 故障排除
```bash
# 1. 检查详细状态
direct status

# 2. 查看错误日志
direct logs

# 3. 重启尝试修复
direct restart

# 4. 如果问题持续，完全重新启动
direct stop
direct run
```

## 🎨 输出颜色说明

- 🔵 **蓝色**: 信息和路径
- 🟢 **绿色**: 成功状态和操作
- 🟡 **黄色**: 警告和命令名称
- 🔴 **红色**: 错误和失败状态
- 🟣 **紫色**: 高级功能和特殊操作
- 🩵 **青色**: 标题和版本信息

## 💡 使用技巧

### 1. 快速状态检查
```bash
# 在任何目录下快速检查服务状态
direct status
```

### 2. 后台运行日志监控
```bash
# 在一个终端窗口中持续监控
direct logs
```

### 3. 系统启动时自动运行
可以将 `direct run` 添加到系统启动脚本中实现开机自启动。

### 4. 脚本集成
可以在其他脚本中调用 direct 命令：
```bash
#!/bin/bash
direct status > /tmp/claude_status.log
if [ $? -eq 0 ]; then
    echo "Claude Route SSL 运行正常"
fi
```

## 🔧 故障排除

### 命令未找到
如果提示 `direct: command not found`：
```bash
# 1. 检查文件是否存在
ls -la /home/leon/bin/direct

# 2. 检查权限
chmod +x /home/leon/bin/direct

# 3. 重新加载环境变量
source ~/.bashrc

# 4. 直接使用完整路径
/home/leon/bin/direct status
```

### 项目目录错误
如果提示项目目录不存在，检查：
```bash
# 确认项目目录存在
ls -la /home/leon/claude-route-ssl/claude-route-ssl/

# 确认脚本目录存在
ls -la /home/leon/claude-route-ssl/claude-route-ssl/shell/
```

## 📞 获取帮助

```bash
# 查看完整帮助信息
direct help

# 查看版本信息
direct version

# 直接运行命令查看可用选项
direct
```

---

**全局命令路径**: `/home/leon/bin/direct`
**项目版本**: v1.0.0
**最后更新**: 2025-08-14