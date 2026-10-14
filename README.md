# Корпоративная почтовая система с высокой доступностью на Docker Swarm

Стек из открытых компонентов Mailcow (Postfix, Dovecot, Rspamd, ClamAV, Redis, MariaDB) с веб-почтой Roundcube и обратным прокси Traefik, развертываемый в кластер Docker Swarm одной командой.
Курсовая работа по дисциплине «Настройка и администрирование сервисного программного обеспечения», РТУ МИРЭА.

## Сервисы

| Сервис | Образ | Режим | Назначение |
|---|---|---|---|
| `traefik` | `traefik:v3.5` | global (на каждом узле-менеджере), порты 80 и 443 в режиме host | вход HTTPS :443, маршрутизация веб-почты, Rspamd UI и дашборда |
| `roundcube` | `roundcube/roundcubemail:1.7.4-apache` | 2 реплики | веб-почта, сессии в MariaDB |
| `postfix` | собственный, `postfix/Dockerfile` | global (на каждом узле), порты 25 и 587 в режиме host | MTA: прием, отправка, SASL через Dovecot, milter Rspamd, доставка по LMTP |
| `dovecot` | собственный, `dovecot/Dockerfile` | 1 реплика, любой узел, ящики на GlusterFS | IMAP 143/993, LMTP 24, аутентификация 12345, хранилище Maildir |
| `rspamd` | `rspamd/rspamd:4.2.1` | 2 реплики | антиспам, грейлистинг, антивирус через ClamAV |
| `redis` | `redis:7.4-alpine` | 1 реплика, любой узел, данные на GlusterFS | данные Rspamd (грейлистинг, история, Bayes) |
| `clamav` | `clamav/clamav-debian:1.4` | 1 реплика, любой узел | антивирусная проверка вложений |
| `mariadb` | `mariadb:11.8` | 1 реплика, любой узел, данные на GlusterFS | база Roundcube |

Сторонние образы в `stack.yml`, базовый `alpine` в Dockerfile, `debian:trixie-slim` и `docker:dind` в `lab/node/Dockerfile`, `registry` в `lab/lab.sh` и `rspamd` в `scripts/make-secrets.sh` закреплены по дайджесту мультиархитектурного индекса (`тег@sha256:...`): тег оставлен для читаемости, тянется образ по дайджесту. Новый дайджест: `docker buildx imagetools inspect <образ:тег>`, строка `Digest`.

Сети: `corpmail_frontend` (Traefik, Roundcube, Rspamd UI) и `corpmail_backend` (почтовые сервисы), обе overlay.
Пароли и ключи хранятся в секретах Swarm, конфигурации Rspamd и Roundcube - в configs Swarm; имена версионируются контрольной суммой, поэтому их изменение выкатывается обычным `deploy.sh`.

## Развертывание

Нужен кластер Docker Swarm (Docker Engine 24+) из трех узлов-менеджеров и том GlusterFS, смонтированный на каждом узле в `/mnt/gluster` (другой каталог задает `DATA_ROOT`), с каталогами `vmail`, `redis` и `mariadb` (раздел «Отказоустойчивость»).

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

`lab/lab.sh up` поднимает на одной машине три узла `node-01`, `node-02`, `node-03` и локальный registry. Узел - контейнер из образа `lab/node/Dockerfile` (Debian trixie, Docker CE 28.5, GlusterFS 11.1). Все три узла входят в Swarm менеджерами и образуют том GlusterFS `corpmail` с тремя копиями, смонтированный в `/mnt/gluster` на каждом узле. `lab.sh` работает с Docker Desktop: `DOCKER_CONTEXT=desktop-linux`.

Порты узлов на `127.0.0.1`:

| | node-01 | node-02 | node-03 |
|---|---|---|---|
| Docker API | 2375 | 2376 | 2377 |
| HTTP (перенаправление на HTTPS) | 8080 | 8081 | 8082 |
| HTTPS | 8443 | 8444 | 8445 |
| SMTP | 2525 | 2526 | 2527 |
| submission | 5587 | 5588 | 5589 |
| IMAP | 1143 | 1144 | 1145 |
| IMAPS | 1993 | 1994 | 1995 |

```sh
DOCKER_CONTEXT=desktop-linux ./lab/lab.sh up
docker context create corpmail-lab --docker host=tcp://127.0.0.1:2375
export DOCKER_CONTEXT=corpmail-lab
TAG=v1 ./scripts/build.sh && TAG=v1 ./scripts/deploy.sh
MAIL_HOST=127.0.0.1 SMTP_PORT=2525 SUBMISSION_PORT=5587 IMAP_PORT=1143 python3 scripts/smoke_test.py
DOCKER_CONTEXT=desktop-linux ./lab/lab.sh down
```

Когда `node-01` выключен, команды идут через другой узел: `DOCKER_HOST=tcp://127.0.0.1:2376 docker node ls`.

