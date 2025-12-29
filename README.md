# cloudflare-ddns
一个基于cloudflare的ddns脚本

## 使用方法
1. 保存并设置权限
```
# 保存脚本
wget -O cloudflare-ddns.sh https://raw.githubusercontent.com/iP3ter/cloudflare-ddns/main/cloudflare-ddns.sh

# 添加执行权限
chmod +x cloudflare-ddns.sh
```
2. 运行脚本
```
# 交互式菜单模式
./cloudflare-ddns.sh

# 命令行模式
./cloudflare-ddns.sh --daemon    # 启动自动更新
./cloudflare-ddns.sh --update    # 立即更新一次
./cloudflare-ddns.sh --help      # 显示帮助
```

## 功能特点
|功能	| 说明 |
|  ----  | ----  |
| 交互式配置 | 引导式设置，无需手动编辑配置 |
| 自动识别IP |	支持 IPv4 和 IPv6 |
| 定时检查 |	默认10分钟，可自定义 |
| 智能更新 |	IP变化才更新，减少API调用 |
| 系统服务 |	一键设置开机自启 |
| 日志记录 |	完整的运行日志 |
| 配置保存 |	配置文件加密存储 |


## 获取 API Token
1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. 点击右上角头像 → My Profile
3. 选择 API Tokens → Create Token
4. 使用 Edit zone DNS 模板
5. 选择对应的域名区域
6. 创建并复制 Token

## 更新日期
2025年12月22日 完成了初版的更新，如果没有其他想法，多半是不会再更新了
