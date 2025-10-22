
To launch the cluster:


kind create cluster --config k8s/kind-cluster.yaml

docker build -f api/Dockerfile -t api:latest api

docker build -f api/Dockerfile -t frontend:latest frontend




kubectl apply -f k8s/deployment-db.yaml 