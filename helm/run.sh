#!/bin/bash

function start() {
  echo "Starting all the services in cluster"
  ./install_all.sh
  ./start_cluster.sh
}

function status() {
  echo "Checking the status of the created cluster"
  kubectl get pods
  kubectl get services
  kubectl get deployments
  kubectl get events
  kubectl get nodes
  kubectl config view
}

function stop() {
  echo "Stopping all the services in cluster"
  # uninstall airflow
  helm uninstall airflow --namespace airflow
  # delete cluster
  kind delete cluster --name kind-cluster
}

# check argument 1st argument
if [ -z "$1" ]; then
  echo "Usage: $0 <start|stop|status>"
  exit 1
fi
cmd=$1

if [ -n "$2" ]; then
  arg=$2
fi

# compare cmd & arg values using use case
case $cmd in
  "start")
    start
    ;;
  "stop")
    stop
    ;;
  "status")
    status
    ;;
  *)
    echo "Usage: $0 <start|stop|status>"
    exit 1
    ;;
esac


