#!/bin/bash
# ============================================================
#  Rclone 多路同步工具 (tongbu) 在线安装脚本
#  源仓库: wk4796/tongbu
# ============================================================

# --- 配置区域 ---
# 你的 GitHub Raw 链接
SOURCE_URL="https://raw.githubusercontent.com/wk4796/tongbu/main/tongbu.sh"
# 本地保存的文件名
DEST_FILE="tongbu.sh"
# 想要使用的命令别名
ALIAS_NAME="tongbu"

# 获取当前路径作为安装目录
DEST_PATH="$(pwd)/${DEST_FILE}"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 主函数 ---
main() {
    echo -e "${GREEN}=== 开始安装 Rclone 多路同步工具 (tongbu) ===${NC}"

    # 1. 检查下载工具
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl -sL"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget -qO-"
    else
        echo -e "${RED}错误：需要 curl 或 wget，请先安装其中之一。${NC}"
        return 1
    fi

    # 2. 检查依赖 (Rclone & Tmux)
    echo -e "${YELLOW}正在检查系统依赖...${NC}"
    MISSING_DEPS=()
    if ! command -v rclone &> /dev/null; then MISSING_DEPS+=("rclone"); fi
    if ! command -v tmux &> /dev/null; then MISSING_DEPS+=("tmux"); fi
    
    if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
        echo -e "${CYAN}检测到缺失依赖: ${MISSING_DEPS[*]}，正在尝试自动安装...${NC}"
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y "${MISSING_DEPS[@]}"
        elif command -v yum &> /dev/null; then
            sudo yum install -y "${MISSING_DEPS[@]}"
        else
            echo -e "${RED}无法自动安装依赖，请手动安装后重试。${NC}"
        fi
    else
        echo "依赖检查通过！"
    fi

    # 3. 从 GitHub 下载脚本
    echo -e "${YELLOW}正在从 GitHub 下载脚本...${NC}"
    echo -e "源: ${CYAN}${SOURCE_URL}${NC}"
    
    # 下载并检查是否成功
    if ! ${DOWNLOADER} "${SOURCE_URL}" > "${DEST_PATH}"; then
        echo -e "${RED}下载失败！请检查网络或 URL 是否正确。${NC}"
        return 1
    fi

    # 简单检查下载的文件是否包含 HTML (防止 404 错误页面被保存为脚本)
    if grep -q "<!DOCTYPE html>" "${DEST_PATH}" || grep -q "404: Not Found" "${DEST_PATH}"; then
        echo -e "${RED}错误：下载的内容似乎是 404 页面而非脚本。请检查 GitHub 链接是否有效。${NC}"
        rm "${DEST_PATH}"
        return 1
    fi
    echo "下载成功！"

    # 4. 设置执行权限
    chmod +x "${DEST_PATH}"

    # 5. 配置 Shell 环境 (添加别名)
    echo -e "${YELLOW}正在配置 Shell 环境...${NC}"
    PROFILE_FILE=""
    SHELL_TYPE=""

    if [ -n "$ZSH_VERSION" ]; then PROFILE_FILE="$HOME/.zshrc"; SHELL_TYPE="Zsh";
    elif [ -n "$BASH_VERSION" ]; then PROFILE_FILE="$HOME/.bashrc"; SHELL_TYPE="Bash";
    elif [ -f "$HOME/.zshrc" ]; then PROFILE_FILE="$HOME/.zshrc"; SHELL_TYPE="Zsh";
    elif [ -f "$HOME/.bashrc" ]; then PROFILE_FILE="$HOME/.bashrc"; SHELL_TYPE="Bash";
    fi

    if [ -n "$PROFILE_FILE" ]; then
        echo -e "配置文件: ${CYAN}${PROFILE_FILE}${NC}"
        ALIAS_CMD="alias ${ALIAS_NAME}='${DEST_PATH}'"

        if grep -qF -- "${ALIAS_CMD}" "${PROFILE_FILE}"; then
            echo -e "${GREEN}别名已存在，跳过。${NC}"
        else
            echo "" >> "${PROFILE_FILE}"
            echo "# Tongbu Tool Alias" >> "${PROFILE_FILE}"
            echo "${ALIAS_CMD}" >> "${PROFILE_FILE}"
            echo "别名写入成功！"
        fi
    fi

    # 6. 立即生效 (仅当前会话)
    eval "alias ${ALIAS_NAME}='${DEST_PATH}'"

    echo ""
    echo -e "${GREEN}🎉 安装完成！${NC}"
    echo -e "您可以直接输入命令： ${YELLOW}${ALIAS_NAME}${NC} 来启动工具。"
    echo ""
    
    # 7. 询问是否运行
    echo -n "是否立即运行? [y/n]: "
    read -r run_now
    if [[ "$run_now" =~ ^[Yy]$ ]]; then
        ${DEST_PATH}
    fi
}

main
