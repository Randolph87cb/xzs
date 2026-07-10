### 6.3 docker部署

> 注意：本目录保留的是上游旧 Docker Compose 示例，仍包含 MySQL 镜像和 MySQL 初始化说明。当前仓库主线是 PostgreSQL 版；Fly.io 部署请使用根目录 `Dockerfile`、`fly.toml` 和 `docs/fly-managed-postgres-deployment.md`，不要直接套用本文件。

* 打开网站<https://gitee.com/mindskip/xzs-mysql>，找到docker目录，里面有已配置好的文件
* 下载sql脚本，下载教程<https://www.mindskip.net:999>，然后解压sql压缩包，找到xzs-mysql.sql文件，编辑此文件，在文件开头加如下代码：

```xzs-mysql
CREATE DATABASE `xzs` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE xzs;
```

* sql文件改好后，将文件移动到 docker/sql 目录下
* 将整个docker目录中的文件，复制到/usr/local/xzs下面
* 进入到install目录，执行下面命令，安装docker-compose

```docker-compose
cd /usr/local/xzs/install
mv docker-compose-linux-x86_64 /usr/local/bin/docker-compose
chmod +x  /usr/local/bin/docker-compose
docker-compose --version
```

* 执行下面命令，启动信息学客观题一本通网站，有问题可以看下/usr/local/xzs/log中的日志

```docker-xzs
cd /usr/local/xzs
docker-compose up -d
```

* 学生端访问地址为：<http://ip:8000/student>
* 管理员端访问地址为：<http://ip:8000/admin>
