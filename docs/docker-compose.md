# 最小 Docker Compose 部署

这个方案覆盖最小可运行拓扑：Caddy 反向代理与自签 HTTPS、前端 SPA 静态资源、
构建镜像、PostgreSQL、一次性迁移、站点 provisioning 和应用进程。公网入站
联邦仍需公网 DNS、443 端口映射和受信任证书。

## 已知限制

- 应用本身只发布到 `127.0.0.1:8080`；外部通过 Caddy 的 `443` 访问。
- 前端 `frontend/dist` 是构建产物，必须先执行 `npm run build`；Caddy 以只读
  方式挂载它。
- Caddy 使用本地自签 CA。浏览器需要信任 `certs/commune-root.crt`，或者
  手动跳过证书警告；`curl` 使用 `--cacert`。
- 浏览器登录和写操作通过 HTTPS 正常工作；直接访问 `http://127.0.0.1:8080`
  仍然只适合健康检查和 curl 级冒烟。
- 没有公网入站联邦；应用可以通过 `egress` 网络访问远端和 SMTP。
- 单 app 副本；媒体存储在本地命名卷，不能直接水平扩展。
- `caddy_data` 卷保存本地 CA 和证书；删除该卷后证书会重新生成，客户端需要
  重新信任。
- `docker compose down -v` 会删除数据库、媒体和 Caddy 数据。

## 前置条件

- Docker Engine 24+，带 BuildKit。
- Docker Compose v2.20+，支持 `additional_contexts` 和
  `service_completed_successfully`。
- 一个本地 MyGO 检出。默认路径是 `../../mygo`，与
  [`go.mod`](../go.mod) 的 `replace` 一致。
- 首次构建允许访问 Go 模块代理；之后的构建复用 BuildKit 缓存。
- 首次构建还需要拉取 `golang:1.27.1-bookworm`、`alpine:3.22` 和
  `postgres:18.6-bookworm`。离线环境请预先 `docker pull`。
- 反向代理使用 `caddy:alpine` 镜像；首次启动时 Compose 会拉取。

## 文件

```text
Dockerfile
compose.yaml
.env.example
deploy/
  Caddyfile
  commune.json.template
  entrypoint.sh
  healthcheck.sh
frontend/
  dist/
scripts/
  prepare-mygo-context.sh
certs/
  commune-root.crt
secrets/
  postgres_password
```

## 首次部署

### 1. 准备环境文件

```sh
cp .env.example .env
```

标准同级布局保持：

```sh
MYGO_CONTEXT=../../mygo
```

当前机器的 MyGO 检出在 `../../../go/mygo` 时改为：

```sh
MYGO_CONTEXT=../../../go/mygo
```

### 2. 创建数据库密码

```sh
mkdir -p secrets
openssl rand -hex 32 | tr -d '\n' > secrets/postgres_password
chmod 600 secrets/postgres_password
```

不要在 secret 文件末尾留下换行；应用和 PostgreSQL 读取同一个文件，换行会
造成认证失败。

### 3. 准备配置

```sh
cp deploy/commune.json.template deploy/commune.json
```

编辑 `deploy/commune.json`：

- 把 `sites[0].origin` 改成真实 HTTPS 域名；`deploy/Caddyfile` 中的站点名
  必须与它一致。
- `sites[0].aliases` 预置了 `localhost`，便于本地通过 `https://localhost`
  访问；上线时可以移除。
- `trusted_proxies` 预置为 Compose `frontend` 子网 `172.28.0.0/24`。如果改
  网络子网，必须同步修改。
- 默认关闭公开注册，开启媒体和后台 worker。

`deploy/commune.json` 只包含占位符，不应写入真实密码。保持它对容器用户可读
（默认 `0644` 即可）；容器内以 UID `10001` 运行，`0600` 会导致入口脚本无法
读取模板。容器启动时 `deploy/entrypoint.sh` 会生成
`/run/commune/config.json`：

- `database_url` 由 `COMMUNE_DB_*` 和数据库密码生成，密码会做 URL 编码。
- `smtp.password` 中的 `__SMTP_PASSWORD__` 会被
  `COMMUNE_SMTP_PASSWORD` 或 `COMMUNE_SMTP_PASSWORD_FILE` 替换。

### 4. 构建镜像

直接使用 Compose：

