#!/usr/bin/env python3
"""Review/approve this Terraform stack's Front Door private app connections."""
import argparse,json,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'azure-cli'))
from deploy import approve
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--approve',action='store_true');p.add_argument('--terraform-dir',default='terraform',help='Terraform root containing the deployment state');a=p.parse_args()
items=json.loads(subprocess.check_output(['terraform','-chdir='+a.terraform_dir,'output','-json','front_door_private_link_approvals'],text=True))
approve(items,a.approve)
