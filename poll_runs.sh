#!/bin/bash
# Polls the 6d6d/tailscale-peer GitHub Actions run and prints per-job progress.
# Usage: poll_runs.sh [max_iterations]
TOKEN=$(awk '/oauth_token:/{print $2; exit}' "$HOME/.config/gh/hosts.yml")
REPO=6d6d/tailscale-peer
MAX=${1:-24}
H=(-H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json")

for i in $(seq 1 "$MAX"); do
  echo "--- poll $i/$(date -u +%H:%M:%S) ---"
  curl -sS "${H[@]}" "https://api.github.com/repos/$REPO/actions/runs?per_page=3" -o /tmp/runs.json
  RUN=$(python3 -c "
import json
d=json.load(open('/tmp/runs.json'))
rs=d.get('workflow_runs',[])
print(rs[0]['id'] if rs else '')
")
  if [ -z "$RUN" ]; then echo "no runs yet"; sleep 20; continue; fi
  curl -sS "${H[@]}" "https://api.github.com/repos/$REPO/actions/runs/$RUN/jobs" -o /tmp/jobs.json
  STATE=$(python3 - <<'PY'
import json
d=json.load(open('/tmp/runs.json'))
r=d['workflow_runs'][0]
print(f"run {r['id']} {r['name']} [{r['status']}/{r['conclusion']}] {r['html_url']}")
j=json.load(open('/tmp/jobs.json'))
allc=True
for job in j.get('jobs',[]):
    mark=''
    for s in job.get('steps',[]):
        if s.get('conclusion') in ('failure','cancelled'):
            mark=f"  <-- step failed: {s['name']}"
    print(f"   {job['name']}: {job['status']}/{job['conclusion']} started={job.get('started_at')}{mark}")
    if job['status'] != 'completed':
        allc=False
print('ALLDONE' if allc else 'RUNNING')
PY
)
  echo "$STATE"
  case "$STATE" in *ALLDONE*) echo "=== 全部作业完成 ==="; break;; esac
  sleep 30
done
