import sys
import logging
import requests
import json
import argparse

class EnterpriseAppClient:
  def __init__(self, tenant_id, spn_id, spn_key, app_name):
    self._tenant_id = tenant_id
    self._token = self._get_access_token(tenant_id, spn_id, spn_key)
    self._header = {"Authorization": f"Bearer {self._token}"}
    self._base_url = "https://graph.microsoft.com/beta"
    self._app_name = app_name
    self._app_definition = self._find_app()
    self._app_object_id = self._app_definition['objectId']
    logger.info(f"Initialized enterprise app: {self._app_definition}")

  @classmethod
  def _get_access_token(cls, tenant_id, spn_id, spn_key):
    post_data = {'client_id': spn_id,
                'scope': 'https://graph.microsoft.com/.default',
                'client_secret': spn_key,
                'grant_type': 'client_credentials'}
    initial_header = {'Content-type': 'application/x-www-form-urlencoded'}
    res = requests.post(f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token", data=post_data, headers=initial_header)
    res.raise_for_status()
    return res.json().get("access_token")

  def _find_app(self):
    res = requests.get(
      f"{self._base_url}/servicePrincipals?$filter=startswith(displayName,'{self._app_name}')&$count=true&$top=1",
      headers=self._header
    )
    res.raise_for_status()

    value = res.json().get("value")

    if len(value) == 0:
      raise ValueError(f"Failed to find app: {self._app_name}")
    
    group = value[0]

    return {
      "appId": group.get("appId"),
      "roleId": group.get("appRoles")[0].get("id"),
      "objectId": group.get("id")
    }
  
  def list_assignments(self):
    def extract_dict(resp_list):
        return [{
            "principalDisplayName": grp.get("principalDisplayName").lower(),
            "principalId": grp.get("principalId"),
            "assignmentId": grp.get("id")
            } for grp in resp_list]
            
    all_data = []
    req_url = f"{self._base_url}/servicePrincipals/{self._app_object_id}/appRoleAssignedTo"

    while req_url:
      res = requests.get(req_url, headers=self._header)
      res.raise_for_status()
      
      data = res.json()
      all_data.extend(extract_dict(data['value']))

      # Check if there are more pages
      req_url = data.get('@odata.nextLink')

    return all_data
  
  def remove_assignment(self, assignment_id):
    logger.info(f"remove_assignment: {assignment_id=}")
    res = requests.delete(
      f"{self._base_url}/servicePrincipals/{self._app_object_id}/appRoleAssignedTo/{assignment_id}",
      headers=self._header
    )

    res.raise_for_status()

  def add_assignment(self, principal_id):
    post_data = {
        "principalId": principal_id,
        "resourceId": self._app_object_id,
        "appRoleId": self._app_definition.get("roleId")
    }

    logger.info(f"add_assignment: {post_data=}")

    res = requests.post(
      f"{self._base_url}/servicePrincipals/{self._app_object_id}/appRoleAssignedTo",
      headers=self._header,
      json=post_data
    )

    res.raise_for_status()

  def set_assignment(self, assignment_ids):
    current = {
      d['principalId'] : d  
      for d in self.list_assignments()
    }

    assignment_ids = set(assignment_ids)

    # add
    for a in assignment_ids:
      if a not in current:
        self.add_assignment(a)
    
    # remove
    for a, d in current.items():
      if a not in assignment_ids:
        self.remove_assignment(d['assignmentId'])

if __name__ == "__main__":
  arg_parser = argparse.ArgumentParser()
  arg_parser.add_argument("--app_name", help="Enterprise Application Name", required=True)
  arg_parser.add_argument("--tenant_id", help="Azure Tenant Id", required=True)
  arg_parser.add_argument("--spn_id", help="Deployment SPN Id", required=True)
  arg_parser.add_argument("--spn_key", help="Deployment SPN Secret Key", required=True)
  arg_parser.add_argument("--json_file_name", help="JSON file containing all groups", default=".aad_state.json", required=False)
  arg_parser.add_argument("--verbose", help="verbose logs", default=False, type=bool, required=False)
  args = vars(arg_parser.parse_args())

  logging.basicConfig(
    stream=sys.stderr,
    level=(logging.DEBUG if args['verbose'] else logging.INFO),
    format='%(asctime)s %(levelname)s %(threadName)s [%(name)s] %(message)s'
  )

  logger = logging.getLogger('sync')

  ec = EnterpriseAppClient(
    tenant_id = args['tenant_id']
    ,spn_id = args['spn_id']
    ,spn_key = args['spn_key']
    ,app_name = args['app_name']
  )

  with open(args['json_file_name'], 'r') as f:
    aad_state = json.load(f)['aad_state']['value']
    groups_ids = list(aad_state['groups_by_id'])

  ec.set_assignment(groups_ids)
