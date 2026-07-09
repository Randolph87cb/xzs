# Raspberry Pi 部署说明

本文说明将学之思后端 Jar、PostgreSQL 和 systemd 服务部署到树莓派的推荐流程。普通运行时不建议在树莓派上执行 Maven、前端构建或其他构建期任务；应在开发机或 CI 构建完成后，只拷贝运行所需资产。

## 运行目录

推荐运行目录如下：

```text
/opt/xzs/
  xzs-3.9.0.jar
  sql/xzs-postgresql.sql
  backups/
/var/log/xzs/
/etc/systemd/system/xzs.service
```

建议创建独立系统用户运行服务：

```sh
sudo useradd --system --home /opt/xzs --shell /usr/sbin/nologin xzs
sudo mkdir -p /opt/xzs/sql /opt/xzs/backups /var/log/xzs
sudo chown -R xzs:xzs /opt/xzs /var/log/xzs
```

将构建好的 `xzs-3.9.0.jar` 放到 `/opt/xzs/xzs-3.9.0.jar`，将数据库初始化脚本放到 `/opt/xzs/sql/xzs-postgresql.sql`。

## 安装部署资产

从仓库复制树莓派部署资产：

```sh
sudo install -m 0644 deploy/raspberry-pi/xzs.service /etc/systemd/system/xzs.service
sudo install -m 0750 deploy/raspberry-pi/init-db.sh /opt/xzs/init-db.sh
sudo install -m 0750 deploy/raspberry-pi/backup-db.sh /opt/xzs/backup-db.sh
sudo install -m 0750 deploy/raspberry-pi/restore-db.sh /opt/xzs/restore-db.sh
sudo chown xzs:xzs /opt/xzs/init-db.sh /opt/xzs/backup-db.sh /opt/xzs/restore-db.sh
```

`xzs.service` 是模板文件，必须先替换下面的密码占位符，不能直接带着占位符启动：

```text
SPRING_DATASOURCE_PASSWORD=REPLACE_WITH_XZS_DB_PASSWORD
```

建议使用 `sudoedit /etc/systemd/system/xzs.service` 交互式替换占位符，避免把真实数据库密码直接写进一行 shell history。替换后建议限制 service 文件权限，例如 `sudo chmod 0640 /etc/systemd/system/xzs.service`。同时确认数据库地址、用户名和 Jar 路径符合实际环境。默认模板运行 `/opt/xzs/xzs-3.9.0.jar`，监听 `8000` 端口，使用 `prod` profile，日志写入 `/var/log/xzs`。

数据库脚本需要 `DB_PASSWORD` 时，推荐二选一：

1. 交互式读取到当前 shell 变量，再执行脚本。命令历史只会记录变量名，不会记录真实密码。
2. 写入权限受限的环境文件，例如 `/etc/xzs/db.env`，只允许 root 和 `xzs` 组读取，再在执行脚本前加载。

权限受限环境文件示例：

```sh
sudo install -d -m 0750 -o root -g xzs /etc/xzs
sudo install -m 0640 -o root -g xzs /dev/null /etc/xzs/db.env
sudoedit /etc/xzs/db.env
```

`/etc/xzs/db.env` 内容示例：

```sh
DB_PASSWORD='替换为实际数据库密码'
```

使用环境文件执行脚本时，可先在受控 shell 中加载它；例如备份可使用 `sudo -u xzs sh -c '. /etc/xzs/db.env; exec /opt/xzs/backup-db.sh'`。初始化脚本如需同时覆盖 `DB_NAME`、`DB_USER` 等变量，也可以继续按下面示例传入非敏感配置项。

## 数据库初始化

`init-db.sh` 会创建或更新 `xzs` 数据库用户，创建 `xzs` 数据库，并导入 `/opt/xzs/sql/xzs-postgresql.sql`。脚本不会把数据库密码打印到日志。

默认值：

```sh
DB_NAME=xzs
DB_USER=xzs
DB_HOST=127.0.0.1
DB_PORT=5432
SQL_FILE=/opt/xzs/sql/xzs-postgresql.sql
```

必须显式提供 `DB_PASSWORD`：

```sh
read -rsp 'Database password: ' DB_PASSWORD
echo
sudo DB_PASSWORD="$DB_PASSWORD" /opt/xzs/init-db.sh
unset DB_PASSWORD
```

如需覆盖默认数据库名、用户名、数据库连接地址或 SQL 文件：

