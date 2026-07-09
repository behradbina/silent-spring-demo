#!/usr/bin/env node
'use strict';

const { spawnSync } = require('child_process');

const PROBE_ARGS = ['SAFE; echo INJECTED'];

function ranThroughShell() {
  const r = spawnSync('echo', PROBE_ARGS);
  const out = (r.stdout || '').toString().trim();
  return out.split('\n').length > 1;
}

const baseline = ranThroughShell();

Object.prototype.shell = true;

const polluted = ranThroughShell();

console.log(JSON.stringify({
  node: process.version,
  baselineFired: baseline,
  pollutedFired: polluted,
  verdict: polluted ? 'VULNERABLE' : 'MITIGATED'
}));