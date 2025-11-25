# Run a Local Kubenernetes Cluster

I run [k3ds](https://k3d.io/stable/) locally on my Mac Mini and serve up public traffic via my CloudFlare account using `cloudflared`.

- Create a cluster
- Setup zero trust in CloudFlare
- Configure a tunnel to point a locally running webserve
    e.g. http://jbot-website-service:8080
- Deploy [cloudlared-deployment.yml](cloudflared-deployment.yml)
- Deploy some apps
- Do a bunch of POCs to test out your ideas.

# Create a k3d cluster

```sh
k3d cluster create local-canary --k3s-arg="--disable=traefik@server:0" --image rancher/k3s
```

# Detele a k3d cluster

```sh
k3d cluster delete local
```

Where `local` is the name of the cluster.

# Deploy CloudFlared Deployment

When running in a k3d cluster, you have to get the images into it's own registry. You can do that by executing (where `local` is the ccluster name):

```sh
docker pull cloudflare/cloudflared:latest
k3d image import cloudflare/cloudflared:latest -c local
```

```sh
kubectl create secret generic cloudflared-token --from-env-file=.env
kubectl apply -f cloudflared-deployment.yml
kubectl create secrete generic discord-token --from-literal=HUBOT_DISCORD_TOKEN='<value>'
kubectl create secret generic cookie-secret --from-literal=COOKIE_SECRET='<value>' -n default
KUBE_CONTEXT=k3d-local KUBE_CLUSTER=local ./deploy-all-apps.sh
```

# Upgrade K3d

```sh
brew upgrade k3d
kubectl get all --all-namespaces -o yaml
kubectl get all --all-namespaces -o yaml > backup.yaml
 ```