# Корпоративная почтовая система с высокой доступностью на Docker Swarm

Стек из открытых компонентов Mailcow (Postfix, Dovecot, Rspamd, ClamAV, Redis, MariaDB) с веб-почтой Roundcube и обратным прокси Traefik, развертываемый в кластер Docker Swarm одной командой.
Курсовая работа по дисциплине «Настройка и администрирование сервисного программного обеспечения», РТУ МИРЭА.

## Сервисы

| Сервис | Образ | Режим | Назначение |
|---|---|---|---|
| `traefik` | `traefik:v3.5` | 1 реплика, manager | вход HTTPS :443, маршрутизация веб-почты, Rspamd UI и дашборда |
| `roundcube` | `roundcube/roundcubemail:1.7.4-apache` | 2 реплики | веб-почта, сессии в MariaDB |
| `postfix` | собственный, `postfix/Dockerfile` | global (на каждом узле), порты 25 и 587 в режиме host | MTA: прием, отправка, SASL через Dovecot, milter Rspamd, доставка по LMTP |
| `dovecot` | собственный, `dovecot/Dockerfile` | 1 реплика, узел `mail=true` | IMAP 143/993, LMTP 24, аутентификация 12345, хранилище Maildir |
| `rspamd` | `rspamd/rspamd:4.2.1` | 2 реплики | антиспам, грейлистинг, антивирус через ClamAV |
| `redis` | `redis:7.4-alpine` | 1 реплика, узел `mail=true` | данные Rspamd (грейлистинг, история, Bayes) |
| `clamav` | `clamav/clamav-debian:1.4` | 1 реплика, worker | антивирусная проверка вложений |
| `mariadb` | `mariadb:11.8` | 1 реплика, узел `db=true` | база Roundcube |

Сети: `corpmail_frontend` (Traefik, Roundcube, Rspamd UI) и `corpmail_backend` (почтовые сервисы), обе overlay.
Пароли и ключи хранятся в секретах Swarm, конфигурации Rspamd и Roundcube - в configs Swarm; имена версионируются контрольной суммой, поэтому их изменение выкатывается обычным `deploy.sh`.

## Развертывание

Нужен кластер Docker Swarm (Docker Engine 24+), на узлах метки `db=true` и `mail=true`.

```sh
./scripts/make-secrets.sh              # secrets/, пароли пользователей в secrets/credentials.env
REGISTRY=registry.example:5000 TAG=v1 ./scripts/build.sh
REGISTRY=registry.example:5000 TAG=v1 ./scripts/deploy.sh
```

`deploy.sh` выполняет `docker stack deploy` и ждет, пока все сервисы выйдут на нужное число реплик и закончат обновление. Новая версия образов выкатывается тем же скриптом с другим `TAG`: Swarm обновляет задачи по одной и откатывает при сбое.

Проверка почтового потока:

```sh
MAIL_HOST=<адрес узла> python3 scripts/smoke_test.py
```

Тест отправляет письмо через submission 587 с SASL, принимает письмо извне на 25, читает их по IMAP и проверяет, что неверный пароль, open relay, спам GTUBE и вирус EICAR отклоняются, а входящее письмо получает заголовки Rspamd.
Первая попытка доставки от нового отправителя выводится как `[INFO]`: Rspamd может ответить 451 (грейлистинг), и тогда тест повторяет доставку каждые 30 секунд до `GREYLIST_WAIT` секунд (по умолчанию 420), как настоящий MTA. Грейлистинг зависит от оценки письма, поэтому в разных средах первая попытка бывает и 451, и 250.
EICAR прикладывается файлом `readme.txt`, а проверка требует слово `virus` в ответе: так отказ доказывает работу ClamAV, а не сумму баллов Rspamd за подозрительное расширение.
Пока Rspamd не видит ClamAV (базы загружаются 1-2 минуты после старта, имя сервиса переразрешается раз в 30 секунд), письма проходят без антивирусной проверки; тест в этом случае повторяет EICAR каждые 10 секунд до `ANTIVIRUS_WAIT` секунд (по умолчанию 90) и печатает пропущенные попытки как `[INFO]`. `CHECK_ANTIVIRUS=0` отключает проверку антивируса.

## Лабораторный кластер

`lab/lab.sh up` поднимает на одной машине три узла Docker-in-Docker (`manager-01`, `worker-01`, `worker-02`) и локальный registry, объединяет их в Swarm и расставляет метки. Порты manager-01 проброшены на `127.0.0.1`: 8443 (HTTPS), 2525 (SMTP), 5587 (submission), 1143 (IMAP), 1993 (IMAPS), 2375 (Docker API).

```sh
./lab/lab.sh up
docker context create corpmail-lab --docker host=tcp://127.0.0.1:2375
export DOCKER_CONTEXT=corpmail-lab
TAG=v1 ./scripts/build.sh && TAG=v1 ./scripts/deploy.sh
MAIL_HOST=127.0.0.1 SMTP_PORT=2525 SUBMISSION_PORT=5587 IMAP_PORT=1143 python3 scripts/smoke_test.py
./lab/lab.sh down
```

После возвращения отключенного узла Swarm не переносит задачи обратно сам; равномерное размещение восстанавливает `docker service update --force corpmail_roundcube corpmail_rspamd`.

Веб-почта: https://localhost:8443, Rspamd: https://rspamd.corp.local:8443, дашборд Traefik: https://traefik.corp.local:8443/dashboard/ (имена `*.corp.local` направить на 127.0.0.1).

## CI/CD

`.github/workflows/ci-cd.yml`:

1. `lint` - проверка stack-файла, hadolint, shellcheck, `postfix check` и `doveconf` на собранных образах.
2. `build` - сборка образов postfix и dovecot для amd64 и arm64, публикация в GitHub Container Registry с тегами коммита и `latest`.
3. `deploy-test` - Swarm на раннере, развертывание стека из опубликованных образов, smoke-тест.
4. `deploy` - rolling update на рабочем кластере по SSH; запускается, если заданы переменная `SWARM_MANAGER_HOST` и секреты `SWARM_SSH_KEY`, `STACK_SECRETS_TAR`.

## Ограничения

- Сертификаты TLS самоподписанные; Roundcube не проверяет сертификаты внутренних сервисов. В рабочей среде нужен внутренний CA или ACME в Traefik.
- Dovecot и MariaDB работают в одном экземпляре на помеченных узлах с локальными томами: отказ узла `mail=true` останавливает доступ к ящикам до его возвращения. Для переноса между узлами тома нужно вынести на общее хранилище (NFS, GlusterFS).
- Очередь Postfix хранится внутри контейнера; письма, ожидающие повторной отправки, теряются при пересоздании задачи.
