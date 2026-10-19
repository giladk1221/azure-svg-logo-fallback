import ast,copy,importlib.util,json,pathlib,sys,unittest
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'azure-cli'))
import template,deploy
BASE={'name':'svgtest000001','subscription_id':'22222222-2222-2222-2222-222222222222','mode':'full','publish_artifacts':False}
class CliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import subprocess
        subprocess.run([sys.executable,str(ROOT/'scripts/package.py')],check=True,capture_output=True)
    def build(self,mode='full',**kw):
        c={**BASE,'mode':mode,**kw}
        if mode=='existing_front_door':c['existing_front_door']={'profile_name':'shared','resource_group_name':'edge','endpoint_name':'shared-edge'}
        return c,*template.build(c)
    def test_three_modes_private_workloads(self):
        for mode,count in [('full',2),('existing_front_door',1),('function_only',1)]:
            c,t,info=self.build(mode)
            sites=[r for r in t['resources'] if r['type']=='Microsoft.Web/sites']
            self.assertEqual(len(sites),count)
            for r in sites:self.assertEqual(r['properties']['publicNetworkAccess'],'Disabled')
            for r in t['resources']:
                if r['type']=='Microsoft.Storage/storageAccounts':
                    self.assertFalse(r['properties']['allowSharedKeyAccess']);self.assertEqual(r['properties']['publicNetworkAccess'],'Disabled')
    def test_front_door_direct_private_function_and_webapp(self):
        c,t,info=self.build()
        edge,out=template.front_door(c,{'logos':{'id':info['function_id'],'hostname':'function.azurewebsites.net'},'webapp':{'id':info['webapp_id'],'hostname':'webapp.azurewebsites.net'}})
        origins=[r for r in edge['resources'] if r['type'].endswith('/origins')]
        self.assertEqual(len(origins),2)
        self.assertTrue(all(r['properties']['sharedPrivateLinkResource']['groupId']=='sites' for r in origins))
        routes=[r for r in edge['resources'] if r['type'].endswith('/routes')]
        logos=next(r for r in routes if r['name'].endswith('-logos'))
        web=next(r for r in routes if r['name'].endswith('-webapp'))
        self.assertEqual(logos['properties']['cacheConfiguration']['queryStringCachingBehavior'],'UseQueryString')
        self.assertNotIn('cacheConfiguration',web['properties'])
    def test_existing_front_door_is_not_redeclared(self):
        c,t,info=self.build('existing_front_door')
        edge,out=template.front_door(c,{'logos':{'id':info['function_id'],'hostname':'function.azurewebsites.net'}})
        types=[r['type'] for r in edge['resources']]
        self.assertNotIn('Microsoft.Cdn/profiles',types);self.assertNotIn('Microsoft.Cdn/profiles/afdEndpoints',types)
        self.assertFalse(any('Firewall' in x or 'securityPolicies' in x for x in types))
        self.assertEqual(out['resource_group'],'edge')
    def test_reused_catalog_and_plan_not_created(self):
        cat={'account_id':'/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Storage/storageAccounts/sharedlogos','account_name':'sharedlogos','container_name':'brand-assets'}
        c,t,info=self.build('function_only',existing_catalog=cat,existing_service_plan_id='/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Web/serverfarms/shared')
        self.assertEqual(len([r for r in t['resources'] if r['type']=='Microsoft.Storage/storageAccounts']),1)
        self.assertFalse(any(r['type']=='Microsoft.Web/serverfarms' for r in t['resources']))
        self.assertEqual(info['catalog_storage_name'],'sharedlogos')
    def test_publisher_private_and_failures_fail_deployment(self):
        c,t,info=self.build(publish_artifacts=True,publisher_ssh_public_key='ssh-ed25519 PUBLIC_TEST_ONLY',publisher_vm_size='Standard_B2ls_v2')
        vm=next(r for r in t['resources'] if r['type']=='Microsoft.Compute/virtualMachines')
        self.assertEqual(vm['properties']['hardwareProfile']['vmSize'],'Standard_B2ls_v2')
        nic=next(r for r in t['resources'] if r['type']=='Microsoft.Network/networkInterfaces')
        self.assertNotIn('publicIPAddress',nic['properties']['ipConfigurations'][0]['properties'])
        run=next(r for r in t['resources'] if r['type'].endswith('/runCommands'))
        self.assertTrue(run['properties']['treatFailureAsDeploymentFailure']);self.assertFalse(run['properties']['asyncExecution'])
        script=run['properties']['source']['script'].split("python3 - <<'LOGO_PUBLISHER'\n")[1].rsplit('\nLOGO_PUBLISHER',1)[0]
        ast.parse(script)
        self.assertTrue(info['publisher_nat_subnet'].endswith('/subnets/publisher'))
    def test_all_workload_dependencies_resolve_to_declared_resources(self):
        # Includes extension-role scopes and nested containers/endpoint DNS groups.
        c,t,info=self.build(publish_artifacts=True,publisher_ssh_public_key='ssh-ed25519 PUBLIC_TEST_ONLY')
        prefix='/subscriptions/'+c['subscription_id']+'/resourceGroups/'+info['resource_group']+'/providers/'
        ids=[]
        for r in t['resources']:
            if 'scope' in r:ids.append(prefix+r['scope']+'/providers/'+r['type']+'/'+r['name'])
            else:
                types=r['type'].split('/');names=r['name'].split('/')
                self.assertEqual(len(types)-1,len(names),r['name'])
                ids.append(prefix+types[0]+'/'+'/'.join(x for pair in zip(types[1:],names) for x in pair))
        self.assertEqual(len(ids),len(set(ids)))
        for r in t['resources']:
            for dep in r.get('dependsOn',[]):self.assertIn(dep,ids,(r['name'],dep))
    def test_route_conflict_detection_preserves_default_route(self):
        def route(name,patterns):return {'name':name,'properties':{'patternsToMatch':patterns}}
        self.assertEqual(deploy.route_conflicts([route('default',['/*'])],'demo'),[])
        self.assertEqual(deploy.route_conflicts([route('other',['/logos/*'])],'demo'),['other'])
        self.assertEqual(deploy.route_conflicts([route('demo-logos',['/logos/*'])],'demo'),[])
    def test_approval_targets_only_matching_request(self):
        vals=[{'id':'matching','properties':{'privateLinkServiceConnectionState':{'description':'demo-only','status':'Pending'}}},{'id':'unrelated','properties':{'privateLinkServiceConnectionState':{'description':'other','status':'Pending'}}}]
        approved={'properties':{'privateLinkServiceConnectionState':{'status':'Approved'}}}
        with patch.object(deploy,'rest_get',side_effect=[{'value':vals},approved]),patch.object(deploy,'az') as az:
            deploy.approve([{'resource_id':'resource','request_message':'demo-only'}],True)
            self.assertEqual(az.call_count,1)
            args=az.call_args.args
            self.assertEqual(args[args.index('--url')+1],'https://management.azure.commatching?api-version=2024-04-01')
            self.assertNotIn('unrelated',str(args))
            body=json.loads(args[args.index('--body')+1])
            self.assertEqual(body['properties']['privateLinkServiceConnectionState']['status'],'Approved')
            self.assertNotIn('privateEndpoint',body['properties'])
    def test_approval_resumes_approving_without_duplicate_write(self):
        item={'id':'owned','properties':{'privateLinkServiceConnectionState':{'description':'demo-only','status':'Approving'}}}
        approved={'properties':{'privateLinkServiceConnectionState':{'status':'Approved'}}}
        with patch.object(deploy,'rest_get',side_effect=[{'value':[item]},approved]),patch.object(deploy,'az') as az:
            deploy.approve([{'resource_id':'resource','request_message':'demo-only'}],True)
            az.assert_not_called()
    def test_approval_checks_state_after_transient_server_error(self):
        item={'id':'owned','properties':{'privateLinkServiceConnectionState':{'description':'demo-only','status':'Pending'}}}
        approving={'properties':{'privateLinkServiceConnectionState':{'status':'Approving'}}}
        approved={'properties':{'privateLinkServiceConnectionState':{'status':'Approved'}}}
        with patch.object(deploy,'rest_get',side_effect=[{'value':[item]},approving,approved]),patch.object(deploy,'az',side_effect=RuntimeError('Internal Server Error')) as az,patch.object(deploy.time,'sleep'):
            deploy.approve([{'resource_id':'resource','request_message':'demo-only'}],True)
            self.assertEqual(az.call_count,1)
    def test_render_each_mode_needs_no_azure_or_terraform(self):
        import tempfile,contextlib,io
        for mode in ('full','existing_front_door','function_only'):
            c={**BASE,'name':'render'+mode.replace('_',''),'mode':mode}
            c['name']={'full':'renderfull','existing_front_door':'renderexisting','function_only':'renderfunction'}[mode]
            if mode=='existing_front_door':c['existing_front_door']={'profile_name':'shared','resource_group_name':'edge','endpoint_name':'edge'}
            with tempfile.TemporaryDirectory() as tmp:
                config=pathlib.Path(tmp)/'config.json';config.write_text(json.dumps(c))
                with patch.object(sys,'argv',['deploy.py','render','--config',str(config)]),patch.object(deploy,'az',side_effect=AssertionError('render must be offline')),contextlib.redirect_stdout(io.StringIO()):
                    deploy.main()
                rendered=json.loads((ROOT/'.deploy'/c['name']/'workload.json').read_text())
                self.assertTrue(rendered['resources'])
    def test_invalid_mode_rejected(self):
        with self.assertRaises(ValueError):template.build({**BASE,'mode':'unknown'})
if __name__=='__main__':unittest.main()
