tensorflow.svg — logo TensorFlow (Wikimedia Commons: https://commons.wikimedia.org/wiki/File:Tensorflow_logo.svg).

OpenShift Topology resuelve el icono con app.openshift.io/runtime y, si no hay recurso icon-<runtime>, con app.kubernetes.io/name (código en openshift/console transform-utils.ts → catalog-item-icon). No existe icon-tensorflow en la consola; por eso tf-server.yaml usa name=python solo como respaldo visual (ecosistema ML). El despliegue lógico sigue siendo tf-server (metadata.name + label app).
