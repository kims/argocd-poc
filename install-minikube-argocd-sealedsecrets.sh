#!/bin/bash
minikube delete
minikube start 

# Install ArgoCD
kubectl create namespace argocd

helm repo add argo https://argoproj.github.io/argo-helm &>/dev/null
helm repo update &>/dev/null
helm install argocd argo/argo-cd --namespace argocd --wait

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s >/dev/null

[ -x /usr/local/bin/argocd ] || { sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && sudo chmod +x /usr/local/bin/argocd; } && argocd version

LATEST=$(curl -sL https://api.github.com/repos/kubernetes/kubernetes/releases/latest | grep '"tag_name"' | awk -F': ' '{print $2}' | tr -d '",'); INSTALLED=$(command -v kubectl &> /dev/null && kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion');
if [[ "${INSTALLED}" != "${LATEST}" ]]; then curl -sLO "https://storage.googleapis.com/kubernetes-release/release/${LATEST}/bin/linux/amd64/kubectl" && chmod +x ./kubectl && sudo mv ./kubectl /usr/local/bin/kubectl; fi


# Install Sealed-secrets
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
  -keyout sealed-secrets.key \
  -out sealed-secrets.crt \
  -subj "/CN=sealed-secrets"


kubectl -n kube-system create secret tls sealed-secrets-custom-key \
  --cert=sealed-secrets.crt \
  --key=sealed-secrets.key

kubectl -n kube-system label secret sealed-secrets-custom-key \
  sealedsecrets.bitnami.com/sealed-secrets-key=active

rm -f sealed-secrets.crt sealed-secrets.key

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm install sealed-secrets -n kube-system \
  --create-namespace \
  --set-string fullnameOverride=sealed-secrets-controller \
  sealed-secrets/sealed-secrets

K_VERSION=$(curl -sL https://api.github.com/repos/bitnami/sealed-secrets/releases/latest | grep '"tag_name"' | awk -F': ' '{print $2}' | tr -d '",'); [ -x /usr/local/bin/kubeseal ] || { curl -sLO "https://github.com/bitnami/sealed-secrets/releases/download/${K_VERSION}/kubeseal-linux-amd64" && sudo install -m 755 kubeseal-linux-amd64 /usr/local/bin/kubeseal && rm kubeseal-linux-amd64; } && kubeseal version

sleep 10

kubectl create secret generic dev1-db-pass --from-literal=username=dev1 --from-literal=password=dev123 --dry-run=client -o json | kubeseal --namespace=dev1 --format=yaml > externportal/templates/SealedSecret.db-pass.yaml

git add *; git commit -m "new"; git push