После возвращения отключенного узла Swarm не переносит задачи обратно сам; равномерное размещение восстанавливает `docker service update --force corpmail_roundcube corpmail_rspamd`.

Веб-почта: https://localhost:8443, Rspamd: https://rspamd.corp.local:8443, дашборд Traefik: https://traefik.corp.local:8443/dashboard/ (имена `*.corp.local` направить на 127.0.0.1).

## Отказоустойчивость

| Живо узлов | Прием входящей почты | Чтение и отправка пользователями | Веб-почта |
|---|---|---|---|
| 3 из 3 | да | да | да |
| 2 из 3 | да | да, автоматически | да |
| 1 из 3 | да, письма копятся в очереди Postfix | после `recover.sh single` | после восстановления |

Отказ одного узла. Два из трех менеджеров сохраняют большинство Raft, Swarm перезапускает задачи умершего узла на живых. Том GlusterFS доступен на запись, пока живы две копии из трех, поэтому Dovecot, Redis и MariaDB поднимаются на другом узле с теми же данными. Postfix и Traefik уже работают на каждом узле; на серверах отправители и клиенты переходят на другой адрес по нескольким записям MX и A. Вернувшийся узел Swarm принимает сам, GlusterFS досылает на его копию изменения (`gluster volume heal corpmail info` - 0 записей), письма из очереди Postfix этого узла доставляются после возврата.

Отказ двух узлов. У Swarm и GlusterFS нет большинства: контейнеры выжившего узла работают, новые задачи не запускаются, том GlusterFS недоступен (операции с файлами завершаются ошибкой `Transport endpoint is not connected`, так GlusterFS защищает копии от расхождения). Postfix выжившего узла принимает почту на порт 25 и держит ее в очереди (том `postfix-spool`). Полную работу возвращает `scripts/recover.sh`, который выполняется на узлах через `sh -s`:

```sh
docker exec -i node-01 sh -s single < scripts/recover.sh            # на сервере: ssh <узел> sh -s single < scripts/recover.sh
docker exec -i node-02 sh -s join <адрес> <токен> < scripts/recover.sh   # для каждого вернувшегося узла, команду печатает single
docker exec -i node-01 sh -s finish < scripts/recover.sh
```

`single` делает выживший узел кластером из одного менеджера (`docker swarm init --force-new-cluster`), снимает кворум GlusterFS, перезапускает Dovecot, MariaDB и Redis на этом узле и доставляет очередь Postfix. `join` возвращает узел в кластер менеджером. `finish` ждет окончания синхронизации GlusterFS, возвращает кворум, удаляет из списка старые записи узлов и выравнивает задачи.

`single` запускается только когда два других узла действительно выключены. Если они живы, но отрезаны сетью, копии данных разойдутся (split-brain).

`lab/ha-test.sh` прогоняет на стенде оба сценария: отказ узла с Dovecot, возврат, отказ двух узлов с письмом в очереди, `recover.sh` и возврат узлов; каждый этап проверяется smoke-тестом. Прогон длится 30-40 минут.

Перенос существующей установки: скопировать данные томов `corpmail_vmail`, `corpmail_redis-data`, `corpmail_mariadb-data` в `/mnt/gluster/vmail`, `redis`, `mariadb`, удалить старые тома на всех узлах (Docker не меняет параметры существующего тома и молча использовал бы старый) и выполнить `deploy.sh`.

На серверах дополнительно нужны: записи MX и A домена на адреса всех узлов, открытый у провайдера порт 25 (входящий и исходящий), PTR-записи, DKIM-подпись, межсетевой экран, открывающий между узлами 2377/TCP, 7946/TCP и UDP, 4789/UDP (Swarm), 24007-24008/TCP и 49152 и выше/TCP (GlusterFS).

## CI/CD

`.github/workflows/ci-cd.yml`:

1. `lint` - проверка stack-файла, hadolint, shellcheck, `postfix check` и `doveconf` на собранных образах.
2. `build` - сборка образов postfix и dovecot для amd64 и arm64, публикация в GitHub Container Registry с тегами коммита и `latest`.
3. `deploy-test` - Swarm на раннере, развертывание стека из опубликованных образов, smoke-тест.
4. `deploy` - rolling update на рабочем кластере по SSH; запускается на ветке `master`, если заданы переменные `SWARM_MANAGER_HOST`, `SWARM_MANAGER_USER` и секреты `SWARM_SSH_KEY`, `STACK_SECRETS_TAR` (архив `tar.gz` каталога `secrets/` в base64).

## Ограничения

- Сертификаты TLS самоподписанные; Roundcube не проверяет сертификаты внутренних сервисов. В рабочей среде нужен внутренний CA или ACME в Traefik.
- При отказе двух узлов из трех чтение почты возвращается вручную (`recover.sh`); автоматически пережить отказ двух узлов могут только пять.
- Письма в очереди Postfix умершего узла доставляются после его возвращения.
