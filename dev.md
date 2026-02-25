
## Prerequisites

```bash
# install kubectl
curl -LO "https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl"; 
chmod +x kubectl; 
sudo mv kubectl /usr/local/bin/;

# install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64;
chmod +x ./kind;
sudo mv ./kind /usr/local/bin/kind;

# install helm 
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash;
```

## Useful Comamnds

### Kind Commands

```bash
# Create a cluster
kind create cluster --name kind-cluster 

# List the clusters
kind get clusters

# Check the cluster
kubectl cluster-info --context kind-kind-cluster

# Delete the cluster
kind delete cluster --name kind-cluster
```

### Kubectl Commands
```bash
kubectl create deployment hello-node --image=hello-world
kubectl get deployments
kubectl get pods
kubectl get events
kubectl config view
kubectl get nodes
kubectl expose deployment hello-node --type=LoadBalancer --port=8080
kubectl get services
kubectl scale deployment hello-node --replicas=4
kubectl delete service hello-node 
kubectl delete deployment hello-node

# kubectl run
kubectl run hello-node --image=hello-world --port=8080

# kubectl apply
kubectl apply -f https://k8s.io/examples/application/deployment.yaml
kubectl get pods
```