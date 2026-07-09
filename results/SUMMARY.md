# Silent Spring demo — run summary

- Generated: 2026-07-09 17:25:30
- Paper: *Silent Spring: Prototype Pollution Leads to RCE in Node.js*, USENIX Security 2023
- Attack: Stage 1 prototype pollution (lodash `defaultsDeep`, v4.17.11) → Stage 2 universal gadget (`child_process.spawn` reading inherited `shell`)

## Result matrix

| Runtime | Universal gadget (probe) | End-to-end HTTP RCE |
|---|---|---|
| Node 16.13.1 (paper) | VULNERABLE | **VULNERABLE** |
| System Node v22.22.3 | MITIGATED | **MITIGATED** |

Proof-of-RCE marker file: **present (/home/behrad/University/Term8/NetworkSecurity/project/silent-spring-demo (2)/results/RCE_PROOF.txt)**

## What each file contains
- `probe-node16.txt` / `probe-system.txt` — standalone gadget probe output
- `exploit-node16.txt` / `exploit-system.txt` — full 4-step HTTP attack transcript
- `server-node16.log` / `server-system.log` — server-side console (shows pollution firing)
- `RCE_PROOF.txt` — file created by the injected command; existence proves arbitrary code execution

## Takeaways for the presentation
1. Passing user data to `spawn` as an **argv array is normally safe** — no shell, no injection.
2. A single prototype-pollution write (`Object.prototype.shell = true`) **silently re-enables** shell
   interpretation inside Node's own `child_process` internals → command injection ("universal gadget").
3. The **injection sink and the gadget live in different, individually-reasonable code** — this is why
   the bug is hard to spot and why the paper needed taint analysis to connect them.
4. Newer Node runtimes hardened the internal gadget (null-prototype default options), so the *same*
   exploit is **mitigated** on modern Node — a concrete argument for keeping runtimes patched.
