'use strict';
const crypto = require('node:crypto');

// Fastly describes fastly.hash as MurmurHash-based, without specifying its exact
// variant and range mapping. These stable colors do NOT claim exact Fastly parity.
function boundedHash(key, seed, low, high) {
  const hash = crypto.createHash('sha256').update(`${seed}:${key}`).digest();
  return low + hash.readUInt32BE(0) % (high - low + 1);
}
function fallback(key) {
  const ticker = key.toUpperCase().replace(/^[A-Z]+:/, '').slice(0, 2);
  const color = `hsl(${boundedHash(key, 0, 0, 350)},${boundedHash(key, 40, 30, 70)}%,${boundedHash(key, 90, 30, 70)}%)`;
  // The request allowlist excludes XML metacharacters. Escape as a second guard.
  const text = ticker.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
  return `<svg xmlns="http://www.w3.org/2000/svg" width="48px" height="40px" viewBox="0 0 40 40" version="1.1"><rect fill="${color}" cx="20" width="40" height="40" cy="20" r="20" rx="200"></rect><text x="50%" y="50%" alignment-baseline="middle" text-anchor="middle" font-size="18" font-weight="400" font-family="Arial" dy=".1em" dominant-baseline="middle" fill="#FFFFFF">${text}</text></svg>`;
}
module.exports = fallback;
