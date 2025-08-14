# 🚀 Direct 全局命令使用指南

## 📋 概述

`direct` 是 Claude Route SSL 项目的全局管理命令工具，让你可以在任何目录下轻松管理项目。

### 🎯 安装位置
- **命令文件**: `/home/leon/bin/direct`
- **全局访问**: 已添加到 `PATH` 环境变量
- **项目路径**: `/home/leon/claude-route-ssl/claude-route-ssl`

## 🔧 核心命令

### 📊 项目管理命令

| 命令 | 功能 | 说明 |
|------|------|------|
| `direct run` | 启动项目 | 完整启动所有服务 (Redis + PM2 + Nginx) |
| `direct restart` | 重启项目 | 重新构建并重启所有服务 |
| `direct stop` | 停止项目 | 停止 PM2 进程，保持其他服务运行 |
| `direct status` | 查看状态 | 详细的服务状态检查和监控 |

### 🔑 密钥生成命令

| 命令 | 功能 | 说明 |
|------|------|------|
| `direct medium <账户名>` | 生成Medium密钥 | 生成Medium级别的产品密钥 |
| `direct high <账户名>` | 生成High密钥 | 生成High级别的产品密钥 |

### 📝 监控命令

| 命令 | 功能 | 说明 |
|------|------|------|
| `direct logs` | 查看日志 | 实时显示PM2日志 |
| `direct monitor` | 监控面板 | 启动PM2监控面板 |

### ℹ️ 帮助命令

| 命令 | 功能 | 说明 |
|------|------|------|
| `direct help` | 帮助信息 | 显示所有可用命令 |
| `direct version` | 版本信息 | 显示工具版本 |

## 🎮 使用示例

### 基本项目管理
```bash
# 在任何目录下启动项目
cd /home/user/documents
direct run

# 检查项目状态  
direct status

# 重启服务
direct restart

# 停止服务
direct stop
```

### 密钥生成示例
```bash
# 生成Medium级别密钥
direct medium myaccount

# 生成High级别密钥  
direct high premium-user

# 生成测试账户密钥
direct medium test-account-001
```

### 日志和监控
```bash
# 查看实时日志 (Ctrl+C退出)
direct logs

# 启动监控面板 (按q退出)
direct monitor

# 检查详细状态
direct status
```

### 典型工作流程
```bash
# 1. 启动项目
direct run

# 2. 检查状态确认启动成功
direct status

# 3. 生成客户端密钥
direct medium production-api

# 4. 检查日志确认服务正常
direct logs

# 5. 需要时重启服务
direct restart
```

## 🌟 主要特性

### ✅ 全局访问
- ✅ 可在任何目录下使用
- ✅ 不需要切换到项目目录
- ✅ 命令执行后自动返回原目录

### ✅ 智能路径管理
- ✅ 自动检测项目路径
- ✅ 验证脚本文件存在性
- ✅ 检查执行权限

### ✅ 彩色输出
- 🔵 蓝色：信息提示
- 🟢 绿色：成功状态
- 🟡 黄色：警告信息
- 🔴 红色：错误信息
- 🟣 紫色：路径信息

### ✅ 错误处理
- ✅ 项目路径检查
- ✅ 脚本文件验证
- ✅ 权限检查
- ✅ 详细错误提示

## 🔧 安装验证

### 检查安装
```bash
# 检查命令是否可用
which direct

# 查看版本信息
direct version

# 测试帮助信息
direct help
```

### 检查PATH配置
```bash
# 查看PATH包含/home/leon/bin
echo $PATH | grep "/home/leon/bin"

# 重新加载.bashrc (如果需要)
source ~/.bashrc
```

## 🛠️ 故障排除

### 命令不存在
```bash
# 如果提示 "command not found"
export PATH="/home/leon/bin:$PATH"

# 或重新加载配置
source ~/.bashrc
```

### 权限问题
```bash
# 确保direct有执行权限
chmod +x /home/leon/bin/direct

# 检查文件权限
ls -la /home/leon/bin/direct
```

### 项目路径问题
```bash
# 确保项目路径存在
ls -la /home/leon/claude-route-ssl/claude-route-ssl

# 确保脚本目录存在
ls -la /home/leon/claude-route-ssl/claude-route-ssl/shell/
```

## 📊 命令对应关系

| Direct命令 | 原始脚本 | 说明 |
|-----------|---------|------|
| `direct run` | `./run.sh` | 项目启动 |
| `direct restart` | `./restart.sh` | 项目重启 |
| `direct stop` | `./stop.sh` | 项目停止 |
| `direct status` | `./status.sh` | 状态检查 |
| `direct medium <账户>` | `./medium.sh <账户>` | Medium密钥 |
| `direct high <账户>` | `./high.sh <账户>` | High密钥 |

## 🎯 使用建议

### 日常使用
1. **启动后检查**: 运行 `direct run` 后使用 `direct status` 确认
2. **定期监控**: 使用 `direct status` 定期检查服务状态
3. **更新后重启**: 代码更新后使用 `direct restart`

### 生产环境
1. **状态监控**: 定期运行 `direct status` 检查健康状态
2. **日志监控**: 使用 `direct logs` 监控异常情况
3. **自动化**: 可集成到监控脚本中

---

## 🎉 总结

现在你可以在任何目录下使用 `direct` 命令管理 Claude Route SSL 项目了！

**访问地址**: https://direct.816981.xyz  
**本地测试**: http://127.0.0.1:8080