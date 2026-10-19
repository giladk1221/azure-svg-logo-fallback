'use strict';
const http = require('node:http');
const page = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Private Web App demo</title><style>body{font:18px system-ui;max-width:800px;margin:8vh auto;padding:24px;color:#18334d}a{color:#0969da}code{background:#eef4fa;padding:4px}</style><h1>Front Door → private Web App</h1><p>This page is served by the App Service origin. The more specific <code>/logos/*</code> route goes directly to the SVG Function.</p><p><a href="/logos/demo">Open the stored and generated SVG logo demo →</a></p><p>The Function reads existing logos from private Blob Storage and generates a two-character SVG only when the original is missing.</p></html>`;
function handler(req,res) {
  res.setHeader('Cache-Control','no-store');
  res.setHeader('X-Demo-Origin','webapp');
  res.setHeader('Content-Type',req.url==='/health'?'text/plain':'text/html; charset=utf-8');
  res.end(req.method==='HEAD'?'':req.url==='/health'?'healthy\n':page);
}
if(require.main===module) http.createServer(handler).listen(Number(process.env.PORT)||8080,'0.0.0.0');
module.exports = handler;
