#/bin/bash

# verify that kind is installed, if not install it
if ! command -v kind &> /dev/null
then
    echo "kind could not be found"
    echo "installing kind"
    # For AMD64 / x86_64
    [ $(uname -m) = x86_64 ] && curl -Lo ~/kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64
    # For ARM64
    [ $(uname -m) = aarch64 ] && curl -Lo ~/kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-arm64
    chmod +x ~/kind
    sudo mv ~/kind /usr/local/bin/kind
else
    echo "kind is already installed, version: $(kind version)"
fi

# verify that kubectl is installed, if not install it
if ! command -v kubectl &> /dev/null
then
    echo "kubectl could not be found"
    echo "installing kubectl"
    sudo apt-get update && sudo apt-get install -y apt-transport-https
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubectl
else
    echo "kubectl is already installed, version: $(kubectl version --client)"
fi

# verify that helm is installed, if not install it
if ! command -v helm &> /dev/null
then
    echo "helm could not be found"
    echo "installing helm"
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
else
    echo "helm is already installed, version: $(helm version)"
fi

# verify and install k9s
if ! command -v k9s &> /dev/null
then
    echo "k9s could not be found"
    echo "installing k9s"
    curl -sS https://webinstall.dev/k9s | bash
else
    echo "k9s is already installed, version: $(k9s version)"
fi

