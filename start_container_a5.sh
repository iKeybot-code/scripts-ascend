#!/bin/bash

if [ $# -lt 2 ]; then
    echo "Error: need 2 or more arguments. Check your command."
    echo "Help : exec >>> sh start-container.sh <IMAGE_INFO> <CONTAINER_NAME> [-w|--workspace WORK_SPACE] [OPTIONS...]"
    exit 1
fi

IMAGE=$1
NAME=$2
WORK_SPACE="/workspace"

shift 2

# 循环解析剩余的 -- 参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--workspace)
            WORK_SPACE="$2"
            shift 2
            ;;
        -*)
            echo "Error: unknown param $1"
            exit 1
            ;;
        *)
            # 如果后面还有既不带 -- 也不属于参数值的多余参数
            echo "Warn : ignore invalid param $1"
            shift
            ;;
    esac
done

# Run the container using the defined variables
# Note: If you are running bridge network with Docker, please expose available ports for multiple nodes communication in advance.
docker run \
--name $NAME \
--net=host \
--privileged=true --runtime=runc \
--shm-size=500g \
--device /dev/davinci0 \
--device /dev/davinci1 \
--device /dev/davinci2 \
--device /dev/davinci3 \
--device /dev/davinci4 \
--device /dev/davinci5 \
--device /dev/davinci6 \
--device /dev/davinci7 \
--device /dev/davinci_manager \
--device /dev/hisi_hdc \
-w $WORK_SPACE \
-v /home:/home \
-v /data:/data \
-v /mnt:/mnt \
-v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
-v /usr/local/Ascend/firmware:/usr/local/Ascend/firmware \
-v /root/host:/root/host \
-v /usr/local/sbin/npu-smi:/usr/local/sbin/npu-smi \
-v /usr/local/sbin:/usr/local/sbin \
-v /usr/local/dcmi:/usr/local/dcmi \
-v /var/log/npu/:/usr/slog \
-v /mnt:/mnt \
-v /data:/data \
-v /etc/hccl_rootinfo.json:/etc/hccl_rootinfo.json \
-v /usr/lib64:/usr/lib64 \
-v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
-v /usr/local/sbin/npu-smi:/usr/local/sbin/npu-smi \
-v /home/:/home/ \
-v /etc/hixlep:/etc/hixlep \
-u root -it -d  $IMAGE bash
