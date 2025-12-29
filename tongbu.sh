#!/bin/bash

# ==========================================
#  Rclone 动态多路同步工具 (Ultra版)
#  功能：自定义缓存路径 + 无限目标网盘 + 自动后台
# ==========================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 1. 环境自检与 Tmux ---
check_environment() {
    if ! command -v rclone &> /dev/null; then
        echo -e "${RED}错误: 请先安装 rclone。${NC}"
        exit 1
    fi

    # 自动进入 tmux 后台
    if [ -z "$TMUX" ]; then
        echo -e "${CYAN}检测到未在 tmux 后台运行。${NC}"
        echo -n "是否自动创建安全后台会话(推荐)? [y/n]: "
        read -r choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            tmux new-session -s rclone_auto "bash $0 inside_tmux"
            exit 0
        fi
    fi
}

# --- 2. 动态配置向导 ---
get_user_input() {
    clear
    echo -e "${GREEN}=== Rclone 动态多路同步向导 ===${NC}"
    
    # 1. 询问源网盘
    echo -e "\n${YELLOW}[1/4] 请输入源网盘路径 (例如 onedrive:/movies):${NC}"
    read -r SOURCE
    while [ -z "$SOURCE" ]; do
        echo -e "${RED}路径不能为空，请重新输入:${NC}"
        read -r SOURCE
    done

    # 2. 询问目标网盘数量 (核心升级点)
    echo -e "\n${YELLOW}[2/4] 请问有几个目标网盘要同步? (输入数字):${NC}"
    read -r TARGET_COUNT
    while ! [[ "$TARGET_COUNT" =~ ^[0-9]+$ ]] || [ "$TARGET_COUNT" -lt 1 ]; do
        echo -e "${RED}请输入有效的数字 (至少 1 个):${NC}"
        read -r TARGET_COUNT
    done

    # 3. 循环询问每个目标网盘的路径
    DEST_ARRAY=() # 初始化数组
    for ((i=1; i<=TARGET_COUNT; i++)); do
        echo -e "${CYAN}  -> 请输入第 $i 个目标网盘的路径:${NC}"
        read -r temp_dest
        while [ -z "$temp_dest" ]; do
             read -r temp_dest
        done
        DEST_ARRAY+=("$temp_dest")
    done

    # 4. 询问临时缓存路径 (核心升级点)
    echo -e "\n${YELLOW}[3/4] 请输入 VPS 本地临时缓存路径:${NC}"
    echo -e "(直接回车默认使用: /tmp/rclone_cache，重启自动清空，推荐)"
    read -r input_dir
    LOCAL_DIR=${input_dir:-"/tmp/rclone_cache"}

    # 5. 询问批次大小
    echo -e "\n${YELLOW}[4/4] 每次同时处理几个文件? (回车默认: 2):${NC}"
    read -r input_batch
    BATCH_SIZE=${input_batch:-2}
}

# --- 3. 确认逻辑 ---
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
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then exit 0; fi
}

# --- 4. 执行同步 ---
run_sync() {
    mkdir -p "$LOCAL_DIR"
    TEMP_LIST="$LOCAL_DIR/temp_file_list.txt"

    echo -e "\n${CYAN}正在获取源文件列表...${NC}"
    # 获取列表
    rclone lsf -R "$SOURCE" --files-only > "$TEMP_LIST"
    
    # 转为数组
    mapfile -t all_files < "$TEMP_LIST"
    total_files=${#all_files[@]}
    echo -e "${GREEN}共发现 $total_files 个文件。${NC}"

    # 开始循环
    for ((i=0; i<total_files; i+=BATCH_SIZE)); do
        batch=("${all_files[@]:i:BATCH_SIZE}")
        echo -e "\n${YELLOW}>>> 处理进度: $((i/BATCH_SIZE + 1)) / $(( (total_files+BATCH_SIZE-1)/BATCH_SIZE )) 批次${NC}"

        # A. 下载到本地
        for file in "${batch[@]}"; do
            echo -e "  [下载] $file"
            rclone copyto "$SOURCE/$file" "$LOCAL_DIR/$file"
        done

        # B. 循环分发到所有目标网盘
        for dest in "${DEST_ARRAY[@]}"; do
            echo -e "  [上传] -> $dest"
            # 使用 copy 自动跳过已存在且相同的文件
            rclone copy "$LOCAL_DIR" "$dest"
        done

        # C. 立即清理本地 (释放 VPS 空间)
        echo -e "  [清理] 删除本地缓存..."
        # 再次确认路径不是根目录，防止误删
        if [[ "$LOCAL_DIR" != "/" ]]; then
            rm -rf "${LOCAL_DIR:?}"/*
        fi
    done

    echo -e "\n${GREEN}所有任务完成！${NC}"
    rm -rf "$LOCAL_DIR"
}

# --- 入口 ---
if [ "$1" == "inside_tmux" ]; then
    get_user_input
    confirm_config
    run_sync
    echo "按任意键退出..."
    read -n 1
else
    check_environment
    get_user_input
    confirm_config
    run_sync
fi
