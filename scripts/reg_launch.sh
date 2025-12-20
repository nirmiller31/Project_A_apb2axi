# run command: bash scripts/reg_launch.sh (from Project), dont forget to clean regression!!!

#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# ---------------------------
# User inputs (edit defaults)
# ---------------------------
UVM_TESTNAME="${UVM_TESTNAME:-apb2axi_test}"

# Seeds: either provide SEEDS="1 2 3" or SEED_START/SEED_COUNT
SEEDS="${SEEDS:-}"
SEED_START="${SEED_START:-123}"
SEED_COUNT="${SEED_COUNT:-10}"

# Parallelism
JOBS="${JOBS:-1}"

# Where simv lives (or build step below can create it)
SIMV="${SIMV:-$PROJ_DIR/simv}"

# Output dir
OUTROOT="${OUTROOT:-out/regress_${UVM_TESTNAME}_$(date +%Y%m%d_%H%M%S)}"

# ---------------------------
# Define MODES (name + flags)
# Edit these to match your project
# ---------------------------
# Each mode is: MODE_NAME|EXTRA_PLUSARGS
MODES=(
  "read_regular_outstanding|+APB2AXI_SEQ=READ"
  "read_linear_outstanding|+APB2AXI_SEQ=READ +LINEAR_OUTSTANDING"
  "read_extreme_outstanding|+APB2AXI_SEQ=READ +EXTREME_OUTSTANDING"
  "write_regular_outstanding|+APB2AXI_SEQ=WRITE"
  "write_linear_outstanding|+APB2AXI_SEQ=WRITE +LINEAR_OUTSTANDING"
  "write_extreme_outstanding|+APB2AXI_SEQ=WRITE +EXTREME_OUTSTANDING"
)

# ---------------------------
# Helper: build seeds list
# ---------------------------
if [[ -z "$SEEDS" ]]; then
  SEEDS=""
  for ((s=SEED_START; s<SEED_START+SEED_COUNT; s++)); do
    SEEDS+="$s "
  done
fi

mkdir -p "$OUTROOT"/{runs,logs}
STATUS_CSV="$OUTROOT/status.csv"
SUMMARY_TXT="$OUTROOT/summary.txt"
SUMMARY_HTML="$OUTROOT/summary.html"

echo "mode,seed,status,dir,log" > "$STATUS_CSV"
: > "$SUMMARY_TXT"

# ---------------------------
# Optional build step (uncomment if you want)
# ---------------------------
# if [[ ! -x "$SIMV" ]]; then
#   echo "[BUILD] simv not found. Building..."
#   vcs -full64 -sverilog -timescale=1ns/1ps -l "$OUTROOT/comp.log" \
#       -debug_access+all -kdb -f filelist.f
# fi

# ---------------------------
# Run one job
# ---------------------------
run_one() {
  local mode_name="$1"
  local mode_args="$2"
  local seed="$3"

  local rundir="$OUTROOT/runs/${mode_name}/seed_${seed}"
  local logfile="$rundir/sim.log"
  mkdir -p "$rundir"

  # Mark running
  echo "${mode_name},${seed},RUNNING,${rundir},${logfile}" >> "$STATUS_CSV"

  # Run
  (
     cd "$rundir"
     echo "[CMD] $SIMV +UVM_TESTNAME=$UVM_TESTNAME +ntb_random_seed=$seed -l sim.log $mode_args" > cmdline.txt
     "$SIMV" \
     +UVM_TESTNAME="$UVM_TESTNAME" \
     +ntb_random_seed="$seed" \
     -l sim.log \
     $mode_args
  ) || true

  # Decide PASS/FAIL (tweak patterns to your style)
  status="PASS"

  # If log missing => FAIL
  if [[ ! -f "$logfile" ]]; then
    status="FAIL"
  else
  # Mark FAIL if UVM_ERROR/FATAL counts nonzero
    if grep -Eq "UVM_ERROR\s*:\s*[1-9]|UVM_FATAL\s*:\s*[1-9]" "$logfile"; then
      status="FAIL"
    fi
  fi

  echo "[$status] mode=$mode_name seed=$seed  log=$logfile" >> "$SUMMARY_TXT"

  # Append final status row
  echo "${mode_name},${seed},${status},${rundir},${logfile}" >> "$STATUS_CSV"
}

