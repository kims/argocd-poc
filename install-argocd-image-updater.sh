kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  registries.conf: |
    registries:
      - name: local-registry
        api_url: http://192.168.49.2:30500
        prefix: 192.168.49.2:30500
        insecure: true
EOF




cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        log
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        hosts {
           192.168.49.1 host.minikube.internal
           fallthrough
        }
        forward . 8.8.8.8 {
           max_concurrent 1000
        }
        cache 30 {
           disable success cluster.local
           disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
EOF


kubectl create secret generic git-creds   --namespace argocd   --from-file=sshPrivateKey=/home/kimsv/.ssh/flux_app_key

kubectl patch deployment argocd-image-updater -n argocd \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/volumes", "value":[{"name":"git-creds","secret":{"secretName":"git-creds"}}]}, {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts", "value":[{"name":"git-creds","mountPath":"/app/config/ssh","readOnly":true}]}]'

