'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const {handle, fallback, lookup} = require('../function/LogoRouter');
function run(url, status=404) {
  const logs=[]; const ctx={invocationId:'local-test',log:x=>logs.push(JSON.parse(x))};
  return handle({url:'https://demo.test'+url,method:'GET'},ctx,async()=>({status,body:Buffer.from('<svg>original</svg>')})).then(res=>({res,logs}));
}
test('existing logo remains original with and without explicit=true',async()=>{
  for(const suffix of ['','?explicit=true']) {const {res,logs}=await run('/logos/JEPQ.svg'+suffix,200);assert.equal(res.status,200);assert.equal(res.headers['X-Logo-Result'],'original');assert.equal(res.body.toString(),'<svg>original</svg>');assert.equal(logs[0].event,'logo_origin_hit');}
});
test('missing JEMXX creates JE and logs missing and generated',async()=>{const {res,logs}=await run('/logos/JEMXX.svg');assert.equal(res.status,200);assert.match(res.body,/>JE<\/text>/);assert.equal(res.headers['Content-Type'],'image/svg+xml');assert.deepEqual(logs.map(l=>l.event),['logo_missing','logo_fallback_generated']);});
test('explicit missing is an uncached 404',async()=>{const {res,logs}=await run('/logos/JEMXX.svg?explicit=true');assert.equal(res.status,404);assert.equal(res.headers['Cache-Control'],'no-store');assert.equal(logs[1].event,'logo_fallback_suppressed');});
test('explicit value comparison matches VCL exactly',async()=>{const {res}=await run('/logos/JEMXX.svg?explicit=True');assert.equal(res.status,200);});
test('customer path is also accepted',async()=>{const {res}=await run('/static/v2/static/logos/JEMXX.svg');assert.equal(res.status,200);assert.match(res.body,/>JE<\/text>/);});
test('origin errors must not become cached placeholders',async()=>{for(const status of [403,500,502,503]){const {res,logs}=await run('/logos/JEMXX.svg',status);assert.equal(res.status,502);assert.equal(res.headers['Cache-Control'],'no-store');assert.equal(logs[0].event,'logo_origin_error');}});
test('direct fallback does not perform origin lookup',async()=>{let calls=0;const ctx={log:()=>{}};const res=await handle({url:'https://demo.test/logos/fallback/NASDAQ:MSFT.svg'},ctx,async()=>{calls++;throw Error('must not call');});assert.equal(calls,0);assert.match(res.body,/>MS<\/text>/);});
test('direct fallback explicit=true is 404',async()=>{assert.equal((await run('/logos/fallback/JEMXX.svg?explicit=true')).res.status,404);});
test('untrusted names cannot inject SVG or choose arbitrary origins',async()=>{for(const p of ['/logos/%3Cscript%3E.svg','/logos/a%2Fb.svg','/logos/a..b.svg','/logos/.svg','/logos/foo.png']){assert.equal((await run(p)).res.status,404);}});
test('colors are deterministic and in requested HSL ranges',()=>{const svg=fallback('JEMXX');assert.equal(svg,fallback('JEMXX'));const m=/hsl\((\d+),(\d+)%,(\d+)%\)/.exec(svg);assert.ok(m);assert.ok(+m[1]>=0&&+m[1]<=350);assert.ok(+m[2]>=30&&+m[2]<=70);assert.ok(+m[3]>=30&&+m[3]<=70);assert.ok(!svg.includes('%25'));});
test('Blob REST requests include identity, API version, date and bounded URL',async()=>{
  const original=global.fetch;const names=['IDENTITY_ENDPOINT','IDENTITY_HEADER','LOGO_STORAGE_ACCOUNT','AZURE_CLIENT_ID'];const saved=names.map(n=>process.env[n]);
  process.env.AZURE_CLIENT_ID='test-user-assigned-client';process.env.IDENTITY_ENDPOINT='http://localhost/identity';process.env.IDENTITY_HEADER='test-header';process.env.LOGO_STORAGE_ACCOUNT='testlogos';
  let calls=0;
  global.fetch=async(url,opts)=>{
    calls++;
    if(calls===1){assert.equal(new URL(url).searchParams.get('client_id'),'test-user-assigned-client');assert.equal(opts.headers['X-IDENTITY-HEADER'],'test-header');return Response.json({access_token:'test-token',expires_on:Math.floor(Date.now()/1000)+3600});}
    assert.equal(url,'https://testlogos.blob.core.windows.net/logos/EXCHANGE%3AJEMXX.svg');
    assert.equal(opts.headers.Authorization,'Bearer test-token');assert.equal(opts.headers['x-ms-version'],'2023-11-03');assert.ok(Number.isFinite(Date.parse(opts.headers['x-ms-date'])));assert.equal(opts.redirect,'error');
    return new Response('<svg/>',{headers:{'Content-Type':'image/svg+xml'}});
  };
  try{const res=await lookup('EXCHANGE:JEMXX');assert.equal(res.status,200);assert.equal(res.body.toString(),'<svg/>');assert.equal(calls,2);}finally{global.fetch=original;names.forEach((n,i)=>{if(saved[i]===undefined)delete process.env[n];else process.env[n]=saved[i];});}
});

