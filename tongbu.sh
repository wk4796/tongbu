#!/bin/bash

# ==========================================
#  [tongbu] Rclone 动态多路同步工具 (完美体验版)
#  功能：增量比对 -> 分批下载 -> 多路分发 -> 自动后台
#  特性：支持方向键修改 | 自动列出网盘 | 支持挂载路径
# ==========================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 1. 环境自检与 Tmux 保护 ---
check_environment() {
    if ! command -v rclone &> /dev/null; then
        echo -e "${RED}错误: 未找到 rclone。请运行安装脚本进行修复。${NC}"
        exit 1
    fi
    # 自动进入 tmux 后台
    if [ -z "$TMUX" ]; then
        echo -e "${CYAN}检测到未在 tmux 后台运行。${NC}"
        echo -e "${YELLOW}为了防止 SSH 断开导致数据传输中断，建议使用后台模式。${NC}"
        echo -n "是否自动创建并进入安全后台会话? [y/n]: "
        # 使用 -e 支持方向键
        read -e -r choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            tmux new-session -s tongbu_session "bash $0 inside_tmux"
            exit 0
        fi
    fi
}

# --- 2. 动态配置向导 (双模校验 + 体验优化) ---
get_user_input() {
    clear
    echo -e "${GREEN}=== Rclone 多路同步工具 (tongbu) ===${NC}"
    
    # [优化] 自动列出网盘供参考
    echo -e "\n${CYAN}当前可用网盘列表 (Rclone Remotes):${NC}"
    echo "---------------------------------"
    rclone listremotes
    echo "---------------------------------"

    # --- 获取源路径 (支持 网盘 或 本地目录) ---
    echo -e "\n${YELLOW}[1/4] 请输入源路径 (支持 'onedrive:/src' 或挂载路径 '/mnt/openlist'):${NC}"
    while true; do
        # [优化] read -e 允许方向键修改
        read -e -r SOURCE
        
        # 1. 空值检查
        if [ -z "$SOURCE" ]; then
            echo -e "${RED}输入不能为空，请重新输入:${NC}"
            continue
        fi
        
        # 2. 检查是否为本地目录 (包括挂载点)
        if [ -d "$SOURCE" ]; then
            echo -e "${GREEN}√ 识别为本地/挂载目录: $SOURCE${NC}"
            break
        fi

        # 3. 检查是否为 Rclone 网盘 (提取冒号前的部分进行比对)
        if [[ "$SOURCE" == *":"* ]]; then
            REMOTE_NAME=$(echo "$SOURCE" | cut -d: -f1):
            if rclone listremotes | grep -q "^$REMOTE_NAME$"; then
                echo -e "${GREEN}√ 识别为 Rclone 网盘: $REMOTE_NAME${NC}"
                break
            else
                echo -e "${RED}错误: 找不到名为 '$REMOTE_NAME' 的网盘。${NC}"
            fi
        else
            echo -e "${RED}错误: 路径无效。${NC}"
            echo -e "请输入有效的本地目录路径，或正确的 Rclone 网盘路径(包含冒号)。"
            echo -e "${YELLOW}请重新输入:${NC}"
        fi
    done

    # --- 获取目标数量 ---
    echo -e "\n${YELLOW}[2/4] 请问有几个目标网盘要同步? (输入数字):${NC}"
    while true; do
        read -e -r TARGET_COUNT
        if [[ "$TARGET_COUNT" =~ ^[0-9]+$ ]] && [ "$TARGET_COUNT" -ge 1 ]; then
            break
        else
            echo -e "${RED}请输入有效的数字 (至少 1 个):${NC}"
        fi
    done

    # --- 获取目标路径 (同样支持双模) ---
    DEST_ARRAY=()
    for ((i=1; i<=TARGET_COUNT; i++)); do
        echo -e "${CYAN}  -> 请输入第 $i 个目标网盘的路径:${NC}"
        while true; do
            read -e -r temp_dest
            if [ -n "$temp_dest" ]; then
                # 校验逻辑同上：先查本地目录，再查网盘
                if [ -d "$temp_dest" ]; then
                     DEST_ARRAY+=("$temp_dest")
                     echo -e "${GREEN}√ 目标已确认为目录。${NC}"
                     break
                else
                    if [[ "$temp_dest" == *":"* ]]; then
                        DEST_NAME=$(echo "$temp_dest" | cut -d: -f1):
                        if rclone listremotes | grep -q "^$DEST_NAME$"; then
                            DEST_ARRAY+=("$temp_dest")
                            echo -e "${GREEN}√ 目标已确认为网盘。${NC}"
                            break
                        else
                             echo -e "${RED}错误: 网盘 '$DEST_NAME' 不存在。${NC}"
                        fi
                    else
                         echo -e "${RED}错误: 路径不存在，请检查拼写。${NC}"
                    fi
                fi
            fi
        done
    done

    # --- 临时路径 ---
    echo -e "\n${YELLOW}[3/4] 请输入 VPS 本地临时缓存路径:${NC}"
    echo -e "(直接回车默认: /tmp/tongbu_cache，推荐)"
    read -e -r input_dir
    LOCAL_DIR=${input_dir:-"/tmp/tongbu_cache"}

    # --- 批次大小 ---
    echo -e "\n${YELLOW}[4/4] 每次同时下载几个文件? (回车默认: 2):${NC}"
    read -e -r input_batch
    BATCH_SIZE=${input_batch:-2}
}

