#!/usr/bin/env python3
"""Azure CLI deployment, independent of Terraform. See docs/azure-cli.md."""
import argparse, copy, json, subprocess, sys, time, uuid
from pathlib import Path
from template import build,front_door,validate,ROOT,ROLES

def az(*args):
    result=subprocess.run(['az',*args,'--only-show-errors','-o','json'],capture_output=True,text=True)
    if result.returncode: raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout) if result.stdout.strip() else None

def rest_get(id,api):return az('rest','--method','get','--url','https://management.azure.com'+id+'?api-version='+api)
def write(path,data):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,indent=2)+'\n')
def route_conflicts(routes,name):
    wanted={'/logos/*','/static/v2/static/logos/*'}
    return [r['name'] for r in routes if r['name']!=name+'-logos' and wanted.intersection(r.get('properties',{}).get('patternsToMatch',[]))]

def preflight(c,folder):
    if c['mode']!='existing_front_door':return
    fd=c['existing_front_door'];pid=f"/subscriptions/{c['subscription_id']}/resourceGroups/{fd['resource_group_name']}/providers/Microsoft.Cdn/profiles/{fd['profile_name']}"
    if rest_get(pid,'2024-09-01')['sku']['name']!='Premium_AzureFrontDoor':raise RuntimeError('Existing Front Door must be Premium.')
    eid=pid+'/afdEndpoints/'+fd['endpoint_name']
    routes=rest_get(eid+'/routes','2024-09-01')['value']
    conflicts=route_conflicts(routes,c['name'])
    if conflicts:raise RuntimeError('Logo paths already owned by routes: '+', '.join(conflicts)+'. Review the migration; this script will not overwrite them.')
    groups=rest_get(pid+'/originGroups','2024-09-01')['value']
    owned=[r for r in routes+groups if r['name']==c['name']+'-logos']
    if owned and not (folder/'manifest.json').exists():raise RuntimeError('Same-name route or origin group exists without a local ownership manifest. Restore the manifest or choose a new deployment name.')

