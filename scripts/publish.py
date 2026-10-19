#!/usr/bin/env python3
"""Upload immutable packages and optional fictional fixtures from a private runner.
Uses the VM system identity with --identity, otherwise the current Azure CLI login.
No account keys or SAS URLs. Also embedded in the optional Terraform VM Run Command.
"""
import argparse, base64, datetime, hashlib, ipaddress, json, socket, subprocess, time
import urllib.error, urllib.parse, urllib.request

def token(identity):
    if identity:
        url = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F'
        with urllib.request.urlopen(urllib.request.Request(url, headers={'Metadata':'true'}), timeout=15) as r:
            return json.load(r)['access_token']
    return subprocess.check_output(['az','account','get-access-token','--resource','https://storage.azure.com/','--query','accessToken','-o','tsv'], text=True).strip()

def upload(account, container, name, data, content_type, identity):
    host = account + '.blob.core.windows.net'
    ips = {x[4][0] for x in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)}
    if not ips or not all(ipaddress.ip_address(ip).is_private for ip in ips):
        raise RuntimeError('Storage must resolve to private addresses: '+host)
    url = 'https://' + host + '/' + container + '/' + urllib.parse.quote(name, safe='')
    digest = hashlib.sha256(data).hexdigest()
    for attempt in range(60):
        headers = {'Authorization':'Bearer '+token(identity), 'x-ms-version':'2023-11-03', 'x-ms-date':datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')}
        request = urllib.request.Request(url, data=data, method='PUT', headers={**headers, 'x-ms-blob-type':'BlockBlob','Content-Type':content_type,'If-None-Match':'*','x-ms-meta-sha256':digest})
        try:
            with urllib.request.urlopen(request,timeout=60): pass
            print('Uploaded '+container+'/'+name, flush=True)
            return
        except urllib.error.HTTPError as e:
            if e.code == 412:
                with urllib.request.urlopen(urllib.request.Request(url,headers=headers),timeout=60) as r:
                    existing = r.read(len(data)+1)
                if hashlib.sha256(existing).hexdigest() != digest:
                    raise RuntimeError('Refusing to overwrite different existing content: '+name)
                print('Verified existing '+container+'/'+name, flush=True)
                return
            if e.code not in (401,403,408,429,500,502,503,504) or attempt == 59: raise
            time.sleep(10)
    raise RuntimeError('Upload retries exhausted')

def publish(payload,identity=False):
    upload(payload['host'], 'packages', payload['package_name'], base64.b64decode(payload['package']), 'application/zip', identity)
    for name,data in payload.get('assets',{}).items():
        upload(payload['catalog'], 'logos', name, base64.b64decode(data), 'image/svg+xml', identity)

if __name__ == '__main__':
    from pathlib import Path
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--identity',action='store_true')
    ap.add_argument('--host',required=True)
    ap.add_argument('--catalog',help='Only set for a NEW demo catalog to seed fictional samples.')
    ap.add_argument('--package',default='.build/function.zip')
    args=ap.parse_args()
    data=Path(args.package).read_bytes()
    payload={'host':args.host,'catalog':args.catalog,'package_name':'logo-'+hashlib.sha256(data).hexdigest()+'.zip','package':base64.b64encode(data).decode(),'assets':{}}
    if args.catalog:
        payload['assets']={f.name:base64.b64encode(f.read_bytes()).decode() for f in Path('assets/logos').glob('*.svg')}
    publish(payload,args.identity)