# --- 3. 确认配置 ---
confirm_config() {
    echo -e "\n${GREEN}=== 配置确认 ===${NC}"
    echo -e "源路径: $SOURCE"
    echo -e "目标数: $TARGET_COUNT 个"
    for ((i=0; i<${#DEST_ARRAY[@]}; i++)); do
        echo -e "  目标 $((i+1)): ${DEST_ARRAY[$i]}"
    done
    echo -e "本地缓存: $LOCAL_DIR"
    echo -e "批次大小: $BATCH_SIZE"
    echo -e "------------------------"
    echo -n "确认开始吗? [y/n]: "
    read -e -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then exit 0; fi
}

# --- 4. 执行同步核心逻辑 ---
run_sync() {
    mkdir -p "$LOCAL_DIR"
    TEMP_LIST="$LOCAL_DIR/temp_file_list.txt"

    echo -e "\n${CYAN}正在获取源文件列表...${NC}"
    
    # 这里的 lsf 同样支持本地路径和网盘路径
    if ! rclone lsf -R "$SOURCE" --files-only > "$TEMP_LIST"; then
        echo -e "${RED}获取文件列表失败，请检查是否有权限读取该目录。${NC}"
        exit 1
    fi
    
    mapfile -t all_files < "$TEMP_LIST"
    total_files=${#all_files[@]}
    echo -e "${GREEN}共发现 $total_files 个文件。${NC}"

    if [ "$total_files" -eq 0 ]; then
        echo -e "${YELLOW}目录为空，没有文件需要同步。${NC}"
        exit 0
    fi

    for ((i=0; i<total_files; i+=BATCH_SIZE)); do
        batch=("${all_files[@]:i:BATCH_SIZE}")
        echo -e "\n${YELLOW}>>> 正在处理批次: $((i/BATCH_SIZE + 1))${NC}"

        # A. 下载到本地
        for file in "${batch[@]}"; do
            echo -e "  [读取] $file"
            # 如果源是本地目录，copyto 会自动处理
            rclone copyto "$SOURCE/$file" "$LOCAL_DIR/$file"
        done

        # B. 分发到所有目标
        for dest in "${DEST_ARRAY[@]}"; do
            echo -e "  [分发] -> $dest"
            rclone copy "$LOCAL_DIR" "$dest"
        done

        # C. 清理本地缓存
        echo -e "  [清理] 删除本地缓存..."
        if [[ "$LOCAL_DIR" != "/" ]]; then
            rm -rf "${LOCAL_DIR:?}"/*
        fi
    done
    
    echo -e "\n${GREEN}所有任务完成！${NC}"
    rm -rf "$LOCAL_DIR"
}

# --- 程序入口 ---
if [ "$1" == "inside_tmux" ]; then
    get_user_input
    confirm_config
    run_sync
    echo -e "${YELLOW}按任意键退出窗口...${NC}"
    read -n 1
else
    check_environment
    get_user_input
    confirm_config
    run_sync
fi
