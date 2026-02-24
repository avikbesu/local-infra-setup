
# pass cluster name as argument
# if no argument is passed, use default cluster name
CLUSTER_NAME="${1:-kind-cluster}"

# create single node cluster with kind if it is not already created
if ! kind get clusters | grep -q $CLUSTER_NAME
then
  echo "kind cluster not found, creating cluster: $CLUSTER_NAME"

  # create a single node cluster using config file if available
  if [ -f kind-config.yaml ]
  then
    echo "Creating cluster using config file kind-config.yaml"
    kind create cluster --name $CLUSTER_NAME --config kind-config.yaml
  else
    kind create cluster --name $CLUSTER_NAME
  fi
else
  echo "kind cluster already exists, listing all clusters: $(kind get clusters | paste -sd ', ')"
fi


# kubectl cluster-info --context kind-$CLUSTER_NAME
# kubectl get nodes


# check whether airflow deployed in airflow namespace
if kubectl get pods -n airflow | grep -q airflow-webserver
then
  echo "Airflow is already deployed in airflow namespace"
else
  echo "Airflow is not deployed in airflow namespace"
  kubectl create namespace airflow
  kubectl apply -f airflow/dags_pv.yaml -n airflow
  kubectl apply -f airflow/dags_pvc.yaml -n airflow
  helm upgrade --install airflow apache-airflow/airflow \
    --namespace airflow --create-namespace \
    -f airflow/values.yaml \
    
    # --set executor=LocalExecutor \
    # --set dags.persistence.enabled=true \
    # --set dags.persistence.existingClaim=dags-pvc \
    # --set dags.gitSync.enabled=false

fi

# get airflow-executor pod name
AIRFLOW_EXECUTOR_POD=$(kubectl get pods -n airflow | grep airflow-webserver | awk '{print $1}')
echo "Airflow executor pod name: $AIRFLOW_EXECUTOR_POD"
kubectl port-forward $AIRFLOW_EXECUTOR_POD 8090:8080 -n airflow &

echo "Airflow webserver is running on http://localhost:8090"