def approve(items,confirmed):
    if not items:raise RuntimeError('No Front Door connections in this mode. Follow manual integration instructions.')
    for origin in items:
        values=rest_get(origin['resource_id']+'/privateEndpointConnections','2024-04-01')['value']
        matched=[v for v in values if v['properties']['privateLinkServiceConnectionState'].get('description')==origin['request_message']]
        if not matched:raise RuntimeError('No matching connection yet. Wait for Front Door propagation and rerun.')
        for item in matched:
            status=item['properties']['privateLinkServiceConnectionState']['status'];print(item['id'],status)
            if confirmed and status=='Pending':az('network','private-endpoint-connection','approve','--id',item['id'],'--description',origin['request_message'])
            elif status not in ('Pending','Approved'):raise RuntimeError('Unexpected Private Link status; inspect before continuing.')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['render','plan','deploy','approve','cleanup-publisher'])
    parser.add_argument('--config',required=True)
    parser.add_argument('--yes',action='store_true',help='Confirm approval or temporary publisher cleanup after review.')
    a=parser.parse_args();c=validate(json.loads(Path(a.config).read_text()))
    folder=ROOT/'.deploy'/c['name'];manifest_path=folder/'manifest.json'
    manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else None
    ownership={k:c.get(k) for k in ['name','subscription_id','resource_group','mode','existing_front_door','existing_network','existing_catalog','existing_service_plan_id']}
    if manifest and manifest['ownership']!=ownership:raise RuntimeError('Immutable deployment ownership/config changed. Use a separate name/state or restore the original configuration.')
    if a.action=='deploy' and manifest and manifest.get('publisher_resource_ids') and not c.get('publish_artifacts',True):
        raise RuntimeError('Run cleanup-publisher first. Incremental deployments do not remove old publisher resources.')
    if a.action in ('render','plan','deploy'):
        subprocess.run([sys.executable,str(ROOT/'scripts/package.py')],check=True,cwd=ROOT)
        template,info=build(c);write(folder/'workload.json',template)
        print('Generated '+str(folder/'workload.json'))
        # Preview front-door resources offline with placeholder hostnames; deploy replaces these with actual Azure hostnames.
        origins={'logos':{'id':info['function_id'],'hostname':'FUNCTION_HOSTNAME_FROM_AZURE'}}
        if info['webapp_id']:origins['webapp']={'id':info['webapp_id'],'hostname':'WEBAPP_HOSTNAME_FROM_AZURE'}
        if c['mode']!='function_only':
            edge,edge_info=front_door(c,origins);write(folder/'front-door.preview.json',edge)
        if a.action=='render':return
    account=az('account','show')
    if account['id'].lower()!=c['subscription_id'].lower():raise RuntimeError('Select the configured subscription with az account set before continuing.')
    if a.action=='approve':
        if not manifest:raise RuntimeError('Deploy first; manifest missing.')
        approve(manifest.get('edge',{}).get('approvals',[]),a.yes);return
    if a.action=='cleanup-publisher':
        if not manifest:raise RuntimeError('Manifest missing; no resources will be deleted.')
        ids=manifest.get('publisher_resource_ids',[])
        print('Temporary resources:',json.dumps(ids,indent=2))
        if not a.yes:return
        subnet=manifest.get('publisher_nat_subnet')
        if subnet:
            attached=az('network','vnet','subnet','show','--ids',subnet).get('natGateway',{}).get('id')
            if attached and attached.lower() not in [x.lower() for x in ids]:raise RuntimeError('Subnet has a different NAT gateway; refusing to detach it.')
            if attached:az('network','vnet','subnet','update','--ids',subnet,'--remove','natGateway')
        for id in ids:
            try:az('resource','show','--ids',id)
            except RuntimeError as e:
                if 'ResourceNotFound' in str(e) or 'NotFound' in str(e):continue
                raise
            az('resource','delete','--ids',id)
        manifest['publisher_resource_ids']=[];manifest['publisher_nat_subnet']=None;write(manifest_path,manifest)
        print('Publisher removed. Set publish_artifacts=false in the config to avoid recreating it on next deployment.');return
    preflight(c,folder)
    rg=info['resource_group'];exists=az('group','exists','--name',rg)
    if not exists:
        if a.action=='plan':raise RuntimeError('For Azure what-if, create the dedicated empty resource group first: az group create -n '+rg+' -l '+c.get('location','westeurope')+' --tags deployment-tool=azure-cli svg-demo-name='+c['name'])
        az('group','create','--name',rg,'--location',c.get('location','westeurope'),'--tags','deployment-tool=azure-cli','svg-demo-name='+c['name'])
    tags=az('group','show','--name',rg).get('tags',{})
    if tags.get('deployment-tool')!='azure-cli' or tags.get('svg-demo-name')!=c['name']:raise RuntimeError('Workload resource group is not owned by this CLI deployment. Do not mix Terraform/CLI ownership.')
    action='what-if' if a.action=='plan' else 'create'
    if a.action=='deploy':
        manifest={**(manifest or {}),**info,'ownership':ownership};write(manifest_path,manifest)
    result=az('deployment','group',action,'--resource-group',rg,'--name','svg-'+c['name'],'--mode','Incremental','--template-file',str(folder/'workload.json'))
    if a.action=='plan':
        print(json.dumps(result,indent=2));print('This what-if covers the workload. Inspect front-door.preview.json for the edge changes; final edge template uses actual deployed app hostnames.');return
    previous=manifest or {}
    manifest={**previous,**info,'ownership':ownership};write(manifest_path,manifest)
    if c.get('existing_catalog'):
        cat=c['existing_catalog'];scope=cat['account_id']+'/blobServices/default/containers/'+cat['container_name']
        principal=az('identity','show','--ids',info['identity_id'])['principalId']
        role_name=str(uuid.uuid5(uuid.NAMESPACE_URL,c['name']+'|'+scope+'|external-reader'))
        assignment=az('role','assignment','create','--name',role_name,'--assignee-object-id',principal,'--assignee-principal-type','ServicePrincipal','--role',ROLES['reader'],'--scope',scope)
        manifest['external_reader_role_id']=assignment['id'];write(manifest_path,manifest)
    if c.get('publish_artifacts',True):
        az('functionapp','restart','--ids',info['function_id'])
        for attempt in range(20):
            try:
                az('rest','--method','post','--url','https://management.azure.com'+info['function_id']+'/syncfunctiontriggers?api-version=2024-04-01');break
            except RuntimeError:
                if attempt==19:raise
                time.sleep(15)
    if c['mode']!='function_only':
        origins={'logos':{'id':info['function_id'],'hostname':az('functionapp','show','--ids',info['function_id'])['defaultHostName']}}
        if info['webapp_id']:origins['webapp']={'id':info['webapp_id'],'hostname':az('webapp','show','--ids',info['webapp_id'])['defaultHostName']}
        edge,edge_info=front_door(c,origins);write(folder/'front-door.json',edge)
        # Record exact edge IDs before deployment, so a partial failure can be inspected and retried.
        manifest['edge']=edge_info;write(manifest_path,manifest)
        az('deployment','group','create','--resource-group',edge_info['resource_group'],'--name','svg-edge-'+c['name'],'--mode','Incremental','--template-file',str(folder/'front-door.json'))
        endpoint=rest_get(edge_info['endpoint_id'],'2024-09-01')
        manifest['demo_url']='https://'+endpoint['properties']['hostName']+'/logos/demo';write(manifest_path,manifest)
        print('Approve the listed Private Link requests before testing:',manifest['demo_url'])
    else:print('Private Function deployed. Connect your Front Door Premium origin to '+info['function_id']+' using subresource sites, then approve the request.')
    print('Deployment manifest: '+str(manifest_path))

if __name__=='__main__':
    try:main()
    except (RuntimeError,ValueError) as e:raise SystemExit(str(e))