test('VCL normalization is generic: uppercase, strip letters-colon prefix, first two characters',()=>{for(const [key,expected] of [['jemxx','JE'],['EXCHANGE:jemxx','JE'],['NASDAQ:MSFT','MS'],['A','A'],['A1:XYZ','A1']]) assert.ok(fallback(key).includes('>'+expected+'</text>'));});

test('Storage 404 is fallback only for BlobNotFound; transport/content failures remain errors',async()=>{
  const original=global.fetch, saved=process.env.LOGO_STORAGE_ACCOUNT;
  process.env.LOGO_STORAGE_ACCOUNT='testlogos';
  try {
    for(const [status,headers,expected] of [[404,{'x-ms-error-code':'BlobNotFound'},404],[404,{'x-ms-error-code':'ContainerNotFound'},502],[403,{},502],[200,{'Content-Type':'text/html'},502],[200,{'Content-Type':'image/svg+xml','Content-Length':'131073'},502]]) {
      global.fetch=async()=>new Response('<svg/>',{status,headers});
      assert.equal((await lookup('TEST')).status,expected);
    }
  } finally {global.fetch=original;if(saved===undefined)delete process.env.LOGO_STORAGE_ACCOUNT;else process.env.LOGO_STORAGE_ACCOUNT=saved;}
});
test('an oversized streamed SVG is rejected even without Content-Length',async()=>{
  const original=global.fetch,saved=process.env.LOGO_STORAGE_ACCOUNT;process.env.LOGO_STORAGE_ACCOUNT='testlogos';
  global.fetch=async()=>new Response('x'.repeat(131073),{headers:{'Content-Type':'image/svg+xml'}});
  try {await assert.rejects(lookup('TEST'),/size limit/);} finally {global.fetch=original;if(saved===undefined)delete process.env.LOGO_STORAGE_ACCOUNT;else process.env.LOGO_STORAGE_ACCOUNT=saved;}
});
test('custom container configuration is respected and invalid names fail before fetch',async()=>{
  const original=global.fetch, saved=[process.env.LOGO_STORAGE_ACCOUNT,process.env.LOGO_CONTAINER];process.env.LOGO_STORAGE_ACCOUNT='testlogos';process.env.LOGO_CONTAINER='brand-assets';
  global.fetch=async(url)=>{assert.equal(url,'https://testlogos.blob.core.windows.net/brand-assets/ACME.svg');return new Response('<svg/>',{headers:{'Content-Type':'image/svg+xml'}});};
  try {assert.equal((await lookup('ACME')).status,200);process.env.LOGO_CONTAINER='bad/container';await assert.rejects(lookup('ACME'),/container/);} finally {global.fetch=original;['LOGO_STORAGE_ACCOUNT','LOGO_CONTAINER'].forEach((n,i)=>{if(saved[i]===undefined)delete process.env[n];else process.env[n]=saved[i];});}
});
test('HTTP HEAD returns headers without a body',async()=>{
  const ctx={log:()=>{}};await require('../function/LogoRouter')(ctx,{url:'https://demo.test/logos/fallback/JEMXX.svg',method:'HEAD'});
  assert.equal(ctx.res.status,200);assert.equal(ctx.res.body,'');assert.equal(ctx.res.headers['X-Logo-Result'],'fallback');
});
