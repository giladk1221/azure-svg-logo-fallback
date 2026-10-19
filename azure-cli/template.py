"""Generate an ARM template for the private workload. No SDKs, credentials or Terraform.
The Azure CLI driver manages Front Door routes separately so existing profiles stay external.
"""
import base64, hashlib, json, re, uuid
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
STARTUP = "node -e \"const http=require('node:http');const m={exports:{}};new Function('require','module','process',Buffer.from(process.env.DEMO_SERVER_B64,'base64').toString())(require,m,process);http.createServer(m.exports).listen(Number(process.env.PORT)||8080,'0.0.0.0')\""
ROLES = {'owner':'b7e6dc6d-f1e8-4753-8033-0f276bb0955b','reader':'2a2b9908-6ea1-4ae2-8e65-a410df84e7d1','contributor':'ba92f5b4-2d11-453d-a403-e96b0029c9fe'}

def validate(c):
    if c.get('mode') not in ('full','existing_front_door','function_only'): raise ValueError('Choose full, existing_front_door, or function_only.')
    if not re.fullmatch(r'[a-z][a-z0-9]{2,17}',c.get('name','')): raise ValueError('name: 3–18 lowercase alphanumeric characters, starting with a letter; choose a globally unique value.')
    if not re.fullmatch(r'[0-9a-fA-F-]{36}',c.get('subscription_id','')): raise ValueError('Set subscription_id.')
    if c['mode']=='existing_front_door' and not all(c.get('existing_front_door',{}).get(k) for k in ('profile_name','resource_group_name','endpoint_name')): raise ValueError('Existing mode needs profile_name, resource_group_name and endpoint_name.')
    if c.get('publish_artifacts',True) and not c.get('publisher_ssh_public_key','').startswith('ssh-'): raise ValueError('Set an SSH PUBLIC key, or publish_artifacts=false.')
    if c.get('existing_network'):
        required=['vnet_id','function_subnet_id','private_endpoint_subnet_id']
        if c.get('publish_artifacts',True): required.append('publisher_subnet_id')
        if not all(c['existing_network'].get(k) for k in required): raise ValueError('Incomplete existing_network inputs.')
    if c.get('existing_catalog') and not all(c['existing_catalog'].get(k) for k in ('account_id','account_name','container_name')): raise ValueError('Incomplete existing_catalog inputs.')
    return c

