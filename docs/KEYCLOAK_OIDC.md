# RKE2 API server OIDC with Keycloak

Status: written from documentation and not tested against a live Keycloak.
The Helm values in `examples/keycloak-values.yaml` were rendered with
`helm template` and passed kubeconform, nothing more.

## Keycloak side

1. Create a realm, for example `platform`.
2. If users live in a directory, add a user federation of type `ldap`
   (see the settings listed at the bottom of `examples/keycloak-values.yaml`).
3. Create a client `kubernetes`, client authentication on, standard flow on,
   valid redirect URI `http://localhost:8000` (kubelogin default).
4. Add a mapper of type "Group Membership" with token claim name `groups`,
   full group path off, added to the ID token.
5. Add a mapper so `preferred_username` is in the ID token (default in most
   realms).

## RKE2 side

Add the kube-apiserver flags on server nodes. With the Ansible role, set:

```yaml
airgap_rke2_apiserver_args:
  - oidc-issuer-url=https://keycloak.example.internal/realms/platform
  - oidc-client-id=kubernetes
  - oidc-username-claim=preferred_username
  - oidc-groups-claim=groups
  - oidc-username-prefix=oidc:
  - oidc-groups-prefix=oidc:
  - oidc-ca-file=/etc/rancher/rke2/keycloak-ca.crt
```

That renders into `/etc/rancher/rke2/config.yaml` as `kube-apiserver-arg`.
Copy the CA that signed the Keycloak certificate to the path in
`oidc-ca-file` before restarting `rke2-server`. The API server must be able to
reach the issuer URL, which is a hard requirement even on a closed network, so
Keycloak must run inside it.

## RBAC

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-platform-admins
subjects:
  - kind: Group
    name: "oidc:platform-admins"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

## Client side

Use the `kubelogin` kubectl plugin with the issuer, client id, and CA file.

## Known gaps

Token lifetime, refresh behavior, and group-claim size limits with large
directories have not been tried. Check them before relying on this.
