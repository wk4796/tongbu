#!/bin/bash

# ==========================================
#  [tongbu] Rclone 动态多路同步工具 (GitHub版)
#  功能：增量比对 -> 分批下载 -> 多路分发 -> 自动后台
# ==========================================

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. 环境自检与 Tmux 保护
check_environment() {
    if ! command -v rclone &> /dev/null; then
        echo -e "${RED}错误: 未找到 rclone。请运行安装脚本进行修复。${NC}"
        exit 1
    fi
    # 自动进入 tmux 后台
    if [ -z "$TMUX" ]; then
        echo -e "${CYAN}检测到未在 tmux 后台运行。${NC}"
        echo -e "${YELLOW}为了防止 SSH 断开导致 1TB 数据传输中断，建议使用后台模式。${NC}"
        echo -n "是否自动创建并进入安全后台会话? [y/n]: "
        read -r choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            tmux new-session -s tongbu_session "bash $0 inside_tmux"
            exit 0
        fi
    fi
}

# 2. 动态配置向导
get_user_input() {
    clear
    echo -e "${GREEN}=== Rclone 多路同步工具 (tongbu) ===${NC}"
    
    # 源网盘
    echo -e "\n${YELLOW}[1/4] 请输入源网盘路径 (例如 onedrive:/source):${NC}"
    read -r SOURCE
    while [ -z "$SOURCE" ]; do
        echo -e "${RED}路径不能为空，请重新输入:${NC}"
        read -r SOURCE
    done

    # 目标网盘数量
    echo -e "\n${YELLOW}[2/4] 请问有几个目标网盘要同步? (输入数字):${NC}"
    read -r TARGET_COUNT
    while ! [[ "$TARGET_COUNT" =~ ^[0-9]+$ ]] || [ "$TARGET_COUNT" -lt 1 ]; do
        echo -e "${RED}请输入有效的数字 (至少 1 个):${NC}"
        read -r TARGET_COUNT
    done

    # 循环询问目标
    DEST_ARRAY=()
    for ((i=1; i<=TARGET_COUNT; i++)); do
        echo -e "${CYAN}  -> 请输入第 $i 个目标网盘的路径:${NC}"
        read -r temp_dest
        while [ -z "$temp_dest" ]; do read -r temp_dest; done
        DEST_ARRAY+=("$temp_dest")
    done

    # 临时路径
    echo -e "\n${YELLOW}[3/4] 请输入 VPS 本地临时缓存路径:${NC}"
    echo -e "(直接回车默认: /tmp/tongbu_cache，推荐)"
    read -r input_dir
    LOCAL_DIR=${input_dir:-"/tmp/tongbu_cache"}

    # 批次大小
    echo -e "\n${YELLOW}[4/4] 每次同时下载几个文件? (回车默认: 2):${NC}"
    read -r input_batch
    BATCH_SIZE=${input_batch:-2}
}

# 3. 确认
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

# 4. 执行同步
run_sync() {
    mkdir -p "$LOCAL_DIR"
    TEMP_LIST="$LOCAL_DIR/temp_file_list.txt"

    echo -e "\n${CYAN}正在获取源文件列表...${NC}"
    rclone lsf -R "$SOURCE" --files-only > "$TEMP_LIST"
    mapfile -t all_files < "$TEMP_LIST"
    total_files=${#all_files[@]}
    echo -e "${GREEN}共发现 $total_files 个文件。${NC}"

    for ((i=0; i<total_files; i+=BATCH_SIZE)); do
        batch=("${all_files[@]:i:BATCH_SIZE}")
        echo -e "\n${YELLOW}>>> 正在处理批次: $((i/BATCH_SIZE + 1))${NC}"

        # A. 下载
        for file in "${batch[@]}"; do
            echo -e "  [下载] $file"
            rclone copyto "$SOURCE/$file" "$LOCAL_DIR/$file"
        done

        # B. 分发
        for dest in "${DEST_ARRAY[@]}"; do
            echo -e "  [上传] -> $dest"
            rclone copy "$LOCAL_DIR" "$dest"
        done

        # C. 清理
        echo -e "  [清理] 删除本地缓存..."
        if [[ "$LOCAL_DIR" != "/" ]]; then
            rm -rf "${LOCAL_DIR:?}"/*
        fi
    done
    echo -e "\n${GREEN}所有任务完成！${NC}"
    rm -rf "$LOCAL_DIR"
}

# 入口
if [ "$1" == "inside_tmux" ]; then
    get_user_input; confirm_config; run_sync
    echo "按任意键退出..."; read -n 1
else
    check_environment; get_user_input; confirm_config; run_sync
fi
