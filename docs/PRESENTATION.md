# Presentation guide — Silent Spring demo

A suggested 10–12 minute flow. Live-demo commands are copy-paste ready.
Keep a terminal in `silent-spring-demo/` and, optionally, the dashboard open.

---

## Slide 1 — Title & hook
- **Silent Spring: Prototype Pollution → RCE in Node.js** (USENIX Security '23).
- Hook: *"A single line of `merge(config, userInput)` can hand an attacker a shell —
  even when the developer did everything the security guides told them to do."*

## Slide 2 — Background: what is prototype pollution
- Every `{}` inherits from `Object.prototype`. Change the prototype → change *every*
  object at once.
- Live micro-demo (30 s):
  ```bash
  ./vendor/node-v16.13.1-darwin-arm64/bin/node -e 'const o={}; ({}).__proto__.x=42; console.log(o.x)'
  # -> 42   (o.x was never set)
  ```
- Prior work: this = DoS. **This paper: this = RCE.**

## Slide 3 — The idea: POIV = a 2-stage gadget chain
- Stage 1 **injection sink**: attacker data reaches `obj[proto][prop]=value` → pollutes prototype.
- Stage 2 **gadget**: innocent code *reads* a property it never set; the read falls
  through to the polluted value and flows into an **attack sink** (e.g. `spawn`).
- Analogy: *load the gun (stage 1), let a gadget pull the trigger (stage 2).*

## Slide 4 — Our target app
- "SysMon" dashboard (`src/server.js`), ~90 lines. Two endpoints:
  - `POST /api/settings` → `_.defaultsDeep(config, req.body)`  ← injection sink
  - `GET /api/ping?host=…` → `spawn('ping', ['-c','1', host])` ← **argv array = the *safe* pattern**
- Emphasize: the ping endpoint is written the way secure-coding guides recommend.

## Slide 5 — LIVE DEMO (the core moment)
Run the standalone probe first (fast, unambiguous):
```bash
npm run probe        # on system node -> MITIGATED
./vendor/node-v16.13.1-darwin-arm64/bin/node scripts/probe-gadget.js   # -> VULNERABLE
```
Then the full HTTP attack:
```bash
npm run demo
```
Walk through `results/exploit-node16.txt` on screen:
1. **Step 2**: `?host=127.0.0.1; id` with no pollution → `id` does NOT run (safe).
2. **Step 3**: POST `{"constructor":{"prototype":{"shell":true}}}` → prototype polluted.
3. **Step 4**: same ping URL → output now contains `uid=501(...)`. **RCE.**
- Show `results/RCE_PROOF.txt` exists — a file the injected command created.

## Slide 6 — Why does the "safe" spawn become unsafe?
- Node's internal `normalizeSpawnArgs` does roughly `if (options.shell) …`.
- The app never set `shell`, but the *options object inherits* the polluted `shell=true`.
- Result: `spawn` re-runs the command through `/bin/sh -c "ping … ; id"`.
- This is **gadget G1** — one of 11 *universal* gadgets that ship inside Node.js.

## Slide 7 — The paper's real-world results
- 11 universal gadgets in Node core; 8 RCEs in **NPM CLI, Parse Server, Rocket.Chat**.
- NPM CLI: pollution during `npm install` + git's `GIT_SSH_COMMAND` env gadget → RCE
  (CVE-2022-24760).
- Detection philosophy: **embrace false positives**, optimize for recall (~93–97%),
  because one true positive against a big app is worth it.

## Slide 8 — Defenses & our second result
- `Object.freeze(Object.prototype)`, null-prototype configs, reject `__proto__`/
  `constructor`/`prototype` keys, debloat unused code.
- **We reproduced the runtime fix first-hand:** identical exploit is
  **VULNERABLE on Node 16.13.1** but **MITIGATED on Node 24** (null-prototype default
  spawn options). Show `results/SUMMARY.md` result matrix.
- Caveat: *application-level* gadgets (`options.cmd || default`) still work on every
  Node version — patching the runtime is necessary but not sufficient.

## Slide 9 — Takeaways
1. Prototype pollution is not just DoS — it is an RCE primitive.
2. "Safe" APIs can be de-fanged by state an attacker controls elsewhere in the process.
3. Injection sink and gadget are far apart → needs whole-program (taint) analysis to find.
4. Defense in depth: validate inputs, freeze the prototype, patch runtimes, remove dead code.

---

### Assets to show
- `results/SUMMARY.md` — the two-runtime result matrix.
- `results/exploit-node16.txt` — annotated attack transcript (the `uid=` line is the money shot).
- `results/probe-node16.txt` vs `results/probe-system.txt` — vulnerable vs mitigated.
- The dashboard at `http://127.0.0.1:3000` if you want a visual.