```sh
read -rsp 'Database password: ' DB_PASSWORD
echo
sudo DB_NAME=xzs DB_USER=xzs DB_HOST=127.0.0.1 DB_PORT=5432 DB_PASSWORD="$DB_PASSWORD" SQL_FILE=/opt/xzs/sql/xzs-postgresql.sql /opt/xzs/init-db.sh
unset DB_PASSWORD
```

初始化完成后，将同一个数据库密码写入 `/etc/systemd/system/xzs.service` 中的 `SPRING_DATASOURCE_PASSWORD`。

## systemd 启停

修改 service 文件后重新加载 systemd：

```sh
sudo systemctl daemon-reload
sudo systemctl enable xzs
sudo systemctl start xzs
sudo systemctl status xzs
```

查看日志：

```sh
journalctl -u xzs -f
```

服务模板包含适合低资源设备的 Undertow、Hikari 和 JVM 初始参数：

```text
SERVER_UNDERTOW_IO_THREADS=2
SERVER_UNDERTOW_WORKER_THREADS=16
SERVER_UNDERTOW_BUFFER_SIZE=512
SERVER_UNDERTOW_DIRECT_BUFFERS=false
SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE=4
SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE=1
ExecStart=/usr/bin/java -Xms128m -Xmx512m -XX:+UseSerialGC ... -Duser.timezone=Asia/Shanghai -jar /opt/xzs/xzs-3.9.0.jar
```

如果树莓派内存更充足，可以在观察内存、响应时间和 PostgreSQL 状态后，再小幅提高 `-Xmx` 或连接池大小。避免把 JVM 堆设置过高导致系统和 PostgreSQL 进入 swap。

## 备份

`backup-db.sh` 使用 `pg_dump --format custom` 生成带时间戳的备份文件，默认输出到 `/opt/xzs/backups`，并保留最近 7 份。

默认值：

```sh
DB_NAME=xzs
DB_USER=xzs
DB_HOST=127.0.0.1
DB_PORT=5432
BACKUP_DIR=/opt/xzs/backups
RETAIN_BACKUPS=7
```

执行备份：

```sh
read -rsp 'Database password: ' DB_PASSWORD
echo
sudo -u xzs DB_PASSWORD="$DB_PASSWORD" /opt/xzs/backup-db.sh
unset DB_PASSWORD
```

覆盖备份目录或保留份数：

```sh
read -rsp 'Database password: ' DB_PASSWORD
echo
sudo -u xzs DB_PASSWORD="$DB_PASSWORD" BACKUP_DIR=/opt/xzs/backups RETAIN_BACKUPS=14 /opt/xzs/backup-db.sh
unset DB_PASSWORD
```

建议定期将备份复制到树莓派以外的可靠存储，并同时记录对应的 Jar 版本和部署时间。

## 恢复

恢复是破坏性操作，必须显式传入备份文件路径，并设置 `XZS_RESTORE_CONFIRM=YES` 才会执行。脚本会在恢复前再次打印目标数据库和备份文件。

```sh
read -rsp 'Database password: ' DB_PASSWORD
echo
sudo -u xzs DB_PASSWORD="$DB_PASSWORD" XZS_RESTORE_CONFIRM=YES /opt/xzs/restore-db.sh /opt/xzs/backups/xzs-20260709-120000.dump
unset DB_PASSWORD
```

恢复脚本默认连接本机 PostgreSQL 的 `xzs` 数据库：

```sh
DB_NAME=xzs
DB_USER=xzs
DB_HOST=127.0.0.1
DB_PORT=5432
```

如需恢复到其他环境，可通过环境变量覆盖这些值。恢复前建议先停止应用服务，恢复完成后再启动：

```sh
sudo systemctl stop xzs
read -rsp 'Database password: ' DB_PASSWORD
echo
sudo -u xzs DB_PASSWORD="$DB_PASSWORD" XZS_RESTORE_CONFIRM=YES /opt/xzs/restore-db.sh /opt/xzs/backups/xzs-20260709-120000.dump
unset DB_PASSWORD
sudo systemctl start xzs
```

## 访问与健康检查

局域网访问地址：

```text
http://<raspberry-pi-host>:8000
```

健康检查地址：

```text
http://<raspberry-pi-host>:8000/actuator/health
```

如果需要公网访问，建议在 Jar 前面放置反向代理，由反向代理负责 HTTPS 证书和域名入口，再转发到 `127.0.0.1:8000`。
