Central delivery — Quarkus + Camel Quarkus (sin Camel K en runtime)

Escucha el topic Kafka `trigger` en `central` y llama al EventListener Tekton en `tf`.

Documentación completa (build, Quay, OpenShift):
  README.md  (en este directorio)

Despliegue OpenShift (después de publicar la imagen):
  oc project central
  oc apply -f ../../deployment/central/central-delivery-deployment.yaml

Imagen Quay JVM (mismo repositorio que edge-manager, otro tag):
  bash ../../deployment/build-push-images.sh central-delivery-jvm
  # o con all: bash ../../deployment/build-push-images.sh

Variables de imagen: ../../deployment/sp-demo-images.env.sh

Ya no se usa: ./mvnw clean package -DskipTests -Dquarkus.kubernetes.deploy=true
