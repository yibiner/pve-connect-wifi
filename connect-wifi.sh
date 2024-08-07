#!/usr/bin/bash

# 检查是否具有root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请以root用户运行此脚本"
    exit 1
fi

# 检查命令是否存在的函数
check_command() {
    if ! command -v $1 &> /dev/null
    then
        echo "$1 未安装，是否安装？"
        read -p "[yes/no]: " install
        install=$(echo $install | tr '[:upper:]' '[:lower:]') # 转换为小写
        if [[ "$install" == "yes" || "$install" == "y" ]]; then
            apt update && apt install -y $1
            if [ $? -ne 0 ]; then
                echo "安装 $1 失败"
                exit 1
            fi
        else
            exit 1
        fi
    fi
}

# 检查必要的命令
check_command wpa_supplicant
check_command iw

# 获取无线网卡名称
wl_dev=$(iw dev | awk '$1=="Interface"{print $2}')
if [ -z "$wl_dev" ]; then
    echo "没有找到无线网卡"
    exit 1
fi

# 设置无线网卡为UP状态
wlst=$(ip link show $wl_dev | grep 'state UP' | awk '{print $9}')
if [ -z "$wlst" ]; then
    ip link set $wl_dev up
    if [ $? -eq 0 ]; then
        echo -e "\e[1;36m$wl_dev 已设置为UP状态...\e[0m"
    else
        echo "无法设置 $wl_dev 为UP状态"
        exit 1
    fi
fi

# 配置文件路径
config_file="/etc/wpa_supplicant/wpa_supplicant-$wl_dev.conf"
echo -e "\e[1;32m配置文件路径为: $config_file\e[0m"

if [ -f "$config_file" ]; then
    echo -e "\e[1;36m已配置的WiFi:\e[0m"
    ssid_list=$(grep 'ssid="' $config_file | awk -F '"' '{print $2}')
    if [ -z "$ssid_list" ]; then
        echo "没有配置WiFi，请连接新WiFi"
        choose="yes"
    else
        sum=0
        for ssid in $ssid_list; do
            wifi_connect[$sum]=$ssid
            echo -e "\e[1;36m$sum : $ssid\e[0m"
            let sum++
        done

        echo -e "\e[1;36m是否要连接新的WiFi？\e[0m"
        read -p "[yes/no]: " choose
        choose=$(echo $choose | tr '[:upper:]' '[:lower:]') # 转换为小写
        while [[ "$choose" != "yes" && "$choose" != "y" && "$choose" != "no" ]]; do
            echo "请输入 'yes' 或 'no'."
            read -p "[yes/no]: " choose
            choose=$(echo $choose | tr '[:upper:]' '[:lower:]') # 转换为小写
        done
    fi
else
    echo "没有配置WiFi，请连接新WiFi"
    choose="yes"
fi

if [[ "$choose" == "no" ]]; then
    echo -e "\e[1;36m将使用当前配置文件连接...\e[0m"
    wpa_supplicant -B -D wext -i $wl_dev -c $config_file
    if [ $? -eq 0 ]; then
        sleep 2s
        current_ssid=$(iw dev $wl_dev link | grep 'SSID' | awk '{print $2}')
        echo -e "\e[1;36m当前连接的WiFi名称: $current_ssid\e[0m"
    else
        echo "连接WiFi失败"
        exit 1
    fi
else
    echo -e "\e[1;36m扫描WiFi设备...\e[0m"
    iw dev $wl_dev scan | grep -E '^SSID:'
    read -p "WiFi名称: " widev
    read -p "密码: " wipas
    wpa_passphrase $widev $wipas >> $config_file
    wpa_supplicant -B -D wext -i $wl_dev -c $config_file
    if [ $? -eq 0 ]; then
        sleep 2s
        echo -e "\e[1;36m已连接到新WiFi: $widev\e[0m"
    else
        echo "连接WiFi失败"
        exit 1
    fi
fi

# 启用 DHCP
read -p "是否启用DHCP？[yes/no]: " enable_dhcp
enable_dhcp=$(echo $enable_dhcp | tr '[:upper:]' '[:lower:]') # 转换为小写
while [[ "$enable_dhcp" != "yes" && "$enable_dhcp" != "y" && "$enable_dhcp" != "no" ]]; do
    echo "请输入 'yes' 或 'no'."
    read -p "是否启用DHCP？[yes/no]: " enable_dhcp
    enable_dhcp=$(echo $enable_dhcp | tr '[:upper:]' '[:lower:]') # 转换为小写
done
if [[ "$enable_dhcp" == "yes" || "$enable_dhcp" == "y" ]]; then
    dhclient $wl_dev
    if [ $? -eq 0 ]; then
        sleep 2s
        # 输出当前无线网卡的IP地址
        ip_addr=$(ip addr show $wl_dev | grep 'inet ' | awk '{print $2}')
        echo -e "\e[1;36m当前连接的WiFi IP地址: $ip_addr\e[0m"
    else
        echo "获取IP地址失败"
        exit 1
    fi
fi

# 设置wpa_supplicant和dhclient开机启动
read -p "是否将上述配置设置为开机启动？[yes/no]: " enable_startup
enable_startup=$(echo $enable_startup | tr '[:upper:]' '[:lower:]') # 转换为小写
while [[ "$enable_startup" != "yes" && "$enable_startup" != "y" && "$enable_startup" != "no" ]]; do
    echo "请输入 'yes' 或 'no'."
    read -p "是否将上述配置设置为开机启动？[yes/no]: " enable_startup
    enable_startup=$(echo $enable_startup | tr '[:upper:]' '[:lower:]') # 转换为小写
done
if [[ "$enable_startup" == "yes" || "$enable_startup" == "y" ]]; then
    systemctl enable wpa_supplicant@$wl_dev
    if [ $? -eq 0 ]; then
        echo -e "\e[1;32mwpa_supplicant服务设置为开机启动成功\e[0m"
    else
        echo -e "\e[1;31mwpa_supplicant服务设置为开机启动失败\e[0m"
    fi

    # 创建并配置DHCP服务配置文件
    dhcp_config_file="/etc/systemd/network/00-wireless-dhcp.network"
    echo -e "[Match]\nName=$wl_dev\n\n[Network]\nDHCP=yes" > $dhcp_config_file
    echo -e "\e[1;32m已创建DHCP服务配置文件: $dhcp_config_file\e[0m"

    # 启用systemd-networkd服务
    systemctl enable systemd-networkd.service
    if [ $? -eq 0 ]; then
        echo -e "\e[1;32mDHCP服务设置为开机启动成功\e[0m"
    else
        echo -e "\e[1;31mDHCP服务设置为开机启动失败\e[0m"
    fi
fi
