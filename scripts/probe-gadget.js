'use strict';
const { spawnSync } = require('child_process');

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

console.log('RESULT_JSON ' + JSON.stringify({
  node: process.version,
  baselineFired: before.fired,
  pollutedFired: after.fired,
  verdict,
}));

process.exit(after.fired ? 0 : 0);
