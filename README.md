# ⌨️ 在您想要安装的机器上，进入目标目录，执行以下命令即可：
```
source <(curl -sL https://raw.githubusercontent.com/wk4796/tongbu/main/install_tongbu.sh)
```
### 脚本别名为：`tongbu`
直接输入`tongbu`就可以进入脚本
---
# 重新连接 SSH 后，想要回到之前那个“正在跑进度条”的界面，只需要运行一条命令。
核心命令：回到现场

登录 SSH 后，直接输入以下命令并回车：
```
tmux attach -t tongbu_session
```
