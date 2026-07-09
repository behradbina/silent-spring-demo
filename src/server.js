/**
 * Silent Spring — Educational Demo Server
 * ---------------------------------------
 * A deliberately-vulnerable "SysMon" dashboard that reproduces the two-stage
 * attack from:
 *
 *   Shcherbakov, Balliu, Staicu. "Silent Spring: Prototype Pollution Leads to
 *   Remote Code Execution in Node.js." USENIX Security 2023.
 *
 * The paper describes a Prototype-based Object Injection Vulnerability (POIV):
 *
 *   Stage 1 (Injection sink):  attacker-controlled data is deep-merged into an
 *                              object, polluting Object.prototype.
 *   Stage 2 (Universal gadget): legitimate code later reads a property that it
 *                              never set (e.g. `options.shell`). Because the
 *                              property is missing on the object, the JS engine
 *                              walks the prototype chain and finds the polluted
 *                              value — turning a "safe" child_process.spawn call
 *                              into arbitrary command execution.
 *
 * THIS SERVER IS INTENTIONALLY INSECURE. Run it only on localhost for the
 * course demo. Do not deploy.
 */

const express = require('express');
const _ = require('lodash');
const { spawn } = require('child_process');
const path = require('path');

const app = express();
app.use(express.json()); // body-parser: preserves "__proto__" / "constructor" keys from JSON

// -------------------------------------------------------------------------
// Application state. A plain object literal => it inherits from Object.prototype,
// so once the prototype is polluted, `dashboardConfig.<missing>` reflects it.
// -------------------------------------------------------------------------
let dashboardConfig = {
  title: 'System Monitor',
  theme: 'dark',
  refreshRate: 5000,
};

app.use(express.static(path.join(__dirname, 'public')));

// -------------------------------------------------------------------------
// STAGE 1 — Injection sink.
// A realistic "save settings" endpoint that deep-merges user JSON into config
// using a vulnerable lodash version (4.17.11). `defaultsDeep` recurses into
// `constructor.prototype`, letting an attacker write onto Object.prototype.
// (This is the class of bug the paper detects with its taint analysis.)
// -------------------------------------------------------------------------
app.post('/api/settings', (req, res) => {
  console.log('[settings] merge request:', JSON.stringify(req.body));
  _.defaultsDeep(dashboardConfig, req.body); // <-- VULNERABLE SINK
  res.json({ status: 'ok', config: dashboardConfig });
});

// -------------------------------------------------------------------------
// STAGE 2 — Universal gadget trigger.
// "Network diagnostics": ping a host. Arguments are passed as an ARRAY, which
// is the textbook-safe way to call spawn — no shell, so `;`/`&&` in the host
// are NOT interpreted. This endpoint is safe... UNLESS Object.prototype.shell
// has been polluted. Then Node's own normalizeSpawnArgs reads the inherited
// `options.shell === true` and re-runs the command through `/bin/sh -c`,
// resurrecting classic command injection. This is gadget G1 from the paper.
//
// NOTE: modern Node (>=18) hardened this internal gadget by using a
// null-prototype default options object, so on newer runtimes the same
// pollution no longer flips spawn into shell mode. The demo runner exercises
// both Node 16 (vulnerable) and the system Node to show the difference.
// -------------------------------------------------------------------------
app.get('/api/ping', (req, res) => {
  const host = req.query.host || '127.0.0.1';
  console.log('[ping] host =', JSON.stringify(host), '| {}.shell =', {}.shell);

  // The "safe" pattern: fixed binary, user data isolated in an argv array.
  const child = spawn('ping', ['-c', '1', host]);

  let output = '';
  child.stdout.on('data', (d) => (output += d));
  child.stderr.on('data', (d) => (output += d));
  child.on('error', (err) => res.status(500).json({ error: err.message }));
  child.on('close', (code) =>
    res.json({ host, exitCode: code, shellPolluted: {}.shell === true, output })
  );
});

// -------------------------------------------------------------------------
// Evidence endpoint — lets the demo script observe the pollution state of the
// running process without executing anything.
// -------------------------------------------------------------------------
app.get('/api/status', (req, res) => {
  const probe = {}; // fresh object; any property here is inherited from prototype
  res.json({
    node: process.version,
    prototypePolluted: {}.shell !== undefined || {}.polluted !== undefined,
    inheritedShell: probe.shell,
    inheritedPolluted: probe.polluted,
    config: dashboardConfig,
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '127.0.0.1', () => {
  console.log(`[server] SysMon dashboard on http://127.0.0.1:${PORT}  (Node ${process.version})`);
});
