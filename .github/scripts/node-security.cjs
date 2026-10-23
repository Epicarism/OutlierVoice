// October 21, 2026 runtime baseline; no dependencies or application code are loaded.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { brotliCompressSync, brotliDecompressSync } = require('node:zlib');
const root = path.resolve(__dirname, '../..');
const packageDirs = ["AlarmServer"];
const engine = '>=22.23.4 <23 || >=24.22.1 <25 || >=26.12.1 <27';
const floors = new Map([[22, [23, 4]], [24, [22, 1]], [26, [12, 1]]]);
function verifyVersion(value, source) {
  const match = /^v?(\d+)\.(\d+)\.(\d+)$/.exec(value);
  const [major, minor, patch] = match ? match.slice(1).map(Number) : [];
  const floor = floors.get(major);
  if (!floor || minor < floor[0] || (minor === floor[0] && patch < floor[1])) {
    throw new Error(`${source}: Node ${value} is vulnerable, EOL, or unreviewed; require ${engine}`);
  }
}
function verifyPins(text, source) {
  // Deployment selectors only: dependency engines and historical prose are not runtime pins.
  const selectors = /(?:node-versions\/v|versions\/node\/v|node-v|\bnode:(?=\d)|\bNODE_(?:VERSION|MAJOR)\s*[=:]\s*["']?|\bnode-version\s*:\s*["']?|\bnvm\s+(?:install|use)\s+|\bfnm\s+(?:install|use)\s+)(v?\d+(?:\.\d+){0,2})/g;
  for (const match of text.matchAll(selectors)) verifyVersion(match[1], source);
}
function selfTest() {
  for (const version of ['22.23.4', '24.22.1', '26.12.1', '24.23.0']) verifyVersion(version, 'boundary');
  for (const version of ['18.20.8', '20.19.0', '22.23.3', '24.22.0', '26.12.0', '23.0.0', '25.0.0', '27.0.0', '24', 'garbage']) {
    assert.throws(() => verifyVersion(version, 'boundary'), /vulnerable, EOL, or unreviewed/);
  }
  for (const text of ['FROM node:20-bookworm', 'node-version: 24.22.0', 'PATH=/x/node-versions/v24.21.0/installation/bin', 'NODE_MAJOR=22', 'nvm install v18.20.8', 'fnm use v24.21.0', 'NODE_VERSION=v20.19.0', 'node-version: v20.19.0']) {
    assert.throws(() => verifyPins(text, 'fixture'), /fixture: Node/);
  }
  verifyPins('FROM node:22.23.4-bookworm\nnode-version: "24.22.1"', 'patched fixture');
  verifyPins("import { serialize } from 'node:v8';", 'builtin fixture');
  console.log('PASS supported-floor boundaries and stale deployment selector rejection');
}
try {
  if (process.argv.includes('--self-test')) selfTest();
  verifyVersion(process.versions.node, 'running process');
  for (const dir of packageDirs) {
    const base = path.join(root, dir);
    verifyVersion(fs.readFileSync(path.join(base, '.node-version'), 'utf8').trim(), `${dir}/.node-version`);
    const manifest = JSON.parse(fs.readFileSync(path.join(base, 'package.json'), 'utf8'));
    if (manifest.volta?.node) verifyVersion(manifest.volta.node, `${dir}/package.json volta.node`);
  }
  const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: root, maxBuffer: 16 * 1024 * 1024 }).toString().split('\0');
  for (const file of files) {
    if (!file || file === '.github/scripts/node-security.cjs' || /(^|\/)(node_modules|vendor|Vendor)\//.test(file)) continue;
    const inScope = packageDirs.includes('.') || packageDirs.some(dir => file.startsWith(`${dir}/`)) || file.startsWith('.github/');
    if (!inScope || !fs.lstatSync(path.join(root, file)).isFile()) continue;
    if (/(^|\/)\.(?:node-version|nvmrc)$/.test(file)) {
      verifyVersion(fs.readFileSync(path.join(root, file), 'utf8').trim(), file);
    } else if (/\.(?:sh|bash|py|mjs|cjs|js|ps1|bat|cmd|ya?ml|md)$/.test(file) || /(^|\/)(?:Dockerfile|Containerfile)[^/]*$/.test(file)) {
      verifyPins(fs.readFileSync(path.join(root, file), 'utf8'), file);
    }
  }
  const input = Buffer.from('October 2026 Node security baseline: normal Brotli roundtrip.\n'.repeat(64));
  assert.deepEqual(brotliDecompressSync(brotliCompressSync(input)), input);
  console.log(`PASS Node ${process.versions.node}; repository runtime pins; benign Brotli roundtrip`);
  console.log('Version + roundtrip verify the baseline, not exploit resistance or vendor backport provenance.');
} catch (error) {
  console.error(`Node security gate FAILED: ${error.message}`);
  process.exitCode = 1;
}
