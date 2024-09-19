#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/Hemi.sh"

# 自动安装缺少的依赖项 (git 和 make)
install_dependencies() {
    for cmd in git make; do
        if ! command -v $cmd &> /dev/null; then
            echo "$cmd 未安装。正在自动安装 $cmd... / $cmd is not installed. Installing $cmd..."

            # 检测操作系统类型并执行相应的安装命令
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                sudo apt update
                sudo apt install -y $cmd
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                brew install $cmd
            else
                echo "不支持的操作系统。请手动安装 $cmd。/ Unsupported OS. Please manually install $cmd."
                exit 1
            fi
        fi
    done
    echo "已安装所有依赖项。/ All dependencies have been installed."
}

# 检查 Go 版本是否 >= 1.22.2
check_go_version() {
    if command -v go >/dev/null 2>&1; then
        CURRENT_GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        MINIMUM_GO_VERSION="1.22.2"

        if [ "$(printf '%s\n' "$MINIMUM_GO_VERSION" "$CURRENT_GO_VERSION" | sort -V | head -n1)" = "$MINIMUM_GO_VERSION" ]; then
            echo "当前 Go 版本满足要求: $CURRENT_GO_VERSION / Current Go version meets the requirement: $CURRENT_GO_VERSION"
        else
            echo "当前 Go 版本 ($CURRENT_GO_VERSION) 低于要求的版本 ($MINIMUM_GO_VERSION)，将安装最新的 Go。/ Current Go version ($CURRENT_GO_VERSION) is below the required version ($MINIMUM_GO_VERSION). Installing the latest Go."
            install_go
        fi
    else
        echo "未检测到 Go，正在安装 Go。/ Go is not detected. Installing Go."
        install_go
    fi
}

install_go() {
    wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    source ~/.bashrc
    echo "Go 安装完成，版本: $(go version) / Go installation completed, version: $(go version)"
}

# 检查并安装 Node.js 和 npm
install_node() {
    echo "检测到未安装 npm。正在安装 Node.js 和 npm... / npm is not installed. Installing Node.js and npm..."

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
        sudo apt-get install -y nodejs
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install node
    else
        echo "不支持的操作系统。请手动安装 Node.js 和 npm。/ Unsupported OS. Please manually install Node.js and npm."
        exit 1
    fi

    echo "Node.js 和 npm 安装完成。/ Node.js and npm installation completed."
}

# 安装 pm2
install_pm2() {
    if ! command -v npm &> /dev/null; then
        echo "npm 未安装。/ npm is not installed."
        install_node
    fi

    if ! command -v pm2 &> /dev/null; then
        echo "pm2 未安装。正在安装 pm2... / pm2 is not installed. Installing pm2..."
        npm install -g pm2
    else
        echo "pm2 已安装。/ pm2 is already installed."
    fi
}

# 生成密钥并安装依赖
generate_key() {
    install_dependencies
    check_go_version
    install_pm2

    URL="https://github.com/hemilabs/heminetwork/releases/download/v0.4.3/heminetwork_v0.4.3_linux_amd64.tar.gz"
    FILENAME="heminetwork_v0.4.3_linux_amd64.tar.gz"
    DIRECTORY="/root/heminetwork_v0.4.3_linux_amd64"
    OUTPUT_FILE="$HOME/popm-address.json"

    echo "正在下载 $FILENAME..."
    wget -q "$URL" -O "$FILENAME"

    if [ $? -eq 0 ]; then
        echo "下载完成。"
    else
        echo "下载失败。"
        exit 1
    fi

    echo "正在解压 $FILENAME..."
    tar -xzf "$FILENAME" -C /root

    if [ $? -eq 0 ]; then
        echo "解压完成。"
    else
        echo "解压失败。"
        exit 1
    fi

    echo "删除压缩文件..."
    rm -rf "$FILENAME"

    echo "进入目录 $DIRECTORY..."
    cd "$DIRECTORY" || { echo "目录 $DIRECTORY 不存在。"; exit 1; }

    # 检查并设置 keygen 执行权限
    if [ -f "keygen" ]; then
        chmod +x "keygen"
    else
        echo "未找到 keygen 文件。"
        exit 1
    fi
    
    echo "正在生成公钥..."
    ./keygen -secp256k1 -json -net="testnet" > "$OUTPUT_FILE"

    echo "公钥生成完成。输出文件：$OUTPUT_FILE"
    echo "正在查看密钥文件内容..."
    cat "$OUTPUT_FILE"

    echo "按任意键返回主菜单栏..."
    read -n 1 -s
}

