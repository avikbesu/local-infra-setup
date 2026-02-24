
# add airflow charts repo
helm repo add apache-airflow https://airflow.apache.org 
helm repo update

# how to download charts
helm pull apache-airflow/airflow --untar --destination ./chart

# install airflow

kubectl apply -f airflow/dags_pv.yaml -n airflow
kubectl apply -f airflow/dags_pvc.yaml -n airflow

helm install airflow apache-airflow/airflow \
  --namespace airflow --create-namespace \
  --set executor=LocalExecutor \
  --set dags.persistence.enabled=true \
  --set dags.persistence.existingClaim=dags-pvc \
  --set dags.gitSync.enabled=false

# port forwarding not working from k9s
kubectl port-forward airflow-webserver-7d55647b5d-lvhzl 8090:8080 -n airflow

#uninstall airflow
helm uninstall airflow --namespace airflow
# check the pods
kubectl get pods  

# check the services
kubectl get services 

# check the deployments
kubectl get deployments

# check the events
kubectl get events

# check the nodes
kubectl get nodes

# check the config
kubectl config view