```sh
docker compose config --quiet
docker compose build
```

或者先准备精简的 MyGO 上下文：

```sh
MYGO_SOURCE=../../../go/mygo make docker-build
```

`make docker-build` 会调用 `scripts/prepare-mygo-context.sh`，只复制
`go.mod`、`go.sum`、`prelude/`、`lib/`、`cmd/`、`internal/` 和
`ebnf.txt` 到 `.build/mygo`，然后把 `MYGO_CONTEXT` 指向它。

BuildKit 是必需的。旧 Docker 环境需要：

```sh
DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 docker compose build
```

### 5. 构建前端

```sh
cd frontend
ELM_HOME=/tmp/commune-elm-home npm ci
ELM_HOME=/tmp/commune-elm-home npm run build
cd ..
```

如果 `frontend/dist` 已经存在，可以跳过。Caddy 以只读方式挂载该目录；
缺失时 `docker compose up` 会因 `create_host_path: false` 失败。

### 6. 启动

```sh
docker compose up -d
```

Compose 会按顺序执行：

1. 启动 PostgreSQL 并等待 `pg_isready`。
2. 运行一次 `migrate`。
3. 运行一次 `provision-sites`。
4. 启动 `app` 并执行健康检查。
5. 启动 `caddy`，监听 `443`，使用本地自签 CA 为 `forum.example` 和
   `localhost` 签发证书，并从 `/srv/frontend` 提供 `frontend/dist` 的 SPA
   静态资源。

Caddy 通过 `frontend` 网络访问 `app:8080`，并覆盖
`X-Forwarded-Host` / `X-Forwarded-For`；应用的 `trusted_proxies` 只信任
`172.28.0.0/24`。

查看状态：

```sh
docker compose ps
docker compose logs -f app
docker compose logs -f caddy
```

### 7. 创建管理员

栈已经启动后，用一次性容器执行 provisioning：

```sh
read -rs COMMUNE_ADMIN_PASSWORD
export COMMUNE_ADMIN_PASSWORD
docker compose run --rm --no-deps \
  -e COMMUNE_ADMIN_PASSWORD \
  app provision-admin a alice
unset COMMUNE_ADMIN_PASSWORD
```

创建普通账号：

```sh
read -rs COMMUNE_ACCOUNT_PASSWORD
export COMMUNE_ACCOUNT_PASSWORD
docker compose run --rm --no-deps \
  -e COMMUNE_ACCOUNT_PASSWORD \
  app provision-account a bob bob@example.org
unset COMMUNE_ACCOUNT_PASSWORD
```

`read -rs` 避免密码进入 shell 历史；`-e VAR` 只传递变量名，密码不会出现在
Docker 命令参数或日志里。

## 健康检查

健康端点仍然先做站点解析，所以必须带 `Host` 头：

```sh
curl -i -H 'Host: forum.example' http://127.0.0.1:8080/health/live
curl -i -H 'Host: forum.example' http://127.0.0.1:8080/health/ready
```

期望 `204`。`/health/ready` 还会做有界数据库 ping 和 schema 检查。

容器内健康检查由 `deploy/healthcheck.sh` 完成，它会从渲染后的配置读取
第一个站点的 origin，并自动带上正确的 Host。

## 启用公开注册

1. 生成 outbox secret：

   ```sh
   openssl rand -base64 32 | tr -d '\n'
   ```

2. 在 `deploy/commune.json` 中：

   - 把目标站点的 `registration_enabled` 改为 `true`。
   - 在 `registration` 中加入
     `"outbox_secret_env": "COMMUNE_OUTBOX_SECRET"`。
   - 填写 `smtp.host`、`smtp.from`，以及需要认证时的
     `smtp.username`。

3. 在 `.env` 中设置 `COMMUNE_OUTBOX_SECRET`，并设置
   `COMMUNE_SMTP_PASSWORD`。如果改用 Docker secret，需要在
   `compose.yaml` 中增加 `smtp_password` secret，并在 app 的
   `environment` 中加入
   `COMMUNE_SMTP_PASSWORD_FILE=/run/secrets/smtp_password`。
   `.env` 中包含空格或 `#` 的值需要加引号。

4. 重建 app：

   ```sh
   docker compose up -d --force-recreate app
   ```

注意：`registration.outbox_secret_env` 一旦写入配置，对应的环境变量就不能
为空，否则配置校验会失败。

