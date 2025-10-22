
To launch the cluster:

#Create cluster
kind create cluster --config k8s/kind-cluster.yaml

#Build files
docker build -f api/Dockerfile -t api:latest api
docker build -f frontend/Dockerfile -t frontend:latest frontend


#upload images 
docker tag api:latest emoralesc/api:latest
docker push emoralesc/api:latest

docker tag frontend:latest emoralesc/frontend:latest
docker push emoralesc/frontend:latest

#start the containers
kubectl apply -f k8s/deployment-db.yaml 
kubectl apply -f k8s/deployment-app.yaml 

kubectl apply -f k8s/deployment-frontend.yaml 


#access api externally
kubectl port-forward service/fastapi-service 8000:80