param location string = 'East US'
param aksClusterName string
param acrName string
param sshPublicKey string
param argocdAdminPassword string
param clientId string @secure()
param secret string @secure()

targetScope = 'resourceGroup'

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-03-01' = {
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
      maxNodeCount: 2
      minNodeCount: 1
      profiles: [
        {
          name: 'default'
          minNodeCount: 1
          maxNodeCount: 2
          enabled: true
        }
      ]
    }
    linuxProfile: {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }
    servicePrincipalProfile: {
      clientId: clientId
      secret: secret
    }
    identity: {
      type: 'SystemAssigned'
    }
  }
  dependsOn: [
    acr
  ]
}

resource argocdNamespace 'Microsoft.ContainerService/managedClusters/namespaces@2023-03-01' = {
  name: 'argocd'
  location: location
  dependsOn: [
    aksCluster
  ]
}

resource argocd 'Microsoft.ContainerService/managedClusters/providers/extensions@2023-03-01' = {
  name: aksClusterName-argocd
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

resource ingressController 'Microsoft.ContainerService/managedClusters/providers/extensions@2023-03-01' = {
  name: aksClusterName-nginx-ingress
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
                }
                {
                  containerPort: 443
                }
              ]
              args: [
                '--nginx-configmap=$(POD_NAMESPACE)/ingress-nginx-controller'
                '--udp-services-configmap=$(POD_NAMESPACE)/ingress-nginx-controller'
                '--tcp-services-configmap=$(POD_NAMESPACE)/ingress-nginx-controller'
                '--publish-service=$(POD_NAMESPACE)/ingress-nginx-controller'
                '--annotations-prefix=nginx.ingress.kubernetes.io'
              ]
            }
          ]
        }
      }
    }
  }
}
