#!/usr/bin/env python3
"""List, or explicitly approve, only the private-link request for this stack."""
import argparse, json, subprocess
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--approve',action='store_true')
args=ap.parse_args()
def az(*args): return subprocess.check_output(['az',*args],text=True)
output=json.loads(subprocess.check_output(['terraform','-chdir=terraform','output','-json','front_door_private_link_approval'],text=True))
if not output: raise SystemExit('This stack has no Front Door.')
items=json.loads(az('rest','--method','get','--url',output['apim_id']+'/privateEndpointConnections?api-version=2024-05-01'))['value']
matches=[x for x in items if x['properties']['privateLinkServiceConnectionState'].get('description')==output['request_message']]
if not matches: raise SystemExit('No matching request yet. Wait for Front Door provisioning, then rerun.')
for item in matches:
    state=item['properties']['privateLinkServiceConnectionState']['status']
    print(item['id'], state)
    if args.approve and state=='Pending':
        az('network','private-endpoint-connection','approve','--id',item['id'],'--description',output['request_message'])
        print('Approved this stack\'s request.')
    elif state not in ('Pending','Approved'):
        raise SystemExit('Unexpected state; inspect this connection before proceeding.')
if not args.approve: print('Review the IDs above, then rerun with --approve.')
