# Paper notes — *Silent Spring* (USENIX Security 2023)

Condensed summary of the paper, with pointers to where each idea shows up in this demo.

## 1. Problem

**Prototype pollution** lets an attacker inject properties into `Object.prototype`
at runtime. Because almost every JS object inherits from that root prototype, the
injected property is visible *everywhere*. Prior work mostly showed this leads to
**Denial of Service** (e.g. overwriting `toString`). This paper is the first to
systematically show it leads to **Remote Code Execution** in real Node.js apps.

## 2. Key concept: POIV (Prototype-based Object Injection Vulnerability)

A two-stage attack, analogous to insecure-deserialization gadget chains:

| Stage | Name | What happens | In this demo |
|---|---|---|---|
| 1 | **Injection sink** | Untrusted data flows into a property write that reaches `obj[proto][prop] = value`, mutating the root prototype. | `_.defaultsDeep(config, req.body)` in `POST /api/settings` |
| 2 | **Gadget** | Legitimate code later *reads* a property it didn't set; the read falls through to the polluted prototype and flows into a security-sensitive **attack sink**. | `spawn('ping', [...])` reading inherited `options.shell` |

"The attacker loads the gun in stage one and lets a gadget pull the trigger in stage two."

## 3. The framework (what we deliberately did NOT rebuild)

The paper's automated tooling is built on **CodeQL** and has three parts:

1. **Prototype-pollution detection** — multi-label static taint analysis (labels
   `input` and `proto`) to find injection sinks of shape `obj[proto][prop]=value`.
   Tuned for **high recall** over precision (embraces false positives). Five query
   variants (Exported vs Any functions; Priority vs General).
2. **Gadget detection** — *hybrid*: dynamic analysis installs getters on
   `Object.prototype` to discover which property names Node's own APIs read when
   uninitialized (e.g. `shell`, `env`, `main`, `exports`), then static taint
   analysis traces those reads to native "attack sinks".
3. **Exploit generation** — human-in-the-loop.

> This educational demo skips the CodeQL analysis and instead **reproduces the
> exploit** that the analysis is designed to find, which is the part that best
> communicates the risk in a presentation.

## 4. Universal gadgets (Table 1 of the paper)

11 gadgets found in Node.js core. They are "universal" because they ship with the
runtime and work in *any* app. Our demo reproduces the headline one:

- **G1 — `shell`, `env`**: pollute `shell` → command-execution APIs (`spawn`,
  `spawnSync`, `exec`, `execSync`, `execFileSync`) run through `/bin/sh -c`,
  enabling command injection even when the developer used the safe argv-array form.
  Precondition: the call site does not explicitly pass an `options` argument.
- Others: `main` / `exports` / `1` confuse Node's module resolver into `require`-ing
  an attacker-chosen file from disk (G4–G11); `contextExtensions` overwrites globals
  in `vm` (G8–G9). Gadgets can be **chained** (e.g. G10, G11).

## 5. Real-world impact (Section 6.3)

Analyzed 15 popular Node.js apps → **8 exploitable RCEs** in **NPM CLI**,
**Parse Server**, and **Rocket.Chat**. Notable: the NPM CLI `diffApply` injection
sink + git's `GIT_SSH_COMMAND` env gadget (`spawn`) → RCE during `npm install`
(CVE-2022-24760). Responsibly disclosed and fixed.

## 6. Headline results to quote

- 11 universal gadgets in Node.js core.
- 8 RCEs across 3 high-profile apps.
- Detection tuned for recall: General/Any queries ≈ **97% recall**, Priority/Any ≈
  **40% precision / 93% recall** (their chosen sweet spot); vs ODGen's high
  precision but ~50% recall.
- Estimated gadget-trigger prevalence in top-10k NPM packages: 1,958 have no `main`,
  4,420 use relative `require` paths, 355 call a command-exec API.

## 7. Defenses discussed

- `Object.freeze(Object.prototype)` / null-prototype objects (`Object.create(null)`).
- Validate/reject `__proto__`, `constructor`, `prototype` keys before merging.
- Code debloating (Mininode) to remove unused gadget code.
- Keeping the Node runtime patched (later versions hardened several core gadgets —
  reproduced first-hand in this demo: vulnerable on 16.13.1, mitigated on 18+).