## 升级

迁移是 forward-only 的。升级前先备份数据库和 `media/local/`：

```sh
docker compose exec -T postgres pg_dump -U commune -Fc commune \
  > "backups/commune-$(date +%Y%m%dT%H%M%S).dump"
```

然后重建并启动：

```sh
docker compose build
docker compose up -d --force-recreate migrate provision-sites app
docker compose ps
```

Compose 在镜像变化时会重建一次性任务。如果镜像没有变化但需要强制重跑迁移，
显式加上 `--force-recreate`。

如果新版本 schema 不兼容，回滚方式是恢复备份并部署旧镜像；仅回退二进制而
保留新 schema 会导致 readiness 失败。

## 备份与恢复

### 数据库

```sh
mkdir -p backups
docker compose exec -T postgres pg_dump -U commune -Fc commune \
  > "backups/commune-$(date +%Y%m%dT%H%M%S).dump"
```

### 媒体

只备份 `local/`。`temporary/` 和 `private-cache/` 是可丢弃的。

```sh
docker run --rm \
  -v commune_media:/media:ro \
  -v "$PWD/backups:/backup" \
  alpine:3.22 \
  tar czf "/backup/media-$(date +%Y%m%dT%H%M%S).tgz" -C /media local
```

卷名默认是 `commune_media`；可用 `docker volume ls` 确认。

### 恢复

先停止 app，避免恢复期间继续写入：

```sh
docker compose stop app

docker compose exec -T postgres dropdb -U commune --if-exists commune
docker compose exec -T postgres createdb -U commune commune
cat backups/commune-YYYYMMDDTHHMMSS.dump \
  | docker compose exec -T postgres pg_restore -U commune -d commune --clean --if-exists

docker run --rm \
  -v commune_media:/media \
  -v "$PWD/backups:/backup" \
  alpine:3.22 \
  sh -c 'rm -rf /media/local && tar xzf /backup/media-YYYYMMDDTHHMMSS.tgz -C /media'

docker compose start app
```

如果恢复后的媒体属主不是 `10001:10001`，直接修正卷：

```sh
docker run --rm -v commune_media:/media alpine:3.22 \
  chown -R 10001:10001 /media
```

## 验证

第一次验证前先按“反向代理与自签证书”导出 `certs/commune-root.crt`。

```sh
docker compose config --quiet
docker compose build
docker compose up -d
docker compose ps

# 直接检查应用
curl -i -H 'Host: forum.example' http://127.0.0.1:8080/health/live
curl -i -H 'Host: forum.example' http://127.0.0.1:8080/health/ready

# 通过 Caddy + 自签证书检查 HTTPS
curl --cacert certs/commune-root.crt https://localhost/health/live
curl --cacert certs/commune-root.crt https://localhost/health/ready
curl --cacert certs/commune-root.crt \
  --resolve forum.example:443:127.0.0.1 \
  https://forum.example/health/ready

# 前端 SPA 与静态资源
curl --cacert certs/commune-root.crt https://localhost/
curl --cacert certs/commune-root.crt https://localhost/assets/index-<hash>.js
curl --cacert certs/commune-root.crt \
  https://localhost/assets/i18n/messages.en-US.<hash>.json

# 缺失的 hashed asset 必须 404，不能回退 SPA
curl --cacert certs/commune-root.crt -o /dev/null -w '%{http_code}\n' \
  https://localhost/assets/i18n/missing.json
```

前端资源文件名以 `frontend/dist/assets` 下的实际哈希为准。HTTPS 健康端点应
返回 `204`。未知 Host 仍应返回 `404`：

```sh
curl -i -H 'Host: unknown.example' http://127.0.0.1:8080/health/live
```

## 故障排查

- `app` 的 healthcheck 返回 404：Host 头不是配置中的站点。直接 curl 时手动
  加 `-H 'Host: <origin-host>'`。
- `migrate` 失败：查看 `docker compose logs migrate`；检查数据库 secret 是否
  有末尾换行。
- `app` 反复重启：查看 `docker compose logs app`，通常是配置校验失败。
- 媒体写入权限错误：确认 `commune_media` 卷是由当前镜像初始化的；绑定目录
  需要手动 `chown -R 10001:10001`。
