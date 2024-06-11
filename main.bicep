param sshRSAPublicKey string
param location string = 'East US'
param resourceGroupName string
param aksClusterName string
param acrName string
param argocdAdminPassword string

targetScope = 'resourceGroup'

resource azapiResourceSshPublicKey 'Microsoft.Compute/sshPublicKeys@2022-11-01' = {
  name: 'sshKey'
  location: location
}

resource azapiResourceActionSshPublicKeyGen 'Microsoft.Compute/sshPublicKeys/generateKeyPair@2022-11-01' = {
  name: '${azapiResourceSshPublicKey.name}/generateKeyPair'
  method: 'POST'
  parent: azapiResourceSshPublicKey
}
output keyData string = azapiResourceActionSshPublicKeyGen.properties['publicKey']

resource acr 'Microsoft.ContainerRegistry/registries@2021-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2021-06-01' = {
  name: aksClusterName
  location: location
  tags: {
    environment: 'Production'
  }
  properties: {
    kubernetesVersion: '1.21.2'
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 3
        vmSize: 'Standard_DS2_v2'
        osType: 'Linux'
        maxPods: 30
      }
    ]
    networkProfile: {
      loadBalancerSku: 'Standard'
      outboundType: 'loadBalancer'
    }
    addonProfiles: {
      kubeDashboard: {
        enabled: true
      }
    }
    enableAutoScaling: true
    autoScalerProfile: {
      balanceSimilarNodeGroups: true
      maxNodeCount: 5
      minNodeCount: 1
      profiles: [
        {
          name: 'default'
          minNodeCount: 1
          maxNodeCount: 5
          enabled: true
        }
      ]
    }
    linuxProfile: {
      adminUsername: 'aksadmin'
      ssh: {
        publicKeys: [
          {
            keyData: azapiResourceActionSshPublicKeyGen.properties['publicKey']
          }
        ]
      }
    }
    servicePrincipalProfile: {
      clientId: 'CLIENT_ID'
      secret: 'CLIENT_SECRET'
    }
    identity: {
      type: 'SystemAssigned'
    }
  }
  dependsOn: [
    acr
  ]
}

resource argocdNamespace 'Microsoft.ContainerService/managedClusters/namespaces@2021-06-01' = {
  name: 'argocd'
  location: location
  dependsOn: [
    aksCluster
  ]
}

resource argocd 'Microsoft.ContainerService/managedClusters/providers/extensions@2021-06-01' = {
  name: '${aksClusterName}-argocd'
  location: location
  properties: {
    apiVersion: 'apps/v1'
    kind: 'Deployment'
    metadata: {
      name: 'argocd-server'
      namespace: argocdNamespace.name
      labels: {
        app: 'argocd-server'
      }
    }
    spec: {
      replicas: 1
      selector: {
        matchLabels: {
          app: 'argocd-server'
        }
      }
      template: {
        metadata: {
          labels: {
            app: 'argocd-server'
          }
        }
        spec: {
          containers: [
            {
              name: 'argocd-server'
              image: 'argoproj/argocd:v2.0.3'
              ports: [
                {
                  containerPort: 8080
                }
              ]
              env: [
                {
                  name: 'ARGOCD_USERNAME'
                  value: 'admin'
                }
                {
                  name: 'ARGOCD_PASSWORD'
                  value: argocdAdminPassword
                }
              ]
            }
          ]
        }
      }
    }
  }
}

resource ingressController 'Microsoft.ContainerService/managedClusters/providers/extensions@2021-06-01' = {
  name: '${aksClusterName}-nginx-ingress'
  location: location
  properties: {
    apiVersion: 'apps/v1'
    kind: 'Deployment'
    metadata: {
      name: 'nginx-ingress-controller'
      namespace: 'kube-system'
      labels: {
        app: 'nginx-ingress'
      }
    }
    spec: {
      replicas: 2
      selector: {
        matchLabels: {
          app: 'nginx-ingress'
        }
      }
      template: {
        metadata: {
          labels: {
            app: 'nginx-ingress'
          }
        }
        spec: {
          containers: [
            {
              name: 'nginx-ingress-controller'
              image: 'k8s.gcr.io/ingress-nginx/controller:v1.0.4'
              ports: [
                {
                  containerPort: 80
                },
                {
                  containerPort: 443
                }
              ]
              args: [
                '--nginx-configmap=$(POD_NAMESPACE)/ingress-nginx-controller',
                '--udp-services-configmap=$(POD_NAMESPACE)/ingress-nginx-controller',
                '--tcp-services-configmap=$(POD_NAMESPACE)/ingress-nginx-controller',
                '--publish-service=$(POD_NAMESPACE)/ingress-nginx-controller',
                '--annotations-prefix=nginx.ingress.kubernetes.io',
              ]
            }
          ]
        }
      }
    }
  }
}
