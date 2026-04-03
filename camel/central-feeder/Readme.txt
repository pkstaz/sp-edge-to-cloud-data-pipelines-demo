Central feeder — Quarkus + Camel Quarkus (ZIP → MinIO + Kafka on central)

Full docs (build, Quay, Skupper, dataset ZIP):
  README.md  (in this directory)

Deploy on OpenShift (after pushing the image):
  oc project central
  oc apply -f ../../deployment/central/central-feeder-deployment.yaml

Quay JVM image (same repo as edge-manager; tag central-feeder-jvm):
  bash ../../deployment/build-push-images.sh central-feeder-jvm

Image env: ../../deployment/sp-demo-images.env.sh

Service name is "feeder" (Skupper). The deployment YAML includes skupper.io/proxy=http on the Service.

Local dev:
  ./mvnw quarkus:dev

No longer used: ./mvnw clean package -DskipTests -Dquarkus.kubernetes.deploy=true
