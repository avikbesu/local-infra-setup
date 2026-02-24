
# Create a cluster
kind create cluster --name kind-cluster 

# List the clusters
kind get clusters

# Check the cluster
kubectl cluster-info --context kind-kind-cluster



# Delete the cluster
kind delete cluster --name kind-cluster


# kubectl

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