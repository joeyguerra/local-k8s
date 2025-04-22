# Create a k3d cluster

```sh
k3d cluster create local --k3s-arg="--disable=traefik@server:0"
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
kubectl create secret generic cloudflared-token --
from-env-file=.env
kubectl apply -f cloudflared-deployment.yml
```