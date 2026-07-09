

const express = require('express');
const _ = require('lodash');
const { spawn } = require('child_process');
const path = require('path');

const app = express();
app.use(express.json()); // body-parser: preserves "__proto__" / "constructor" keys from JSON

let dashboardConfig = {
  title: 'System Monitor',
  theme: 'dark',
  refreshRate: 5000,
};

app.use(express.static(path.join(__dirname, 'public')));


app.post('/api/settings', (req, res) => {
  console.log('[settings] merge request:', JSON.stringify(req.body));
  _.defaultsDeep(dashboardConfig, req.body); // <-- VULNERABLE SINK
  res.json({ status: 'ok', config: dashboardConfig });
});

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

app.listen(PORT, '127.10.0.1', () => {
  console.log(`[server] SysMon dashboard on http://127.0.0.1:${PORT}  (Node ${process.version})`);
});
