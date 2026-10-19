#!/usr/bin/env python3
"""Read-only verification through APIM or Front Door; no storage writes."""
import argparse, json, os, urllib.request, urllib.error, xml.etree.ElementTree as ET
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('base_url',help='https://<gateway-or-front-door-host>, without /logos')
ap.add_argument('--original',default='ACME',help='Existing SVG key (case-sensitive)')
ap.add_argument('--missing',default='JEMXX',help='A key known to be absent')
a=ap.parse_args()
if not a.base_url.startswith('https://'): raise SystemExit('Use HTTPS.')
headers={}
if os.environ.get('LOGO_TEST_TOKEN'): headers['Authorization']='Bearer '+os.environ['LOGO_TEST_TOKEN']
# Existing customer gateways may require their own authentication; never print credentials.
if os.environ.get('APIM_SUBSCRIPTION_KEY'): headers['Ocp-Apim-Subscription-Key']=os.environ['APIM_SUBSCRIPTION_KEY']
checks=[(f'/logos/{a.original}.svg',200,'original'),(f'/logos/{a.missing}.svg',200,'fallback'),(f'/logos/{a.missing}.svg?explicit=true',404,'explicit-not-found'),(f'/logos/{a.original}.svg?explicit=true',200,'original'),(f'/logos/fallback/{a.missing}.svg',200,'fallback'),(f'/static/v2/static/logos/{a.missing}.svg',200,'fallback')]
for round in range(2):
    for path,status,result in checks:
        try: r=urllib.request.urlopen(urllib.request.Request(a.base_url.rstrip('/')+path,headers=headers),timeout=45)
        except urllib.error.HTTPError as e: r=e
        with r:
            body=r.read();h=r.headers
            assert r.status==status, (path,r.status,status)
            assert h.get('X-Logo-Result')==result,(path,dict(h))
            if status==404: assert h.get('Cache-Control')=='no-store',path
            else:
                assert h.get_content_type()=='image/svg+xml',path
                root=ET.fromstring(body)
                assert root.tag=='{http://www.w3.org/2000/svg}svg',path
                if result=='fallback':
                    import re
                    letters=re.sub(r'^[A-Z]+:','',a.missing.upper())[:2]
                    assert root.find('{http://www.w3.org/2000/svg}text').text==letters,path
            print(json.dumps({'round':round+1,'path':path,'status':r.status,'result':result,'cache':h.get('X-Cache'),'age':h.get('Age')}))
print('PASS: 12 requests. Cache hits are informational; POP warming is asynchronous.')