def build(c):
    validate(c)
    n=c['name']; rg=c.get('resource_group','rg-'+n); sub=c['subscription_id']; loc=c.get('location','westeurope'); publish=c.get('publish_artifacts',True)
    prefix=f'/subscriptions/{sub}/resourceGroups/{rg}/providers/'
    def rid(typ,name):
        types=typ.split('/'); names=name.split('/')
        if len(types)-1 != len(names): raise ValueError('Invalid nested resource name: '+typ+' '+name)
        return prefix+types[0]+'/'+ '/'.join(x for pair in zip(types[1:],names) for x in pair)
    resources=[]; cleanup=[]; tags={**c.get('tags',{}),'purpose':'svg-logo-demo','deployment-tool':'azure-cli','svg-demo-name':n}
    def add(typ,name,props,api='2023-05-01',deps=(),**kwargs):
        r={'type':typ,'apiVersion':api,'name':name,'properties':props,**kwargs}
        if deps:r['dependsOn']=list(deps)
        resources.append(r);return rid(typ,name)
    def ref(id,api,prop):return f"[reference('{id}', '{api}').{prop}]"
    uai=add('Microsoft.ManagedIdentity/userAssignedIdentities',n+'-function-mi',{},api='2023-01-31',location=loc,tags=tags)
    principal=ref(uai,'2023-01-31','principalId');client=ref(uai,'2023-01-31','clientId')
    host=rid('Microsoft.Storage/storageAccounts',n+'host')
    catalog=c.get('existing_catalog') or {'account_id':rid('Microsoft.Storage/storageAccounts',n+'logos'),'account_name':n+'logos','container_name':'logos'}
    new_catalog=not c.get('existing_catalog')
    for name,container in [(n+'host','packages')]+([(n+'logos','logos')] if new_catalog else []):
        account=add('Microsoft.Storage/storageAccounts',name,{'minimumTlsVersion':'TLS1_2','supportsHttpsTrafficOnly':True,'allowSharedKeyAccess':False,'allowBlobPublicAccess':False,'publicNetworkAccess':'Disabled','networkAcls':{'defaultAction':'Deny','bypass':'None'}},location=loc,kind='StorageV2',sku={'name':'Standard_LRS'},tags=tags)
        add('Microsoft.Storage/storageAccounts/blobServices/containers',name+'/default/'+container,{'publicAccess':'None'},deps=[account])
    def role(scope,who,label,kind,deps):
        name=str(uuid.uuid5(uuid.NAMESPACE_URL,n+'|'+scope+'|'+label+'|'+kind))
        # ARM extension resource scope is relative to this deployment resource group.
        rel=scope.split('/providers/',1)[1]
        add('Microsoft.Authorization/roleAssignments',name,{'principalId':who,'principalType':'ServicePrincipal','roleDefinitionId':f'/subscriptions/{sub}/providers/Microsoft.Authorization/roleDefinitions/{ROLES[kind]}'},api='2022-04-01',scope=rel,deps=deps)
        return scope+'/providers/Microsoft.Authorization/roleAssignments/'+name
    host_role=role(host,principal,'function','owner',[uai,host])
    catalog_role=None
    if new_catalog:catalog_role=role(catalog['account_id']+'/blobServices/default/containers/logos',principal,'function','reader',[uai,rid('Microsoft.Storage/storageAccounts/blobServices/containers',n+'logos/default/logos')])
    network=c.get('existing_network'); nat=None
    if publish and not network:
        ip=add('Microsoft.Network/publicIPAddresses',n+'-publisher-egress',{'publicIPAllocationMethod':'Static'},api='2024-05-01',location=loc,sku={'name':'Standard'},tags=tags)
        nat=add('Microsoft.Network/natGateways',n+'-publisher-nat',{'publicIpAddresses':[{'id':ip}]},api='2024-05-01',location=loc,sku={'name':'Standard'},deps=[ip],tags=tags)
        cleanup.extend([nat,ip])
    if not network:
        vnet=rid('Microsoft.Network/virtualNetworks',n+'-vnet')
        subnets=[]
        for sn,space in [('function','10.84.1.0/24'),('endpoints','10.84.2.0/24'),('publisher','10.84.3.0/27')]:
            props={'addressPrefix':space,'privateEndpointNetworkPolicies':'Disabled','defaultOutboundAccess':False}
            if sn=='function':props['delegations']=[{'name':'web','properties':{'serviceName':'Microsoft.Web/serverFarms'}}]
            if sn=='publisher' and nat:props['natGateway']={'id':nat}
            subnets.append({'name':sn,'properties':props})
        add('Microsoft.Network/virtualNetworks',n+'-vnet',{'addressSpace':{'addressPrefixes':['10.84.0.0/16']},'subnets':subnets},api='2024-05-01',location=loc,tags=tags,deps=[nat] if nat else [])
        network={'vnet_id':vnet,'function_subnet_id':vnet+'/subnets/function','private_endpoint_subnet_id':vnet+'/subnets/endpoints','publisher_subnet_id':vnet+'/subnets/publisher'}
    zone=c.get('private_dns_zone_ids',{}).get('blob')
    network_deps=[] if c.get('existing_network') else [network['vnet_id']]
    dns_deps=[]
    if not zone:
        zone=add('Microsoft.Network/privateDnsZones','privatelink.blob.core.windows.net',{},api='2020-06-01',location='global',tags=tags)
        link=add('Microsoft.Network/privateDnsZones/virtualNetworkLinks','privatelink.blob.core.windows.net/'+n,{'virtualNetwork':{'id':network['vnet_id']},'registrationEnabled':False},api='2020-06-01',location='global',deps=[zone]+network_deps)
        dns_deps=[link]
    private_endpoints=[]
    for label,account in [('host',host)]+([('catalog',catalog['account_id'])] if new_catalog else []):
        pe=add('Microsoft.Network/privateEndpoints',n+'-'+label+'-pe',{'subnet':{'id':network['private_endpoint_subnet_id']},'privateLinkServiceConnections':[{'name':label,'properties':{'privateLinkServiceId':account,'groupIds':['blob']}}]},api='2024-05-01',location=loc,tags=tags,deps=[account]+network_deps)
        group=add('Microsoft.Network/privateEndpoints/privateDnsZoneGroups',n+'-'+label+'-pe/default',{'privateDnsZoneConfigs':[{'name':'blob','properties':{'privateDnsZoneId':zone}}]},api='2024-05-01',deps=[pe]+dns_deps)
        private_endpoints.append(group)
    plan=c.get('existing_service_plan_id')
    if not plan:plan=add('Microsoft.Web/serverfarms',n+'-plan',{'reserved':True},api='2024-04-01',location=loc,kind='linux',sku={'name':c.get('function_plan_sku','B1')},tags=tags)
    law=add('Microsoft.OperationalInsights/workspaces',n+'-logs',{'sku':{'name':'PerGB2018'},'retentionInDays':30},api='2023-09-01',location=loc,tags=tags)
    ai=add('Microsoft.Insights/components',n+'-insights',{'Application_Type':'web','WorkspaceResourceId':law},api='2020-02-02',location=loc,kind='web',tags=tags,deps=[law])
    package=(ROOT/c.get('package_path','.build/function.zip')).read_bytes(); package_name='logo-'+hashlib.sha256(package).hexdigest()+'.zip'
    app_settings={'FUNCTIONS_WORKER_RUNTIME':'node','FUNCTIONS_EXTENSION_VERSION':'~4','AzureWebJobsStorage__accountName':n+'host','AzureWebJobsStorage__credential':'managedidentity','AzureWebJobsStorage__clientId':client,'AZURE_CLIENT_ID':client,'LOGO_STORAGE_ACCOUNT':catalog['account_name'],'LOGO_CONTAINER':catalog['container_name'],'WEBSITE_RUN_FROM_PACKAGE':f'https://{n}host.blob.core.windows.net/packages/{package_name}','WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID':uai,'APPLICATIONINSIGHTS_CONNECTION_STRING':ref(ai,'2020-02-02','ConnectionString')}
    settings=lambda d:[{'name':k,'value':v} for k,v in d.items()]
    deps=[uai,host_role,ai]+private_endpoints+network_deps+([plan] if not c.get('existing_service_plan_id') else [])+([catalog_role] if catalog_role else [])
    fn=add('Microsoft.Web/sites',n+'-function',{'serverFarmId':plan,'reserved':True,'httpsOnly':True,'publicNetworkAccess':'Disabled','virtualNetworkSubnetId':network['function_subnet_id'],'siteConfig':{'linuxFxVersion':'NODE|22','alwaysOn':True,'minTlsVersion':'1.2','scmMinTlsVersion':'1.2','ftpsState':'Disabled','appSettings':settings(app_settings)}},api='2024-04-01',location=loc,kind='functionapp,linux',identity={'type':'UserAssigned','userAssignedIdentities':{uai:{}}},tags=tags,deps=deps)
    sites=[(n+'-function',fn)]
    if c['mode']=='full':
        web=add('Microsoft.Web/sites',n+'-webapp',{'serverFarmId':plan,'reserved':True,'httpsOnly':True,'publicNetworkAccess':'Disabled','siteConfig':{'linuxFxVersion':'NODE|22-lts','alwaysOn':True,'minTlsVersion':'1.2','scmMinTlsVersion':'1.2','ftpsState':'Disabled','appCommandLine':STARTUP,'appSettings':settings({'DEMO_SERVER_B64':base64.b64encode((ROOT/'webapp/server.js').read_bytes()).decode()})}},api='2024-04-01',location=loc,kind='app,linux',tags=tags,deps=[plan] if not c.get('existing_service_plan_id') else [])
        sites.append((n+'-webapp',web))
    for name,site in sites:
        for policy in ('ftp','scm'):add('Microsoft.Web/sites/basicPublishingCredentialsPolicies',name+'/'+policy,{'allow':False},api='2024-04-01',deps=[site])
    if publish:
        nsg=add('Microsoft.Network/networkSecurityGroups',n+'-publisher-nsg',{'securityRules':[{'name':'DenyInbound','properties':{'priority':100,'direction':'Inbound','access':'Deny','protocol':'*','sourcePortRange':'*','destinationPortRange':'*','sourceAddressPrefix':'*','destinationAddressPrefix':'*'}}]},api='2024-05-01',location=loc,tags=tags)
        nic=add('Microsoft.Network/networkInterfaces',n+'-publisher-nic',{'networkSecurityGroup':{'id':nsg},'ipConfigurations':[{'name':'private','properties':{'subnet':{'id':network['publisher_subnet_id']},'privateIPAllocationMethod':'Dynamic'}}]},api='2024-05-01',location=loc,tags=tags,deps=[nsg]+network_deps)
        vm=add('Microsoft.Compute/virtualMachines',n+'-publisher',{'hardwareProfile':{'vmSize':c.get('publisher_vm_size','Standard_B1s')},'storageProfile':{'imageReference':{'publisher':'Canonical','offer':'0001-com-ubuntu-server-jammy','sku':'22_04-lts-gen2','version':'latest'},'osDisk':{'name':n+'-publisher-os','createOption':'FromImage','caching':'ReadWrite','managedDisk':{'storageAccountType':'Standard_LRS'},'deleteOption':'Delete'}},'osProfile':{'computerName':n+'-publisher','adminUsername':'publisher','linuxConfiguration':{'disablePasswordAuthentication':True,'ssh':{'publicKeys':[{'path':'/home/publisher/.ssh/authorized_keys','keyData':c['publisher_ssh_public_key']}]}}},'networkProfile':{'networkInterfaces':[{'id':nic,'properties':{'deleteOption':'Detach'}}]}},api='2024-07-01',location=loc,identity={'type':'SystemAssigned'},tags=tags,deps=[nic])
        vm_principal=f"[reference('{vm}', '2024-07-01', 'Full').identity.principalId]"
        upload_roles=[]
        for label,scope in [('packages',host+'/blobServices/default/containers/packages')]+([('logos',catalog['account_id']+'/blobServices/default/containers/logos')] if new_catalog else []):
            container_id=rid('Microsoft.Storage/storageAccounts/blobServices/containers',(n+'host/default/packages') if label=='packages' else n+'logos/default/logos')
            upload_roles.append(role(scope,vm_principal,'publisher','contributor',[vm,container_id]))
        payload={'host':n+'host','catalog':catalog['account_name'],'package_name':package_name,'package':base64.b64encode(package).decode(),'assets':{f.name:base64.b64encode(f.read_bytes()).decode() for f in (ROOT/'assets/logos').glob('*.svg')} if new_catalog else {}}
        script="#!/bin/sh\nset -eu\npython3 - <<'LOGO_PUBLISHER'\nnamespace={'__name__':'private_publisher'}\nexec("+repr((ROOT/'scripts/publish.py').read_text())+",namespace)\nnamespace['publish']("+repr(payload)+",True)\nLOGO_PUBLISHER\n"
        add('Microsoft.Compute/virtualMachines/runCommands',n+'-publisher/publish',{'source':{'script':script},'asyncExecution':False,'timeoutInSeconds':1800,'treatFailureAsDeploymentFailure':True},api='2024-07-01',location=loc,deps=[vm]+upload_roles+private_endpoints)
        cleanup=upload_roles+[vm,nic,nsg]+cleanup
    out={'resource_group':rg,'function_id':fn,'function_name':n+'-function','host_storage_name':n+'host','catalog_storage_name':catalog['account_name'],'package_name':package_name,'identity_id':uai,'publisher_resource_ids':cleanup,'publisher_nat_subnet':network['publisher_subnet_id'] if nat else None,'webapp_id':sites[1][1] if len(sites)>1 else None}
    template={'$schema':'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#','contentVersion':'1.0.0.0','resources':resources}
    return template,out

