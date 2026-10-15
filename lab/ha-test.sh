#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
STACK=corpmail
NODES="node-01 node-02 node-03"

on() { n=$1; shift; docker exec "$n" docker "$@"; }
gl() { n=$1; shift; docker exec "$n" gluster --mode=script "$@"; }
step() { printf '\n== %s\n' "$*"; }

index() { echo $((${1#node-0} - 1)); }

smoke() {
  i=$(index "$1")
  MAIL_HOST=127.0.0.1 SMTP_PORT=$((2525 + i)) SUBMISSION_PORT=$((5587 + i)) IMAP_PORT=$((1143 + i)) python3 scripts/smoke_test.py
}

placed() {
  on "$1" service ps "${STACK}_$2" --filter desired-state=running --format '{{.Node}} {{.CurrentState}}' \
    | awk '$2 == "Running" { print $1 }'
}

wait_for() {
  deadline=$(( $(date +%s) + $1 )); shift
  until "$@" 2>/dev/null; do
    [ "$(date +%s)" -lt "$deadline" ] || { echo "timeout: $*"; exit 1; }
    sleep 3
  done
}

start_node() {
  until [ "$(docker inspect -f '{{.State.Running}}' "$1")" = true ]; do
    docker start "$1" >/dev/null || true
    sleep 10
  done
  until on "$1" info >/dev/null 2>&1; do sleep 2; done
}

dovecot_on() { [ "$(placed "$1" dovecot)" = "$2" ]; }
dovecot_up() { [ -n "$(placed "$1" dovecot)" ]; }
dovecot_not_on() { p=$(placed "$1" dovecot); [ -n "$p" ] && [ "$p" != "$2" ]; }
managers_ready() {
  [ "$(on "$1" node ls --format '{{.Status}} {{.ManagerStatus}}' | grep -cE '^Ready (Leader|Reachable)')" -eq "$2" ]
}
healed() { gl "$1" volume heal corpmail info | awk '/^Number of entries:/ { s += $4 } END { exit (s > 0) }'; }
globals_on() { for s in postfix traefik; do placed "$1" "$s" | grep -qx "$2" || return 1; done; }

task_exec() { docker exec "$1" sh -c "docker exec \$(docker ps -q -f name=${STACK}_$2 | head -1) $3"; }
delivered() { task_exec "$1" dovecot "doveadm search -u dima@corp.local subject $2" | grep -q .; }

send_external() {
  i=$(index "$1")
  python3 - "$((2525 + i))" "$2" <<'PY'
import smtplib, sys, time
port, subject = int(sys.argv[1]), sys.argv[2]
message = f"From: partner@external.test\r\nTo: dima@corp.local\r\nSubject: {subject}\r\n\r\nsent while two nodes are down\r\n"
deadline = time.time() + 420
while True:
    try:
        with smtplib.SMTP("127.0.0.1", port, "mx.external.test", timeout=30) as smtp:
            smtp.sendmail("partner@external.test", ["dima@corp.local"], message)
        print("accepted")
        break
    except (smtplib.SMTPException, OSError) as error:
        if time.time() > deadline:
            raise
        print(f"retry: {error}")
        time.sleep(30)
PY
}

step "1. smoke test on the full cluster"
smoke node-01

victim=$(placed node-01 dovecot)
for alive in $NODES; do [ "$alive" = "$victim" ] || break; done
step "2. stop $victim (runs dovecot), check from $alive"
start=$(date +%s)
docker stop "$victim" >/dev/null
wait_for 300 dovecot_not_on "$alive" "$victim"
echo "dovecot is back on $(placed "$alive" dovecot) after $(( $(date +%s) - start )) s"
on "$alive" node ls
smoke "$alive"

step "3. return $victim"
start_node "$victim"
wait_for 300 managers_ready "$alive" 3
wait_for 600 healed "$alive"
wait_for 300 globals_on "$alive" "$victim"
on "$alive" node ls

holder=$(placed "$alive" dovecot)
for survivor in $NODES; do [ "$survivor" = "$holder" ] || break; done
dead=""
for n in $NODES; do [ "$n" = "$survivor" ] || dead="$dead $n"; done
subject="ha-test-$(date +%s)"
step "4. stop$dead, only $survivor is left"
# shellcheck disable=SC2086
docker stop $dead >/dev/null
sleep 20
send_external "$survivor" "$subject"
task_exec "$survivor" postfix "postqueue -p" | grep -q dima@corp.local
echo "message is queued on $survivor"

step "5. recover.sh single on $survivor"
docker exec -i "$survivor" sh -s single < scripts/recover.sh
wait_for 300 dovecot_on "$survivor" "$survivor"
smoke "$survivor"
wait_for 300 delivered "$survivor" "$subject"
echo "queued message delivered"

step "6. return$dead and rejoin"
addr=$(on "$survivor" info --format '{{.Swarm.NodeAddr}}')
token=$(on "$survivor" swarm join-token -q manager)
for n in $dead; do
  start_node "$n"
  docker exec -i "$n" sh -s join "$addr" "$token" < scripts/recover.sh
done
docker exec -i "$survivor" sh -s finish < scripts/recover.sh
docker restart "$survivor" >/dev/null
start_node "$survivor"
wait_for 300 managers_ready "$survivor" 3
wait_for 600 healed "$survivor"
wait_for 300 globals_on "$survivor" "$survivor"
wait_for 300 dovecot_up "$survivor"
smoke "$survivor"

step "ha-test passed"
