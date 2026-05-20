#!/usr/bin/env bash
# ----------------------------------------------------------------------
# Background "normal traffic" generator for the demo Bookinfo cluster.
#
# Mirrors how demo.sh injects requests — `kubectl exec` into the
# productpage pod and hit in-cluster service DNS (details, reviews,
# ratings) over HTTP. This works regardless of whether Istio's ingress
# LoadBalancer has an external IP, since we never leave the cluster.
#
# Usage:
#   ./bg_traffic.sh start      start (auto-discovers productpage pod)
#   ./bg_traffic.sh stop       stop the running daemon
#   ./bg_traffic.sh status     is it running?
#   ./bg_traffic.sh restart    stop + start
#   ./bg_traffic.sh logs       tail the log file
#
# Tunables (env vars):
#   BG_NAMESPACE   k8s namespace for the productpage pod (default: default)
#   BG_MIN_DELAY   min seconds between requests (default: 0.4)
#   BG_MAX_DELAY   max seconds between requests (default: 2.5)
#
# State lives in /tmp:
#   /tmp/zentrion-bg-traffic.pid
#   /tmp/zentrion-bg-traffic.log
# ----------------------------------------------------------------------
set -euo pipefail

PID_FILE="/tmp/zentrion-bg-traffic.pid"
LOG_FILE="/tmp/zentrion-bg-traffic.log"

NAMESPACE="${BG_NAMESPACE:-default}"
MIN_DELAY="${BG_MIN_DELAY:-0.4}"
MAX_DELAY="${BG_MAX_DELAY:-2.5}"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
DIM="\033[2m"
RESET="\033[0m"

is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

find_productpage_pod() {
  kubectl get pods -n "$NAMESPACE" -l app=productpage \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

cmd_start() {
  if is_running; then
    echo -e "${YELLOW}Already running (PID $(cat "$PID_FILE")).${RESET} Use 'stop' or 'restart'."
    exit 0
  fi

  for tool in kubectl python3; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo -e "${RED}Required tool not found: ${tool}${RESET}" >&2
      exit 1
    }
  done

  local pod
  pod="$(find_productpage_pod)"
  if [[ -z "$pod" ]]; then
    echo -e "${RED}No Running productpage pod found in namespace '${NAMESPACE}'.${RESET}" >&2
    echo -e "  Tip: ${DIM}kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/platform/kube/bookinfo.yaml${RESET}"
    exit 1
  fi

  echo -e "${GREEN}Starting background traffic${RESET} via ${NAMESPACE}/${pod}"
  : > "$LOG_FILE"

  # The traffic loop lives inside the productpage pod as a python -c
  # script piped over `kubectl exec -i`. Stdlib only (urllib.request)
  # so we don't depend on `requests` being installed in the image.
  local generator_py
  generator_py="$(cat <<'PY'
import os, random, sys, threading, time
import urllib.request

MIN_DELAY = float(os.environ.get("MIN_DELAY", "0.4"))
MAX_DELAY = float(os.environ.get("MAX_DELAY", "2.5"))

# Watchdog: if the parent (`kubectl exec`) goes away, stdin closes. Read
# it in a daemon thread and exit hard the moment that happens. Without
# this, killing the local script orphans the in-pod loop indefinitely.
def _stdin_watchdog():
    try:
        while sys.stdin.read(1):
            pass
    except Exception:
        pass
    os._exit(0)

threading.Thread(target=_stdin_watchdog, daemon=True).start()

# Hit the same in-cluster services demo.sh uses. All Bookinfo pods
# share a docker network through Istio, so cluster DNS resolves these.
ENDPOINTS = [
    "http://details:9080/details/0",
    "http://details:9080/details/1",
    "http://details:9080/details/2",
    "http://reviews:9080/reviews/0",
    "http://reviews:9080/reviews/1",
    "http://reviews:9080/reviews/2",
    "http://ratings:9080/ratings/0",
    "http://ratings:9080/ratings/1",
    "http://productpage:9080/productpage",
    "http://productpage:9080/api/v1/products",
    "http://productpage:9080/api/v1/products/0",
]

AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    "curl/8.4.0",
]

sent = 0
ok_count = 0
err_count = 0
last_report = time.time()

while True:
    url = random.choice(ENDPOINTS)
    req = urllib.request.Request(url, headers={"User-Agent": random.choice(AGENTS)})
    try:
        with urllib.request.urlopen(req, timeout=3) as r:
            r.read(64)  # consume so Envoy logs a complete request
            sent += 1
            ok_count += 1
    except Exception as exc:
        sent += 1
        err_count += 1
        # Don't spam the log; only print exceptions every 20 errors.
        if err_count % 20 == 1:
            print(f"[bg-traffic] {url} -> {exc.__class__.__name__}: {exc}", flush=True)

    now = time.time()
    if now - last_report > 30:
        print(f"[bg-traffic] sent={sent} ok={ok_count} err={err_count}", flush=True)
        last_report = now

    time.sleep(random.uniform(MIN_DELAY, MAX_DELAY))
