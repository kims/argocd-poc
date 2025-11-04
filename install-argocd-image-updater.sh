kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/main/manifests/install.yaml


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



kubectl create secret generic git-creds   --namespace argocd   --from-file=sshPrivateKey=/home/kimsv/.ssh/flux_app_key

kubectl patch deployment argocd-image-updater -n argocd \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/volumes", "value":[{"name":"git-creds","secret":{"secretName":"git-creds"}}]}, {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts", "value":[{"name":"git-creds","mountPath":"/app/config/ssh","readOnly":true}]}]'

