#!/bin/bash
MINIKUBE_IP="192.168.49.2"
INT_REGISTRY_HOSTNAME="my-repo.local"
EXT_REGISTRY_HOSTNAME=$(echo $1 | awk -F"/" '{print $1}')

minikube delete

echo '127.0.0.1 localhost' > ~/.minikube/files/etc/hosts
echo '::1 localhost ip6-localhost ip6-loopback' >> ~/.minikube/files/etc/hosts
echo 'fe00::0 ip6-localnet' >> ~/.minikube/files/etc/hosts
echo 'ff00::0 ip6-mcastprefix' >> ~/.minikube/files/etc/hosts
echo 'ff02::1 ip6-allnodes' >> ~/.minikube/files/etc/hosts
echo 'ff02::2 ip6-allrouters' >> ~/.minikube/files/etc/hosts
echo "$(minikube ip) control-plane.minikube.internal" >> ~/.minikube/files/etc/hosts
echo "$(minikube ip) ${INT_REGISTRY_HOSTNAME}" >> ~/.minikube/files/etc/hosts
echo "172.18.10.100 ${EXT_REGISTRY_HOSTNAME}" >> ~/.minikube/files/etc/hosts

minikube start  --static-ip $MINIKUBE_IP  --insecure-registry="${MINIKUBE_IP}:30500" --insecure-registry="172.18.10.100"
sed -i "s/\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}/${MINIKUBE_IP}/" externportal/values-poc.yaml
minikube addons enable registry
kubectl -n kube-system patch svc registry \
  --type='json' \
  -p='[
    {"op":"replace","path":"/spec/type","value":"NodePort"},
    {"op":"replace","path":"/spec/ports/0/nodePort","value":30500},
    {"op":"replace","path":"/spec/ports/0/port","value":80},
    {"op":"replace","path":"/spec/ports/0/targetPort","value":5000}
  ]'


MINIKUBE_COMMAND_CHAIN="
docker login $EXT_REGISTRY_HOSTNAME
docker pull $1
docker tag $1 192.168.49.2:30500/ui:dev-latest
docker push  192.168.49.2:30500/ui:dev-latest 
"

# Execute the entire command chain on Minikube
minikube ssh -- "${MINIKUBE_COMMAND_CHAIN}"


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

sleep 20 #sleep for sealed secrets bootup

K_VERSION=$(curl -sL https://api.github.com/repos/bitnami/sealed-secrets/releases/latest | grep '"tag_name"' | awk -F': ' '{print $2}' | tr -d '",'); [ -x /usr/local/bin/kubeseal ] || { curl -sLO "https://github.com/bitnami/sealed-secrets/releases/download/${K_VERSION}/kubeseal-linux-amd64" && sudo install -m 755 kubeseal-linux-amd64 /usr/local/bin/kubeseal && rm kubeseal-linux-amd64; } 

