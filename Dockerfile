FROM alpine AS wsdd2-builder

RUN apk add --no-cache make gcc libc-dev linux-headers && wget -O - https://github.com/Netgear/wsdd2/archive/refs/heads/master.tar.gz | tar zxvf - \
 && cd wsdd2-master && make
 
FROM golang:alpine AS goofys-builder

WORKDIR /go/src/app

RUN mkdir -p /go/src/app/github.com/kahing/goofys/ && \
    mkdir -p /mnt/s3 && \
    export GOOFYS_HOME=/go/src/app/github.com/kahing/goofys/
RUN apk update && apk add git
RUN cd /go/src/app/github.com/kahing/ && \
    git clone https://github.com/kahing/goofys.git && \
    cd /go/src/app/github.com/ && \
    go get github.com/Azure/azure-pipeline-go && \
    cd /go/src/app/github.com/kahing/goofys && \
    git submodule init && \
    git submodule update && \
    go install /go/src/app/github.com/kahing/goofys
    
FROM alpine
# alpine:3.14

# goofys 的环境变量
ENV UID=0
ENV GID=0
ENV FILEMOD=0664
ENV DIRMODE=0664
ENV ENDPOINT=https://storage.yandexcloud.net
ENV BACKETNAME=goofys
ENV MOUNTPOINT=/mnt/s3
ENV CREDPOINT=/root/.aws/credentials
ENV HOME=/root
ENV S3FS_ARGS=''
ENV AWS_ACCESS_KEY_ID=
ENV AWS_SECRET_ACCESS_KEY=

# 创建必要的目录和文件
RUN mkdir -p /root/.aws/credentials && \
    touch /root/.aws/credentials/.pass && \
    echo "[default]" > /root/.aws/credentials/.pass && \
    echo "aws_access_key_id = $AWS_ACCESS_KEY_ID" >> /root/.aws/credentials/.pass && \
    echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY" >> /root/.aws/credentials/.pass

# 复制 wsdd2 和 goofys 的二进制文件
COPY --from=wsdd2-builder /wsdd2-master/wsdd2 /usr/sbin
COPY --from=goofys-builder /go/bin/goofys /bin/goofys

# 安装必要的软件包
RUN apk add --no-cache runit tzdata avahi samba fuse && \
    sed -i 's/#enable-dbus=.*/enable-dbus=no/g' /etc/avahi/avahi-daemon.conf && \
    rm -vf /etc/avahi/services/* && \
    mkdir -p /external/avahi && \
    touch /external/avahi/not-mounted

# 定义卷和暴露端口
VOLUME ["/shares", "/mnt/s3"]
EXPOSE 137/udp 139 445

# 健康检查和入口点
COPY . /container/
HEALTHCHECK CMD ["/container/scripts/docker-healthcheck.sh"]
ENTRYPOINT ["/container/scripts/entrypoint.sh"]

# 运行 goofys 的命令
CMD ["/bin/goofys", "-f", "--endpoint=${ENDPOINT}", "--uid=${UID}", "--gid=${GID}", "--file-mode=${FILEMOD}", "--dir-mode=${DIRMODE}", "${S3FS_ARGS}", "${BACKETNAME}", "${MOUNTPOINT}"]