def front_door(c,origins):
    """Separate ARM deployment; existing profile/endpoint are referenced, never redeclared."""
    full=c['mode']=='full'; n=c['name'];sub=c['subscription_id'];loc=c.get('location','westeurope')
    fd={'profile_name':n+'-afd','endpoint_name':n+'-edge','resource_group_name':c.get('resource_group','rg-'+n)} if full else c['existing_front_door']
    prefix=f"/subscriptions/{sub}/resourceGroups/{fd['resource_group_name']}/providers/"
    profile=prefix+'Microsoft.Cdn/profiles/'+fd['profile_name'];endpoint=profile+'/afdEndpoints/'+fd['endpoint_name']
    res=[];approvals=[]
    def add(typ,name,props,deps=(),**kw):
        r={'type':typ,'name':name,'apiVersion':'2024-09-01','properties':props,**kw}
        if deps:r['dependsOn']=list(deps)
        res.append(r)
    if full:
        add('Microsoft.Cdn/profiles',fd['profile_name'],{'originResponseTimeoutSeconds':60},location='global',sku={'name':'Premium_AzureFrontDoor'},tags={'purpose':'svg-logo-demo'})
        add('Microsoft.Cdn/profiles/afdEndpoints',fd['profile_name']+'/'+fd['endpoint_name'],{'enabledState':'Enabled'},deps=[profile],location='global')
    for label,origin in origins.items():
        group=profile+'/originGroups/'+n+'-'+label;oid=group+'/origins/'+label
        health='/logos/health' if label=='logos' else '/health'
        add('Microsoft.Cdn/profiles/originGroups',fd['profile_name']+'/'+n+'-'+label,{'sessionAffinityState':'Disabled','loadBalancingSettings':{'sampleSize':4,'successfulSamplesRequired':3,'additionalLatencyInMilliseconds':50},'healthProbeSettings':{'probePath':health,'probeRequestType':'HEAD','probeProtocol':'Https','probeIntervalInSeconds':60}},deps=[profile] if full else [])
        message=f'svg-logo-{n}-{label}'
        add('Microsoft.Cdn/profiles/originGroups/origins',fd['profile_name']+'/'+n+'-'+label+'/'+label,{'hostName':origin['hostname'],'originHostHeader':origin['hostname'],'httpPort':80,'httpsPort':443,'priority':1,'weight':1000,'enabledState':'Enabled','enforceCertificateNameCheck':True,'sharedPrivateLinkResource':{'privateLink':{'id':origin['id']},'groupId':'sites','privateLinkLocation':loc,'requestMessage':message}},deps=[group])
        props={'originGroup':{'id':group},'supportedProtocols':['Http','Https'],'patternsToMatch':['/logos/*','/static/v2/static/logos/*'] if label=='logos' else ['/*'],'forwardingProtocol':'HttpsOnly','httpsRedirect':'Enabled','linkToDefaultDomain':'Enabled','enabledState':'Enabled'}
        if label=='logos':props['cacheConfiguration']={'queryStringCachingBehavior':'UseQueryString','compressionSettings':{'isCompressionEnabled':True,'contentTypesToCompress':['image/svg+xml','text/html']}}
        add('Microsoft.Cdn/profiles/afdEndpoints/routes',fd['profile_name']+'/'+fd['endpoint_name']+'/'+n+'-'+label,props,deps=[oid]+([endpoint] if full else []))
        approvals.append({'resource_id':origin['id'],'request_message':message})
    if full:
        waf=prefix+'Microsoft.Network/frontDoorWebApplicationFirewallPolicies/'+n+'waf'
        res.append({'type':'Microsoft.Network/frontDoorWebApplicationFirewallPolicies','apiVersion':'2022-05-01','name':n+'waf','location':'global','sku':{'name':'Premium_AzureFrontDoor'},'properties':{'policySettings':{'enabledState':'Enabled','mode':'Prevention'},'managedRules':{'managedRuleSets':[{'ruleSetType':'Microsoft_DefaultRuleSet','ruleSetVersion':'2.1','ruleSetAction':'Block'}]}}})
        add('Microsoft.Cdn/profiles/securityPolicies',fd['profile_name']+'/logo-waf',{'parameters':{'type':'WebApplicationFirewall','wafPolicy':{'id':waf},'associations':[{'domains':[{'id':endpoint}],'patternsToMatch':['/*']}]}},deps=[endpoint,waf])
    return {'$schema':'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#','contentVersion':'1.0.0.0','resources':res},{'resource_group':fd['resource_group_name'],'profile_id':profile,'endpoint_id':endpoint,'approvals':approvals,'route_ids':[endpoint+'/routes/'+n+'-'+k for k in origins],'group_ids':[profile+'/originGroups/'+n+'-'+k for k in origins]}