# 运行节点函数
run_node() {
    DIRECTORY="$HOME/heminetwork_v0.4.3_linux_amd64"

    echo "进入目录 $DIRECTORY..."
    cd "$DIRECTORY" || { echo "目录 $DIRECTORY 不存在。"; exit 1; }

    # 设置 popm-address.json 的权限为可读写
    if [ -f "$HOME/popm-address.json" ]; then
        echo "为 popm-address.json 文件设置权限..."
        chmod 600 "$HOME/popm-address.json"  # 仅当前用户可读写
    else
        echo "$HOME/popm-address.json 文件不存在。"
        exit 1
    fi

    # 显示文件内容
    cat "$HOME/popm-address.json"

    # 导入 private_key
    POPM_BTC_PRIVKEY=$(jq -r '.private_key' "$HOME/popm-address.json")
    read -p "检查 https://mempool.space/zh/testnet 上的 sats/vB 值并输入 / Check the sats/vB value on https://mempool.space/zh/testnet and input: " POPM_STATIC_FEE

    export POPM_BTC_PRIVKEY=$POPM_BTC_PRIVKEY
    export POPM_STATIC_FEE=$POPM_STATIC_FEE
    export POPM_BFG_URL="wss://testnet.rpc.hemi.network/v1/ws/public"

    echo "启动节点..."
    pm2 start ./popmd --name popmd
    pm2 save

    echo "按任意键返回主菜单栏..."
    read -n 1 -s
}

# 升级版本函数
upgrade_version() {
    URL="https://github.com/hemilabs/heminetwork/releases/download/v0.4.3/heminetwork_v0.4.3_linux_amd64.tar.gz"
    FILENAME="heminetwork_v0.4.3_linux_amd64.tar.gz"
    DIRECTORY="/root/heminetwork_v0.4.3_linux_amd64"
    ADDRESS_FILE="$HOME/popm-address.json"
    BACKUP_FILE="$HOME/popm-address.json.bak"

    echo "备份 address.json 文件..."
    if [ -f "$ADDRESS_FILE" ]; then
        cp "$ADDRESS_FILE" "$BACKUP_FILE"
        echo "备份完成：$BACKUP_FILE"
    else
        echo "未找到 address.json 文件，无法备份。"
    fi

    echo "正在下载新版本 $FILENAME..."
    wget -q "$URL" -O "$FILENAME"

    if [ $? -eq 0 ]; then
        echo "下载完成。"
    else
        echo "下载失败。"
        exit 1
    fi

    echo "删除旧版本目录..."
    rm -rf "$DIRECTORY"

    echo "正在解压新版本..."
    tar -xzf "$FILENAME" -C /root

    if [ $? -eq 0 ]; then
        echo "解压完成。"
    else
        echo "解压失败。"
        exit 1
    fi

    echo "删除压缩文件..."
    rm -rf "$FILENAME"

    # 恢复 address.json 文件
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$ADDRESS_FILE"
        echo "恢复 address.json 文件：$ADDRESS_FILE"
    else
        echo "备份文件不存在，无法恢复。"
    fi

    echo "版本升级完成！"
    echo "按任意键返回主菜单栏..."
    read -n 1 -s
}

# 备份 address.json 函数
backup_address_json() {
    ADDRESS_FILE="$HOME/popm-address.json"
    BACKUP_FILE="$HOME/popm-address.json.bak"

    echo "备份 address.json 文件..."
    if [ -f "$ADDRESS_FILE" ]; then
        cp "$ADDRESS_FILE" "$BACKUP_FILE"
        echo "备份完成：$BACKUP_FILE"
    else
        echo "未找到 address.json 文件，无法备份。"
    fi

    echo "按任意键返回主菜单栏..."
    read -n 1 -s
}

# 查看日志函数
view_logs() {
    DIRECTORY="heminetwork_v0.4.3_linux_amd64"

    echo "进入目录 $DIRECTORY..."
    cd "$HOME/$DIRECTORY" || { echo "目录 $DIRECTORY 不存在。"; exit 1; }

    echo "查看 pm2 日志..."
    pm2 logs popmd

    echo "按任意键返回主菜单栏..."
    read -n 1 -s
}