export -f run_one
export UVM_TESTNAME SIMV OUTROOT STATUS_CSV SUMMARY_TXT

# ---------------------------
# Launch all (parallel)
# ---------------------------
echo "[INFO] OUTROOT=$OUTROOT"
echo "[INFO] TEST=$UVM_TESTNAME"
echo "[INFO] MODES=${#MODES[@]}  SEEDS=($SEEDS)"
echo

jobs_file="$OUTROOT/jobs.list"
: > "$jobs_file"

# Encode/decode helper (no external deps beyond python3)
b64enc() { python3 - <<'PY' "$1"
import base64, sys
print(base64.b64encode(sys.argv[1].encode()).decode())
PY
}

b64dec() { python3 - <<'PY' "$1"
import base64, sys
print(base64.b64decode(sys.argv[1]).decode())
PY
}

# Build jobs as 3 *safe* tokens: mode_name seed mode_args_b64
for m in "${MODES[@]}"; do
  mode_name="${m%%|*}"
  mode_args="${m#*|}"
  mode_b64="$(b64enc "$mode_args")"
  for seed in $SEEDS; do
    printf "%s %s %s\n" "$mode_name" "$seed" "$mode_b64" >> "$jobs_file"
  done
done

worker() {
  local mode_name="$1"
  local seed="$2"
  local mode_b64="$3"
  local mode_args
  mode_args="$(b64dec "$mode_b64")"
  run_one "$mode_name" "$mode_args" "$seed"
}

export -f worker b64dec

cat "$jobs_file" | xargs -P "$JOBS" -n 3 bash -lc 'worker "$0" "$1" "$2"'

# ---------------------------
# Generate HTML summary
# ---------------------------
python3 - <<'PY'
import csv, html, os, sys
outroot = os.environ.get("OUTROOT")
status_csv = os.path.join(outroot, "status.csv")
summary_html = os.path.join(outroot, "summary.html")

rows=[]
with open(status_csv, newline="") as f:
    r=csv.reader(f)
    header=next(r)
    for row in r:
        rows.append(row)

# Keep last status per (mode,seed)
last={}
for mode,seed,status,dir_,log in rows:
    last[(mode,seed)] = (status,dir_,log)

items=[(k[0], int(k[1]), *v) for k,v in last.items() if v[0] in ("PASS","FAIL","RUNNING")]
items.sort(key=lambda x:(x[0], x[1]))

def color(st):
    return {"PASS":"#b6f2c2","FAIL":"#ffb3b3","RUNNING":"#ffe8a6"}.get(st,"#eee")

with open(summary_html,"w") as f:
    f.write("<html><head><meta charset='utf-8'><title>Regression Summary</title></head><body>")
    f.write(f"<h2>Regression Summary</h2><p>OUT: {html.escape(outroot)}</p>")
    f.write("<table border='1' cellpadding='6' cellspacing='0'>")
    f.write("<tr><th>Mode</th><th>Seed</th><th>Status</th><th>Log</th></tr>")
    for mode,seed,status,dir_,log in items:
        rel = os.path.relpath(log, outroot)
        f.write(f"<tr style='background:{color(status)}'>")
        f.write(f"<td>{html.escape(mode)}</td><td>{seed}</td><td><b>{status}</b></td>")
        f.write(f"<td><a href='{html.escape(rel)}'>{html.escape(rel)}</a></td>")
        f.write("</tr>")
    f.write("</table></body></html>")
print("Wrote:", summary_html)
PY

echo
echo "[DONE] Text summary : $SUMMARY_TXT"
echo "[DONE] HTML summary : $SUMMARY_HTML"
echo "[TIP] Serve the report locally:"
echo "      cd '$OUTROOT' && python3 -m http.server 8000"
echo "      then open: http://localhost:8000/summary.html"