PY
)"

  # `nohup … &` detaches from terminal; setsid puts the child in its
  # own process group so 'stop' can kill the whole tree cleanly.
  #
  # `sleep infinity | kubectl exec -i` keeps the kubectl exec stdin open
  # for the lifetime of the wrapper. Without this, nohup redirects stdin
  # from /dev/null → kubectl forwards immediate EOF to the pod →
  # the in-pod Python stdin-watchdog fires and exits ~instantly.
  # When the wrapper process group is killed (cmd_stop or terminal close),
  # the `sleep` dies too, the pipe closes, kubectl exec sees EOF, and the
  # in-pod watchdog cleanly tears down the loop.
  nohup setsid bash -c "
    echo \"[bg-traffic] target pod: ${NAMESPACE}/${pod}\"
    echo \"[bg-traffic] delay: ${MIN_DELAY}-${MAX_DELAY}s per request\"
    sleep infinity | \
      kubectl exec -i -n '${NAMESPACE}' '${pod}' -- \
      env MIN_DELAY='${MIN_DELAY}' MAX_DELAY='${MAX_DELAY}' \
      python3 -u -c '$(printf '%s' "$generator_py" | sed "s/'/'\\\\''/g")'
  " >>"$LOG_FILE" 2>&1 &

  local pid=$!
  disown "$pid" 2>/dev/null || true
  echo "$pid" > "$PID_FILE"

  sleep 0.5
  if is_running; then
    echo -e "  PID:  ${pid}"
    echo -e "  Log:  ${LOG_FILE}"
    echo -e "  Stop: ${DIM}$0 stop${RESET}"
  else
    echo -e "${RED}Failed to start — check ${LOG_FILE}.${RESET}" >&2
    rm -f "$PID_FILE"
    exit 1
  fi
}

cmd_stop() {
  local was_running=0
  if is_running; then
    was_running=1
    local pid
    pid="$(cat "$PID_FILE")"
    echo -e "${YELLOW}Stopping${RESET} (PID ${pid})..."

    # Kill the whole process group (kubectl exec child included). setsid
    # gave us our own pgid that matches $pid.
    kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    for _ in {1..10}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 -- -"$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    fi
  fi

  # Belt-and-suspenders: any leftover `kubectl exec` for our pod.
  pkill -f "kubectl exec.* -n ${NAMESPACE} .*python3 -u -c" 2>/dev/null || true

  # And sweep any orphaned generator processes inside the pod itself.
  # The stdin-watchdog in the generator should exit them on its own once
  # kubectl exec is gone, but this is a safety net for any that linger.
  local pod
  pod="$(find_productpage_pod 2>/dev/null || true)"
  if [[ -n "$pod" ]]; then
    kubectl exec -n "$NAMESPACE" "$pod" -c productpage -- python3 -c '
import os, glob
for d in glob.glob("/proc/[0-9]*"):
    try: pid = int(d.rsplit("/", 1)[1])
    except ValueError: continue
    if pid == os.getpid() or pid == 1: continue
    try:
        with open(f"{d}/cmdline", "rb") as f:
            cmd = f.read().decode(errors="ignore")
    except FileNotFoundError:
        continue
    if "urllib.request" in cmd and "MIN_DELAY" in cmd:
        try: os.kill(pid, 9)
        except ProcessLookupError: pass
' >/dev/null 2>&1 || true
  fi

  rm -f "$PID_FILE"
  if [[ "$was_running" == "1" ]]; then
    echo -e "${GREEN}Stopped.${RESET}"
  else
    echo "Not running (cleanup pass complete)."
  fi
}

cmd_status() {
  if is_running; then
    local pid lines
    pid="$(cat "$PID_FILE")"
    lines=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
    echo -e "${GREEN}Running${RESET} (PID ${pid})"
    echo -e "  Log lines: ${lines}"
    echo -e "  Log:       ${LOG_FILE}"
    if [[ -s "$LOG_FILE" ]]; then
      echo -e "  Last line: $(tail -n 1 "$LOG_FILE")"
    fi
  else
    echo "Not running."
  fi
}

cmd_restart() {
  cmd_stop
  cmd_start
}

cmd_logs() {
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "No log file yet at $LOG_FILE."
    exit 0
  fi
  tail -f "$LOG_FILE"
}

case "${1:-}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  restart) cmd_restart ;;
  logs)    cmd_logs ;;
  *)
    echo "Usage: $0 {start|stop|status|restart|logs}"
    echo "Env: BG_NAMESPACE=default BG_MIN_DELAY=0.4 BG_MAX_DELAY=2.5"
    exit 2
    ;;
esac
