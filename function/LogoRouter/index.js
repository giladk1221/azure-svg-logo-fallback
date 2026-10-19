'use strict';
const fallback = require('./svg');
const fs = require('node:fs');
const path = require('node:path');
// Load the demo once per worker, outside the logo request path.
const demo = fs.readFileSync(path.join(__dirname, '../demo.html'));
let tokenCache;
const MAX_BYTES = 128 * 1024;

async function storageToken() {
  if (tokenCache && tokenCache.expires > Date.now() + 60000) return tokenCache.token;
  const endpoint = new URL(process.env.IDENTITY_ENDPOINT);
  endpoint.searchParams.set('api-version', '2019-08-01');
  endpoint.searchParams.set('resource', 'https://storage.azure.com/');
  if (process.env.AZURE_CLIENT_ID) endpoint.searchParams.set('client_id', process.env.AZURE_CLIENT_ID);
  const response = await fetch(endpoint, {headers: {'X-IDENTITY-HEADER': process.env.IDENTITY_HEADER}, signal: AbortSignal.timeout(5000)});
  if (!response.ok) throw Error('Managed identity token request failed');
  const data = await response.json();
  tokenCache = {token: data.access_token, expires: Number(data.expires_on) * 1000};
  return tokenCache.token;
}
async function lookup(key) {
  // Fixed administrator-configured origin. Visitors cannot supply an upstream URL.
  const account = process.env.LOGO_STORAGE_ACCOUNT;
  const container = process.env.LOGO_CONTAINER || 'logos';
  if (!/^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])$/.test(container) || container.includes('--')) throw Error('Invalid container configuration');
  if (!/^[a-z0-9]{3,24}$/.test(account || '')) throw Error('Invalid storage configuration');
  const response = await fetch(`https://${account}.blob.core.windows.net/${container}/${encodeURIComponent(key)}.svg`, {
    redirect: 'error', signal: AbortSignal.timeout(8000), headers: {
      Authorization: `Bearer ${await storageToken()}`, 'x-ms-version': '2023-11-03',
      'x-ms-date': new Date().toUTCString()
    }
  });
  if (response.status === 404) {
    // Only an actual missing blob counts as a missing logo. A missing container
    // or an access/configuration failure must not be disguised as a placeholder.
    const errorCode = response.headers.get('x-ms-error-code');
    await response.body?.cancel();
    return {status: errorCode === 'BlobNotFound' ? 404 : 502};
  }
  if (!response.ok || !response.headers.get('content-type')?.startsWith('image/svg+xml')) {
    await response.body?.cancel(); return {status: 502};
  }
  if (Number(response.headers.get('content-length')) > MAX_BYTES) {
    await response.body?.cancel(); return {status: 502};
  }
  const chunks = []; let bytes = 0;
  for await (const chunk of response.body) {
    bytes += chunk.length;
    if (bytes > MAX_BYTES) throw Error('Origin logo exceeded size limit');
    chunks.push(Buffer.from(chunk));
  }
  return {status: 200, body: Buffer.concat(chunks)};
}
function response(status, body, result, cache = 'no-store', type = 'text/plain; charset=utf-8') {
  const headers = {'Content-Type': type, 'Cache-Control': cache, 'X-Logo-Result': result, 'X-Content-Type-Options': 'nosniff'};
  if (type === 'image/svg+xml') headers['Content-Security-Policy'] = "default-src 'none'; style-src 'unsafe-inline'; sandbox";
  return {status, body, headers};
}
async function handle(req, context, originLookup = lookup) {
  const url = new URL(req.url);
  const log = (event, extra = {}) => context.log(JSON.stringify({event, ...extra, invocationId: context.invocationId}));
  if (url.pathname === '/logos/health') return response(200, 'healthy\n', 'health');
  if (url.pathname === '/logos/demo') return response(200, demo, 'demo', 'no-store', 'text/html; charset=utf-8');
  let pathname;
  try { pathname = decodeURIComponent(url.pathname); } catch { return response(400, 'Invalid path', 'invalid'); }
  // The second prefix preserves the path observed on the customer's website.
  pathname = pathname.replace(/^\/static\/v2\/static\/logos\//, '/logos/');
  const match = /^\/logos\/(fallback\/)?([A-Za-z0-9][A-Za-z0-9._:-]{0,95})\.svg$/.exec(pathname);
  if (!match || match[2].includes('..')) return response(404, 'Not Found', 'invalid');
  const forcedFallback = Boolean(match[1]), key = match[2];
  const explicit = url.searchParams.get('explicit') === 'true';
  if (!forcedFallback) {
    let existing;
    try { existing = await originLookup(key); } catch { existing = {status: 502}; }
    if (existing.status === 200) {
      log('logo_origin_hit', {key});
      return response(200, existing.body, 'original', 'public, max-age=300', 'image/svg+xml');
    }
    if (existing.status !== 404) {
      log('logo_origin_error', {key, status: existing.status});
      return response(502, 'Logo origin unavailable', 'origin-error');
    }
    log('logo_missing', {key, explicit});
  }
  if (explicit) {
    log('logo_fallback_suppressed', {key, forcedFallback});
    return response(404, 'Not Found', 'explicit-not-found');
  }
  log('logo_fallback_generated', {key, forcedFallback});
  return response(200, fallback(key), 'fallback', 'public, max-age=60', 'image/svg+xml');
}
module.exports = async function (context, req) {
  context.res = await handle(req, context);
  if (req.method === 'HEAD') context.res.body = '';
};
module.exports.handle = handle;
module.exports.fallback = fallback;
module.exports.lookup = lookup;