- BuildKit 报 named context 错误：检查 `MYGO_CONTEXT` 是否指向包含
  `go.mod` 的 MyGO 根目录，并确认 `DOCKER_BUILDKIT=1`。
- Caddy 无法绑定 443：`ss -ltn | grep :443` 查看占用；停止宿主机上的其他
  Caddy/Nginx。若改端口，需同步 `deploy/Caddyfile` 和站点 alias。
- 浏览器证书警告：信任 `certs/commune-root.crt`，或临时跳过警告；`curl`
  使用 `--cacert certs/commune-root.crt`。
- `forum.example` 无法解析：在 `/etc/hosts` 添加
  `127.0.0.1 forum.example`，或使用 `curl --resolve`。
- `trusted_proxies` 不匹配：应用会忽略 `X-Forwarded-Host`/`X-Forwarded-For`；
  确认 `frontend` 子网是 `172.28.0.0/24` 且配置一致。
- 查看 Caddy 证书签发日志：`docker compose logs caddy`。
- `frontend/dist` 缺失：Caddy 挂载失败；先在 `frontend` 下执行
  `ELM_HOME=/tmp/commune-elm-home npm run build`。
- `/assets/*` 返回 404：检查构建产物中的哈希文件名；缺失资源不会回退 SPA。
- `/communities/:id` 的 HTML 与 AP 结果不同：Caddy 按 `Accept` 协商；
  local-only 社区没有 ActivityPub 表示，AP 请求返回 404。
- `docker compose down -v` 会删除 `commune_pgdata`、`commune_media` 和
  `commune_caddy_data`，不要在生产环境误用。

## 反向代理与自签证书

Compose 已经包含 Caddy：

- `caddy` 服务监听容器内 `443`，Compose 映射到宿主机 `443`。
- 站点地址是 `https://forum.example` 和 `https://localhost`。
- `local_certs` 让 Caddy 使用本地 CA 自动签发自签证书，证书保存在
  `caddy_data` 卷。
- `frontend` 网络固定为 `172.28.0.0/24`；应用只信任该网段内的代理。
- 应用自身仍然只发布到 `127.0.0.1:8080`，用于调试和健康检查。

Caddy 同时从 `frontend/dist` 提供前端：

- `/assets/*` 直接返回静态文件，缺失返回 `404`，并使用 immutable 缓存。
- `/api/*`、`/health/*`、WebFinger、用户/对象/活动/上下文/联邦媒体/collections
  反代到 `app:8080`。
- `/communities/*` 按 `Accept` 内容协商：ActivityPub 媒体类型走后端，HTML
  走 SPA。
- 其他路径使用 SPA fallback `/index.html`，`index.html` 使用 no-cache。

### 导出并信任根证书

```sh
mkdir -p certs
docker compose cp \
  caddy:/data/caddy/pki/authorities/local/root.crt \
  certs/commune-root.crt
```

`certs/` 已在 `.gitignore` 中。根证书是自签 CA；对应的私钥保存在
`caddy_data` 卷内，不要删除该卷，除非接受重新签发。

`curl` 使用：

```sh
curl --cacert certs/commune-root.crt https://localhost/health/ready
curl --cacert certs/commune-root.crt \
  --resolve forum.example:443:127.0.0.1 \
  https://forum.example/health/ready
```

浏览器：

- `https://localhost` 可直接访问，但需要信任根证书或跳过证书警告。
- `https://forum.example` 需要把 `forum.example` 解析到 `127.0.0.1`
  （`/etc/hosts` 或内网 DNS）。
- 浏览器登录使用 `https://localhost` 或 `https://forum.example`，二者都已
  配置为同一站点的 origin/alias。

### 换成真实证书

如果使用受信任证书，把 `deploy/Caddyfile` 中的 `local_certs` 移除，并改为：

```caddyfile
https://forum.example {
  tls /etc/caddy/certs/fullchain.pem /etc/caddy/certs/privkey.pem
  reverse_proxy app:8080
}
```

然后把证书目录挂载到 `/etc/caddy/certs` 并重建 `caddy`。也可以保留 Caddy
的 ACME 自动签发，但需要公网可解析域名和 80/443 入站。

### 保留 localhost 别名

`deploy/commune.json` 的 `sites[0].aliases` 包含 `localhost`。如果上线时只
使用 `forum.example`，可以移除该别名，并同步修改 `deploy/Caddyfile`。
