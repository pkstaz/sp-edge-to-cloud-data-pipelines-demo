Edge Manager — Quarkus + Camel Quarkus (sin Camel K en runtime)

Resumen rápido:
- Lee modelos del bucket S3 {edge}-ready en MinIO central (p. ej. edge1-ready).
- Los copia a production en MinIO edge y envía MQTT al detectar saved_model.pb.

Documentación completa (GraalVM nativo, Docker, Quay, OpenShift):
  README.md  (en este directorio)

Despliegue OpenShift (después de publicar la imagen):
  oc project edge1
  oc apply -f ../../deployment/edge/edge-manager-deployment.yaml

Imagen Quay JVM (una vez; no va en install-demo-steps.sh):
  bash ../../deployment/build-push-images.sh edge-manager-jvm
  # o: bash ../../deployment/build-push-images.sh   (por defecto = JVM)
  # Nativo (backlog): edge-manager-native — ver BACKLOG.md

Ya no se usa: ./mvnw ... -Dquarkus.kubernetes.deploy=true (extensión openshift retirada del pom).
