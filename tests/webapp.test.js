'use strict';
const test=require('node:test'), assert=require('node:assert/strict');
const handler=require('../webapp/server');
function request(url,method='GET'){const headers={};let body;handler({url,method},{setHeader:(k,v)=>headers[k]=v,end:b=>body=b});return {headers,body};}
test('Web App identifies the separate origin and links to the logo route',()=>{const {headers,body}=request('/');assert.equal(headers['X-Demo-Origin'],'webapp');assert.equal(headers['Cache-Control'],'no-store');assert.match(body,/href="\/logos\/demo"/);});
test('Web App health and HEAD requests return appropriate bodies',()=>{assert.equal(request('/health').body,'healthy\n');assert.equal(request('/','HEAD').body,'');});
