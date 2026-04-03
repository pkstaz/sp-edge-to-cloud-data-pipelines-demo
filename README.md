# rhods-transfer-learning

This project contains resources to showcase a full circle continuous motion of data to capture training data, train new ML models, deploy them, serve them, and expose the service for clients to send inference requests.

   > [!INFO]
   > This project has been updated based on the repository referenced below,
   > and the deployment has been validated/built with support for OpenShift 4.20 and OpenShift AI 3.3.
   >
   > For a newer and improved version of this demo, including updated deployment scripts and detailed documentation, see:
   > * https://github.com/brunoNetId/sp-edge-to-cloud-data-pipelines-demo
   >
   > This repository preserves the original implementation for reference.

RHODS artifacts are not YAML editable, they require UI interaction. \
Although tedious and time consuming, by the end of the deployment procedure (below), you will be able to understand how the full cycle connects all the stages together (acquisition, training, delivery, inferencing).

## Cluster

Do this first: obtain a running OpenShift cluster and confirm it meets the operator/version expectations before you follow the deployment steps.

### Request an OpenShift environment

1. Provision an environment from the [Red Hat Demo Platform](https://demo.redhat.com/), selecting **Red Hat OpenShift AI 3**: \
   https://catalog.demo.redhat.com/catalog?item=babylon-catalog-prod/published.openshift-ai-v3.prod&utm_source=webapp&utm_medium=share-link \
   This is the validated environment for installing this demo.

2. When the cluster is ready, open the **OpenShift web console** with the credentials provided for the sandbox, and run **`oc login`** against the same cluster API.

### Requirements (operators and versions)

Target versions are defined in `validate-cluster-operators.sh` and should match this list. After `oc login`, run the following from the root of this repository (repeat if you add or upgrade operators):

```bash
bash validate-cluster-operators.sh
```

* OpenShift **4.20.x**
* OpenShift Data Foundation **4.20**
* OpenShift AI **3.3.0**
* OpenShift Pipelines **1.21.1**
* AMQ Streams **3.1.0**
* AMQ Broker **7.12**
* **Apache Camel K** (community operator from OperatorHub) **2.x** — CSV is matched with substring **`2.`** in `validate-cluster-operators.sh` (excludes legacy **1.10.x** Red Hat–only line)
* Red Hat Service Interconnect (Skupper) **2.1.3**

The script exits with a non-zero status if the cluster minor version, any listed operator, or an installed version does not match; `install-demo-steps.sh` stops the install when validation fails.

## Deployment instructions

The following list summarises the steps to deploy the demo **after** [Cluster](#cluster) (environment ready, `oc` logged in, and validation as needed):

1. Create and prepare a RHOAI project.
1. Create and run the AI/ML Pipeline.
1. Deliver the AI/ML model and run the ML server.
1. Pipeline install, first run, triggers, and Kafka/Camel delivery.
1. Deploy the data ingestion system.
1. Test the end to end solution.

**Scripted install / uninstall:** from the repository root, **`bash install-demo-steps.sh`** provisions **`central`** (MinIO, then Kafka **`deployment/central/kafka.yaml`** unless **`SKIP_KAFKA=1`**), S3 buckets/uploads, project **`tf`**, workbench sync, Tekton **`train-model`** (**`deployment/pipeline/pipeline.yaml`** + **`rbac-pipeline-sa.yaml`**; **Trigger** / **EventListener** YAMLs unless **`SKIP_TEKTON_TRIGGERS=1`**; **`deployment/central/central-delivery-deployment.yaml`** unless **`SKIP_CENTRAL_DELIVERY=1`** (Quay **`:central-delivery-jvm`**); **`deployment/central/central-feeder-deployment.yaml`** unless **`SKIP_CENTRAL_FEEDER=1`** (Quay **`:central-feeder-jvm`**); then **`oc create -f deployment/pipeline/pipelinerun-example.yaml`** and waits for **Succeeded** unless **`SKIP_PIPELINE_RUN=1`**, timeout **`PIPELINE_RUN_TIMEOUT`** seconds, default **7200**), and in **`edge1`** (unless skipped): AMQ (**`deployment/edge/amq-broker.yaml`**, route **`broker-amq-mqtt`**) — requires **AMQ Broker Operator 7.12** — and edge MinIO (**`deployment/edge/minio.yaml`**, **`deployment/edge/minio-edge-buckets.sh`**). Skips: **`SKIP_EDGE1_AMQ=1`**, **`SKIP_EDGE1_MINIO=1`**, **`SKIP_EDGE1_MINIO_BUCKETS=1`**. **Skupper (RHSI):** by default **`install-demo-steps.sh`** runs **`deployment/si/skupper-link-minio.sh`** after edge MinIO. It **checks** that **`skupper`** is on your `PATH` and that **`skupper version`** works; it does **not** download or upgrade the CLI (install or upgrade Skupper on your machine yourself — see below). Skip with **`SKIP_SKUPPER_LINK=1`**. **Edge Manager:** after Skupper, the installer applies **`deployment/edge/edge-manager-deployment.yaml`** (needs the image already on Quay). Skip with **`SKIP_EDGE_MANAGER=1`**. **Edge Monitor:** then **`deployment/edge/edge-monitor-deployment.yaml`** (Quay **`:edge-monitor-jvm`**; Kafka in **`central`** + MQTT on edge). Skip with **`SKIP_EDGE_MONITOR=1`**. **TensorFlow Serving:** then **`deployment/edge/tensorflow.yaml`** (**`tf-server`**, model from MinIO **`production`**). Skip with **`SKIP_TF_SERVING=1`**. **Camel K price-engine:** registry secret **`camel-k-registry`**, **`deployment/edge/integration-platform-camel-k.yaml`** (namespace **`EDGE1_NS`**), ConfigMap **`catalogue`**, **`kamel run`** for **`camel/edge-shopper/camel-price/price-engine.xml`**, wait **Ready**, Route **`price-engine`**. Requires **Camel K operator 2.x**, **`kamel` CLI** on **`PATH`**, and a user token that can push to the internal registry. Skip with **`SKIP_EDGE1_CAMEL_K=1`**. **Edge Shopper:** **`deployment/edge/edge-shopper-deployment.yaml`** (Quay **`:edge-shopper-jvm`**), same ConfigMap **`catalogue`** mounted at **`/deployments/config`**, Route **`camel-edge`** → Service **`edge-shopper`**. Skip with **`SKIP_EDGE_SHOPPER=1`**. At the end of **`install-demo-steps.sh`**, the installer prints **`https://<route-host>/index.html`** and **`…/admin.html`** using the live **`oc get route camel-edge`** host (skip printing with **`SKIP_EDGE_SHOPPER_URLS=1`**). **`bash uninstall-demo-steps.sh`** deletes Tekton resources and projects **`tf`** / **`central`**, and **by default deletes the whole `edge1` project** (MinIO, AMQ, Skupper site there, edge-manager, edge-monitor, edge-shopper, tf-server, Camel K resources, routes). To keep the **`edge1`** namespace and remove only selected resources: **`SKIP_EDGE1_PROJECT_DELETE=1`** (optional **`SKIP_EDGE1_MINIO_UNINSTALL=1`**, **`SKIP_EDGE1_AMQ_UNINSTALL=1`**, **`SKIP_EDGE_MONITOR_UNINSTALL=1`**, **`SKIP_EDGE_SHOPPER_UNINSTALL=1`**, **`SKIP_EDGE1_CAMEL_K_UNINSTALL=1`**). Other skips: **`SKIP_TEKTON_UNINSTALL=1`**.

**Container images (Quay):** not built by **`install-demo-steps.sh`**. Build and push once with **`bash deployment/build-push-images.sh`** (default **JVM** builds **edge-manager**, **edge-monitor**, **edge-shopper**, **central-delivery**, and **central-feeder**; uses **podman**; **`CONTAINER_ENGINE=docker`** to override). GraalVM native is deferred — **`BACKLOG.md`**. One Quay repository **`sp-edge-to-cloud-data-pipelines-demo`** with differentiated tags (e.g. **`:edge-manager-jvm`**, **`:edge-monitor-jvm`**, **`:edge-shopper-jvm`**, **`:central-delivery-jvm`**, **`:central-feeder-jvm`**). See **`deployment/sp-demo-images.env.sh`**.

<br/>

### Create a RHODS project

1. Deploy an instance of Minio
   
   1. Create a new project, named `central`
   3. Under the `central` project, deploy the following YAML resource:
      * **deployment/central/minio.yaml**

1. Create necessary S3 buckets
   
   1. Open the Minio UI (2 routes: use _UI Route_)
   2. Login with `minio/minio123`
   3. Create buckets for RHODS:
      * **workbench**
   3. Create buckets for Edge-1:
      * **edge1-data**
      * **edge1-models**
      * **edge1-ready**

      <br/>

   3. [OPTIONAL] Create buckets for Edge-2: \
      (Not needed for standard demo)
      * **edge2-data**
      * **edge2-models**
      * **edge2-ready**

1. Create a new *Data Science Project*.

   Open *Red Hat OpenShift AI* (also known as RHODS). \
   Log in using your environment credentials. \
   Select *Data Science Projects* and click `Create data science project`. \
   As a name, use for example `tf` (TensorFlow).

   **From the CLI:** a plain `oc new-project tf` creates an OpenShift project, but the OpenShift AI dashboard only treats a namespace as a *data science project* when it has the label **`opendatahub.io/dashboard=true`** (this is what the dashboard applies when you use *Create data science project*; see the `DSG_CREATION` flow in [odh-dashboard `namespaceUtils.ts`](https://github.com/opendatahub-io/odh-dashboard/blob/main/backend/src/routes/api/namespaces/namespaceUtils.ts) and `isAiProject` in the UI). Without that label, the project will not appear under *Data science projects*.

   ```bash
   oc new-project tf --display-name="TensorFlow"
   oc label namespace tf opendatahub.io/dashboard=true --overwrite
   ```

   If your cluster has **Kueue** enabled for new dashboard projects (`spec.dashboardConfig.disableKueue: false` in `OdhDashboardConfig`), the dashboard also sets **`kueue.openshift.io/managed=true`** on the namespace; add the same label with `oc label` if workbenches or queues expect it.

1. Create a new *Data Connection*.

   Under the new `tf` project > Data connections, click `Add data connection`. \
   Enter the following parameters:
   * Name: `dc1` (data connection 1)
   * Access key: `minio` 
   * Secret key: `minio123` 
   * Endpoint: `http://minio-service.central.svc:9000` 
   * Region: `eu-west-2`
   * Bucket: `workbench`

1. Create a *Pipeline Server*.

   The dashboard flow is *Projects* → *Pipelines* → *Configure pipeline server* → existing data connection `dc1`. \
   The same result is a **`DataSciencePipelinesApplication`** (API group `datasciencepipelinesapplications.opendatahub.io`, short name **`dspa`**) in namespace `tf`, with **`spec.objectStorage.externalStorage`** pointing at MinIO and the **`dc1`** Secret for S3 keys. See **deployment/tf/datasciencepipelinesapplication.yaml** (RHOAI 3.3 / KFP v2, `dspVersion: v2`).

   From the CLI (after `dc1` exists):

   ```bash
   oc apply -f deployment/tf/datasciencepipelinesapplication.yaml
   oc wait datasciencepipelinesapplication/dspa -n tf --for=condition=Ready --timeout=600s
   ```

   If `condition=Ready` is not supported on your `oc` version, wait until the pipeline API route and pods are up: `oc get dspa,pods -n tf`.

   Do not create a second pipeline server for the same project in the UI without deleting this `dspa` first, or you will have two DSPA instances conflicting for the same purpose.

1. Create a '*PersistentVolumeClaim*' for the pipeline.

   This PVC is for **OpenShift Pipelines (Tekton)** task pods (the Elyra-exported `Pipeline` / `train-model` workflow). It is **not** the object-store backend of the **DataSciencePipelinesApplication** (KFP v2) pipeline server, which already uses S3 via `dc1`.

   Apply:

   ```bash
   oc apply -f deployment/pipeline/pvc.yaml
   ```

   Source: **deployment/pipeline/pvc.yaml** (core `PersistentVolumeClaim` `v1`; adjust `storageClassName` in the file if your cluster has no default StorageClass).

1. Create a new *Workbench*.

   **From the dashboard:** *Projects* → `tf` → *Workbenches* → *Create workbench*. Este taller usa **siempre** la imagen **Jupyter | TensorFlow | CUDA | Python 3.12** (no la variante ROCm). RHOAI **2025.1** / **2025.2** sustituyen las etiquetas antiguas de “TensorFlow” en la UI. Name **`wb1`**, size **Medium**, almacenamiento nuevo **`wb1-storage`** (convención de la consola: `<workbench>-storage`), data connection **`dc1`**. (Solo en clústeres AMD sin CUDA, `export WORKBENCH_ACCEL=rocm` antes del script CLI.)

   **From the CLI (recommended for automation):** el manifiesto replica lo que crea la consola: **`Notebook`** (`kubeflow.org/v1`) + PVC **`wb1-storage`**, anotación `notebooks.opendatahub.io/inject-auth: "true"`, imagen como referencia del **registry interno** (`image-registry.openshift-image-registry.svc:5000/.../tensorflow:2025.2`), `envFrom` del Secret **`dc1`**, recursos **Medium** (2 CPU / 4Gi) y los mismos `volumeMounts` opcionales (Elyra, CA, runtimes de pipeline). El operador inyecta **`kube-rbac-proxy`** y los volúmenes asociados; no los declares a mano.

   Discover the **ImageStream** name and tag that back that image (default location **`redhat-ods-applications`**; some installs use **`opendatahub`**):

   ```bash
   oc get imagestream -n redhat-ods-applications -l opendatahub.io/notebook-image=true \
     -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.opendatahub\.io/notebook-image-name}{"\n"}{end}'
   oc get imagestream <nombre-is> -n redhat-ods-applications -o jsonpath='{range .spec.tags[*]}{.name}{"\n"}{end}'
   ```

   En RHOAI reciente el ImageStream suele llamarse **`tensorflow`** con tag **`2025.2`** (comprueba con el listado anterior). El script construye la misma referencia que usa la UI (`image-registry.openshift-image-registry.svc:5000/<ns>/<is>:<tag>`). Para inspeccionar el digest externo:

   ```bash
   oc get imagestreamtag 'tensorflow:2025.2' -n redhat-ods-applications -o jsonpath='{.image.dockerImageReference}{"\n"}'
   ```

   Apply the manifests (imagen interna, usuario, commit del tag, `HardwareProfile` **default-profile** y anotaciones las rellena el script):

   ```bash
   oc project tf
   bash deployment/tf/apply-notebook-wb1.sh
   ```

   Or set overrides explicitly, for example:

   ```bash
   export NOTEBOOK_IS_NS=redhat-ods-applications
   # WORKBENCH_ACCEL=cuda por defecto (TensorFlow CUDA Py3.12). Solo en AMD: WORKBENCH_ACCEL=rocm
   export WORKBENCH_ISTAG='tensorflow:2025.2'   # u otro IS:tag; o WORKBENCH_IMAGE='…' (cualquier pull spec)
   # export WORKBENCH_HW_PROFILE=   # vacío omite anotaciones de hardware (p. ej. clúster sin HardwareProfile)
   bash deployment/tf/apply-notebook-wb1.sh
   ```

   Sources: **deployment/tf/workbench-pvc-wb1.yaml**, **deployment/tf/notebook-wb1.yaml** (placeholders `__…__`), **deployment/tf/render_notebook_wb1.py**, **deployment/tf/apply-notebook-wb1.sh**.

   > [!NOTE]
   > **Actualizar imagen en la UI:** Si *Current version* y *Latest version* muestran el mismo tag y digest (p. ej. ambos `2025.2` con el mismo hash `8e73cac`), no hay actualización pendiente. Si en el futuro difieren y pulsas actualizar, el mensaje de que se **reiniciará** `wb1` es normal.
   >
   > **Stack de referencia** (tag **2025.2**, imagen TensorFlow CUDA Python 3.12 en RHOAI reciente): CUDA 12.8, Python 3.12, TensorFlow 2.20, JupyterLab 4.4, Kubeflow Pipelines SDK 2.14, Odh-Elyra 4.3, y el resto de paquetes que lista la consola en *Software* / *Packages* (Boto3, Kafka-Python-ng, etc.). El script usa por defecto `WORKBENCH_TAG=2025.2` para alinear con esa línea.
   >
   > **Aviso “Notebook image deprecated” en la UI:** El dashboard marca el workbench si el **ImageStreamTag** tiene la anotación `opendatahub.io/image-tag-outdated: "true"` (ciclo de vida Red Hat: el tag sigue funcionando pero se considera fuera de la línea “recomendada”). No implica que tu imagen sea distinta de la del registry; a menudo **Current** y **Latest** coinciden y el warning sigue. Comprueba el tag que usas (`tensorflow:2025.2` típico):
   >
   > ```bash
   > oc get istag tensorflow:2025.2 -n redhat-ods-applications \
   >   -o jsonpath='{.tag.annotations.opendatahub\.io/image-tag-outdated}{"\n"}'
   > ```
   >
   > Si el `jsonpath` devuelve vacío, mira el YAML del tag (a veces la clave no está y el aviso de la UI viene de otra regla del dashboard):
   >
   > ```bash
   > oc get istag tensorflow:2025.2 -n redhat-ods-applications -o yaml | grep -E 'opendatahub\.io/(image-tag-outdated|workbench-image-recommended)'
   > ```
   >
   > Un `oc get istag … -o custom-columns=…OUTDATED:.tag.annotations…` sobre **lista** de tags suele mostrar `<none>`: OpenShift no rellena bien columnas anidadas en `ImageStreamTag`; usa un tag concreto como arriba.
   >
   > Si es `true`, puedes ignorar el aviso en demos, migrar cuando Red Hat publique un tag **no** marcado como outdated, o que un **administrador del clúster** revise el catálogo de imágenes del operador (no suele ser algo que corrija el YAML del proyecto `tf`).

1. Open the workbench (*Jupyter*).

   When your workbench is in *Running* status, click `Open`.

   Log in using your environment credentials.

<br/>

### Create the AI/ML Pipeline

1. Copy the pipeline sources into the workbench tree (no manual upload).

   > [!CAUTION] 
   > Do not use the *'Git Clone'* feature to upload the project, you don't need to upload the big dataset of images!

   **Automated (recommended):** with the `wb1` workbench *Running* in project `tf`, run (path to the script can be absolute; it always resolves `workbench/` from the repository tree that contains `deployment/`):

   ```bash
   oc project tf
   bash deployment/tf/sync-workbench-sources.sh
   ```

   This copies the whole **`workbench/`** directory from the clone into **`/opt/app-root/src/workbench`** inside the Jupyter pod (via `tar` and `oc exec`). It includes the files used in the next steps:

   * **workbench/clean-01.ipynb** — full modelling flow
   * **workbench/pipeline/step-01.ipynb**, **step-02.ipynb**, **step-03.ipynb** — segmented steps
   * **workbench/pipeline/retrain.pipeline** — Elyra pipeline definition

   Optional: the same step runs automatically after the workbench apply when you use **`install-demo-steps.sh`**, unless you set **`SKIP_WORKBENCH_SOURCES=1`**.

   **Verify the copy** (replace nothing if you only have one `wb1` pod):

   ```bash
   POD=$(oc get pods -n tf -l app=wb1 -o jsonpath='{.items[0].metadata.name}')
   oc get pod -n tf "$POD" -o wide
   oc exec -n tf "$POD" -c wb1 -- ls -la /opt/app-root/src/workbench
   oc exec -n tf "$POD" -c wb1 -- ls -la /opt/app-root/src/workbench/pipeline
   oc exec -n tf "$POD" -c wb1 -- test -f /opt/app-root/src/workbench/clean-01.ipynb && echo "clean-01.ipynb OK"
   oc exec -n tf "$POD" -c wb1 -- test -f /opt/app-root/src/workbench/pipeline/retrain.pipeline && echo "retrain.pipeline OK"
   ```

   In Jupyter, open the file browser: you should see a **`workbench`** folder with the same layout.

   **Manual alternative:** *Jupyter* menu → *Upload Files* and upload the paths above if you cannot use `oc`.

   <br/>

1. Install the *Tekton* `Pipeline` used by this workshop (**OpenShift Pipelines**, not Data Science Pipelines).

   > [!TIP] 
   > Reference to documented guidelines:
   > * https://docs.google.com/document/d/1kcubQQuQyJGP_grbMD6Jji8o-IBDrYBbuIOREj2dFlc/edit#heading=h.wd1fnfz39nr

   > [!NOTE]
   > **Why you only see “KFP” in Elyra and not “Tekton”:** Workbench images on OpenShift AI ship **[`odh-elyra`](https://github.com/opendatahub-io/elyra)** (see also [`odh-elyra` on PyPI](https://pypi.org/project/odh-elyra/)), which targets **Data Science Pipelines / KFP v2**. The separate **Tekton YAML file** export path exists in **upstream** Elyra for **OpenShift Pipelines** (`tekton.dev`), but it is **not offered** in this productized editor—**only KFP-oriented actions appear**. That is expected, not a misconfiguration.
   >
   > **`Error making request` / `Unexpected token '<' … is not valid JSON`:** Elyra is calling an HTTP endpoint that returns **HTML** (often OAuth or an error page) instead of **JSON**. That is common when mixing legacy KFP v1 client assumptions with DSPA / KFP v2 routes. See also [this Elyra discussion on KFP v1 APIs vs newer deployments](https://github.com/elyra-ai/elyra/issues/3092#issuecomment-1404990114).

   **Recommended on OpenShift AI — skip Elyra export and apply the manifest from this repo** (already `tekton.dev/v1`, namespace `tf`, name `train-model`):

   ```bash
   oc project tf
   oc apply -f deployment/pipeline/pipeline.yaml
   oc get pipeline train-model -n tf -o yaml
   ```

   **CPU vs GPU (NVIDIA):** the parameter **`use_gpu_for_training`** defaults to **`false`** so runs work on clusters without GPU. Set it to **`true`** when you want **`create_model`** (`run-a-file-2`) and **`push_model`** (`run-a-file-3`) to each request **`nvidia.com/gpu: 1`**; the Pipeline tolerates the common **`nvidia.com/gpu`** taint so pods schedule on GPU nodes. Those GPU steps set **`TF_XLA_FLAGS`** / **`XLA_FLAGS`** so TensorFlow can find **`libdevice`** under the CUDA image (avoids errors like **`libdevice.10.bc` not found**). The CPU branch uses **`CUDA_VISIBLE_DEVICES=-1`** so TensorFlow stays on CPU even if the pod lands on a GPU-capable node. The first step **`run-a-file`** (data prep) has no GPU request. **AMD / other accelerators** need different resource names and are not covered here.

   You can still open **`workbench/pipeline/retrain.pipeline`** in Jupyter on OpenShift AI to **show the visual pipeline** in class; the **Tekton** install itself uses the command above.

   > [!CAUTION]
   > **`deployment/pipeline/pipeline.yaml`** references Elyra dependency archives under the MinIO bucket **`workbench`** (prefix `retrain-0109181508/`). Those objects are normally produced when an Elyra export uploads to COS. This repository vendors a copy under **`deployment/pipeline/s3/workbench/`**; **`install-demo-steps.sh`** (via **`deployment/central/minio-buckets-and-dataset.sh`**) uploads that tree to the **`workbench`** bucket so the first **PipelineRun** can find the `step-0X-*.tar.gz` files. To skip that upload: **`SKIP_WORKBENCH_S3_ARTIFACTS=1`**. If you change the pipeline export, refresh **`pipeline.yaml`** and the files under **`deployment/pipeline/s3/workbench/`** (or upload the new prefix manually).

   **CLI / notebook — generate YAML from the Elyra `.pipeline` file (not from a single `.ipynb`):** OpenShift and `tkn` do **not** compile notebooks into a `Pipeline` object. Elyra does, but it consumes the **pipeline graph** (`*.pipeline` JSON), which references your `step-*.ipynb` files.

   * **Elyra command-line** (installed with the workbench image as part of Elyra): from a terminal or a notebook cell, run:
     ```bash
     elyra-pipeline export path/to/retrain.pipeline \
       --runtime-config YOUR_RUNTIME_NAME \
       --format yaml \
       --output ./exported.yaml \
       --overwrite
     ```
     You need a **runtime configuration** whose type matches the pipeline (create it in the UI under *Runtimes* or with [`elyra-metadata`](https://elyra.readthedocs.io/en/stable/user_guide/command-line-interface.html)). On **OpenShift AI**, **`odh-elyra`** exports **`yaml`** / **`py`** aimed at **Data Science Pipelines (KFP v2)** — that is **not** the same resource as an OpenShift **Tekton** `Pipeline` (`tekton.dev/v1`) used in this demo. Use that YAML with the **Data Science Pipelines** UI/API if you adopt that track; for **Tekton** here, keep using **`deployment/pipeline/pipeline.yaml`**.
   * **Notebook:** run **`workbench/export_elyra_pipeline.ipynb`** end-to-end (lista runtimes vía API de Elyra, comprueba *component catalogs*, ejecuta `elyra-pipeline export`). Variables opcionales: `ELYRA_RUNTIME_NAME`, `ELYRA_EXPORT_OUTPUT_DIR`, `ELYRA_EXPORT_FORMAT`, `ELYRA_PARAM_S3ENDPOINT`.
   * **Si el export tarda minutos o en los logs aparece** `No components could be found in any catalog for platform type 'KUBEFLOW_PIPELINES'`: Elyra necesita al menos un **Pipeline component catalog** para KFP (barra lateral *Component catalogs* en JupyterLab, o documentación [Elyra — Pipeline components](https://elyra.readthedocs.io/en/stable/user_guide/pipeline-components.html) y la guía de pipelines en Jupyter de OpenShift AI). Sin catálogos, el taller con Tekton sigue siendo **`oc apply -f deployment/pipeline/pipeline.yaml`**. El aviso `No entrypoint with name 'airflow'` en `odh-elyra` es habitual y se puede ignorar.
   * **Notebook cell:** también puedes usar `!elyra-pipeline export ...` o `subprocess.run([...], check=True)` como en ese notebook.
   * **`oc`:** `oc apply -f`, `oc create -f` — apply manifests only; no conversion from notebooks.
   * **`tkn`:** run / describe / export pipelines **already on the cluster**; it does not build YAML from Elyra or Jupyter sources.

   **Optional — import via console instead of `oc apply`:** From *OpenShift UI* → *Pipelines* → *Pipelines* (project `tf`), *Create* → *Pipeline*, and use:

   ```yaml
   apiVersion: tekton.dev/v1
   kind: Pipeline
   metadata:
     name: train-model
     namespace: tf
   spec:
   
     [Copy paste here contents under 'pipelineSpec']
   ```

   Paste the full **`spec:`** from **`deployment/pipeline/pipeline.yaml`** (or from a `retrain.yaml` you generated with upstream Elyra), i.e. everything under `spec` of the `Pipeline` resource.

   > [!CAUTION] 
   > Make sure you un-tab one level the `pipelineSpec` definition if you paste a nested export. Elyra may still emit `tekton.dev/v1beta1` and `$(inputs.params.*)` inside embedded `taskSpec` steps. For **OpenShift Pipelines** with **`tekton.dev/v1`**, use `apiVersion: tekton.dev/v1`, add `type: string` (and other types as needed) on each declared `param`, and replace `$(inputs.params.NAME)` with `$(params.NAME)` in step arguments. Point `secretKeyRef` for AWS keys at the **`dc1`** Secret (same as the data connection).

   You can test the pipeline by clicking `Action > Start`, accept default values and click `Start`.

   If the bucket **`edge1-data`** is still empty, the pipeline can <u>**FAIL**</u> (no trainable data). After you upload images (below) or run **`install-demo-steps.sh`** with **`dataset/images`** populated, a new run should get past the data step.

1. Upload training data to S3.

   There are three options to upload training data:
   * **With the install script (recommended for demos)**: put image files under **`dataset/images`** in your clone, then run **`bash install-demo-steps.sh`**. MinIO setup uses **one** short-lived pod (**`deployment/central/minio-buckets-and-dataset.sh`**) that creates the standard buckets and uploads to **`s3://edge1-data/images/`** (required layout for **`step-01`** / **`step-02`**). To upload only the dataset later: **`bash deployment/central/sync-dataset-to-minio.sh`**. To skip dataset upload when you have no local files yet: **`SKIP_MINIO_TRAINING_DATA=1 bash install-demo-steps.sh`**. See **`dataset/images/README.txt`**.
   * **Manually**: Use MinIO’s UI console to upload the images (training data):
     * From the project’s folder:
       * `dataset/images` (including class subfolders)
     * Into bucket **`edge1-data`** under the **`images/`** prefix (so object keys look like `images/<class>/file.jpg`, not loose at the bucket root). **`step-01.ipynb`** downloads `Key` to `working_dir + Key`, and **`step-02`** expects `working_dir/images/`.
       (wait for all images to be fully uploaded)
   * **Camel feeder**: Use the Camel server provided in the repository to push training data to S3. Follow the instructions under:
     * `camel/central-feeder/Readme.txt`

1. Train the model.

   When **ALL** images have been uploaded, re-run the pipeline by clicking `Action > Start`, accept default values and click `Start`.

   You should now see the pipeline succeed. It will push the new model to the following buckets:
   * `edge1-models`
   * `edge1-ready`

<br/>

### Prepare the *Edge1* environment

1. Create a new *OpenShift* project `edge1`.


1. Deploy an *AMQ Broker*
    
    AMQ is used to enable MQTT connectivity with edge devices and manage monitoring events.

    1. Install the **AMQ Broker Operator** from OperatorHub: *Red Hat Integration - AMQ Broker for RHEL 8 (Multiarch)*, on a channel that matches **AMQ Broker 7.12** (see [Requirements](#requirements-operators-and-versions) and `validate-cluster-operators.sh`).

        **Installation mode — namespace-only vs cluster-wide (All namespaces):** both are supported in OpenShift. If you installed the operator **cluster-wide**, you do **not** need a second operator in `edge1`; create the broker CR in `edge1` as below. Be aware of the following:

        * **Overlapping operators:** you must **not** run two AMQ Broker Operators whose watch scope overlaps the same namespace (for example, one *All namespaces* and another *Single namespace* that includes `edge1`). That leads to conflicting reconciliation. *Remediation:* uninstall the duplicate subscription or narrow `WATCH_NAMESPACE` / installation mode so only one operator manages `edge1`.
        * **RBAC and upgrades:** a cluster-wide install uses broader cluster RBAC and cluster admins control operator upgrades for every watched namespace — expected, not a functional bug.
        * **Nothing happens after `oc apply`:** confirm the ClusterServiceVersion is **Succeeded**, the operator’s watch scope includes **`edge1`**, and you applied the CR with **`-n edge1`**. Check `oc get activemqartemis -n edge1` and operator pod logs in `openshift-operators` (typical for all-namespaces installs).

    1. Create the ***ActiveMQArtemis*** broker instance from **`deployment/edge/amq-broker.yaml`**. The manifest uses **`apiVersion: broker.amq.io/v1beta1`**, **`kind: ActiveMQArtemis`**, and **`deploymentPlan.image: placeholder`**, which matches the Red Hat AMQ Broker **7.12** operator examples (the operator resolves the broker image). **`metadata.name: broker-amq`** and the **`mqtt`** acceptor determine the MQTT **Service** name — keep them unchanged so downstream apps stay aligned.

        ```bash
        oc project edge1
        oc apply -f deployment/edge/amq-broker.yaml
        ```

    1. Create a route for external MQTT (demo mobile app). **Keep the route name `broker-amq-mqtt` and the service `broker-amq-mqtt-0-svc`** so other components can rely on stable names.

        ```bash
        oc project edge1
        oc create route edge broker-amq-mqtt --service broker-amq-mqtt-0-svc
        ```

    1. **Quick check (optional):** `oc get activemqartemis,pods,route/broker-amq-mqtt -n edge1`. When the broker pod is **Running**, you can inspect the MQTT route with `oc describe route broker-amq-mqtt -n edge1` (hostname and target port for clients). Same steps run automatically if you use **`install-demo-steps.sh`** without **`SKIP_EDGE1_AMQ=1`**.

1. Deploy a *Minio* instance on the (near) edge.

   Use the same pattern as *central*: apply the manifest (Deployment, PVC, Secret, Service, Routes), wait for the deployment, then create buckets with a short-lived pod and the MinIO client `mc` (no `tar` in the `minio` image — same approach as **`deployment/central/minio-buckets-and-dataset.sh`**).

   1. In the `edge1` namespace apply **`deployment/edge/minio.yaml`** (equivalent layout to **`deployment/central/minio.yaml`**: `minio-service`, routes **`minio-api`** / **`minio-ui`**, credentials `minio` / `minio123`).

      ```bash
      oc project edge1
      oc apply -f deployment/edge/minio.yaml
      oc rollout status deployment/minio -n edge1 --timeout=300s
      ```

   1. Create the edge buckets (**production**, **data**, **valid**, **unclassified**):

      ```bash
      bash deployment/edge/minio-edge-buckets.sh
      ```

      Or with an explicit namespace: **`EDGE1_NS=edge1 bash deployment/edge/minio-edge-buckets.sh`**. Skip bucket creation only: **`SKIP_EDGE1_MINIO_BUCKETS=1`**.

      Bucket purposes (unchanged): **production** (live AI/ML models), **data** (training data), **valid** (valid inferences), **unclassified** (invalid inferences).

   **`install-demo-steps.sh`** applies edge MinIO after the AMQ block unless **`SKIP_EDGE1_MINIO=1`**, then runs **Service Interconnect** (**`deployment/si/skupper-link-minio.sh`**) unless **`SKIP_SKUPPER_LINK=1`**. **`uninstall-demo-steps.sh`** deletes the **`edge1`** project by default; use **`SKIP_EDGE1_PROJECT_DELETE=1`** to keep **`edge1`** and remove resources selectively (**`SKIP_EDGE1_MINIO_UNINSTALL`**, **`SKIP_EDGE1_AMQ_UNINSTALL`**, **`SKIP_EDGE_MONITOR_UNINSTALL`**, **`SKIP_EDGE_SHOPPER_UNINSTALL`**, **`SKIP_EDGE1_CAMEL_K_UNINSTALL`**).

1. Create a local service to access the **central** S3 storage with **Service Interconnect** (Red Hat Service Interconnect / Skupper).

   **Prerequisites:** the **Red Hat Service Interconnect** operator on the cluster (see [Requirements](#requirements-operators-and-versions)), projects **`central`** and **`edge1`**, and **MinIO** in **`central`** as **`minio-service`**.

   **Automated (equivalent to the manual steps below):** the installer runs this after edge MinIO. You can run the same script alone from the repo root with **`skupper`** on your `PATH`:

   ```bash
   bash deployment/si/skupper-link-minio.sh
   ```

   The script writes **`edge-to-central.token`** in the repo root (listed in **`.gitignore`**). Skupper **v2** rejects token paths containing underscores — use only **`[A-Za-z0-9./~-]`** in the filename. Override with **`TOKEN_FILE=/path/to/token`**.

   **Skip from the full installer:** **`SKIP_SKUPPER_LINK=1 bash install-demo-steps.sh`** if you do not want Skupper (no **`skupper`** CLI, or you will link sites manually later).

   ---

   **Manual procedure** (follow in order):

   **Skupper CLI v1 vs v2:** Red Hat Service Interconnect **2.x** ships a CLI without **`skupper init`** (uses **`skupper site create`**, **`skupper token issue` / `redeem`**, **`skupper connector`** / **`listener`**). The steps **2–4** below are the **v1** flow. **`bash deployment/si/skupper-link-minio.sh`** detects your CLI and runs **v1 or v2** automatically — prefer that script if you are unsure.

   **1. Install Service Interconnect’s CLI**

   Use any terminal with outbound HTTPS (your laptop, CI, or the **embedded terminal** in the OpenShift console).

   ```bash
   curl https://skupper.io/install.sh | sh
   ```

   Put the CLI on your `PATH`. Examples:

   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```

   In the OpenShift web terminal, the install path is often under **`/home/user`**:

   ```bash
   export PATH="/home/user/.local/bin:$PATH"
   ```

   If the installer prints a different directory, use that instead.

   **Update an existing Skupper CLI (manual, on your workstation)**

   The **`install-demo-steps.sh`** script does **not** install or upgrade Skupper for you. To refresh the binary yourself:

   1. See what you have: **`which skupper`** and **`skupper version`**.
   2. Download the official installer and run it locally (same as a first install; it typically replaces the CLI under your home directory):

      ```bash
      curl -sSfL https://skupper.io/install.sh -o /tmp/skupper-install.sh
      sh /tmp/skupper-install.sh
      ```

      (You can use **`curl … | sh`** if you accept piping; saving the script first lets you inspect it.)

   3. Ensure **`PATH`** includes the directory the installer prints (often **`$HOME/.local/bin`**). Open a **new** shell, or run **`hash -r`** in bash, then **`skupper version`** again to confirm.
   4. If you installed via **Homebrew** instead: **`brew update && brew upgrade skupper`** (when the formula exists for your OS).

   **2. Initialize SI in `central` and create a connection token**

   ```bash
   oc project central
   skupper init --enable-console --enable-flow-collector --console-auth unsecured
   skupper token create edge-to-central.token
   ```

   Run **`skupper token create`** (v1) or **`skupper token issue`** (v2) from the directory where you want the token file written (or pass an absolute path). **v2** requires the filename to match **`^[A-Za-z0-9./~-]+$`** (no underscores).

   **3. Initialize SI in `edge1` and link using that token**

   ```bash
   oc project edge1
   skupper init
   skupper link create edge-to-central.token --name edge-to-central
   ```

   The token file must be readable from your current working directory (or use the full path to the file).

   **4. Expose MinIO (S3) from `central` on the application network**

   On OpenShift, use **`oc`** (equivalent to `kubectl` here). **`--overwrite`** lets you re-run the command safely if the annotations already exist:

   ```bash
   oc project central
   oc annotate service minio-service skupper.io/proxy=http skupper.io/address=minio-central --overwrite
   ```

   **5. Verify on `edge1`**

   The Skupper-local service **`minio-central`** should appear in **`edge1`** (e.g. **`oc get svc -n edge1`**). Optional: expose the MinIO **console** (port **9090**) with a Route for a quick UI check:

   ```bash
   oc project edge1
   oc create route edge minio-central-demo --service=minio-central --port=port9090
   ```

   Open the route URL and confirm **central** buckets (e.g. **workbench**, **edge1-data**). Remove the test route when done: **`oc delete route minio-central-demo -n edge1`**.

   If **`skupper init`** fails because a site already exists, you may need **`skupper delete`** in that namespace first (destructive for that Skupper site — see RHSI documentation).

<br/>

### Deliver the AI/ML model and run the ML server

1. Deploy the *Edge Manager* (Quarkus + **Camel Quarkus**, not Camel K). \
   **Default image tag is `:jvm`** (faster builds). **Native (GraalVM)** is in **`BACKLOG.md`**.

   * **Documentation (build, Quay, OpenShift):** **`camel/edge-manager/README.md`**
   * **Short pointer:** **`camel/edge-manager/Readme.txt`**
   * **Image naming:** `quay.io/<org>/sp-edge-to-cloud-data-pipelines-demo:edge-manager-jvm` (same repo, tag **`edge-manager-native`** for Graal later) — **`deployment/sp-demo-images.env.sh`**, **`BACKLOG.md`**.

   The Edge Manager copies new objects from the **`edge1-ready`** bucket on **central** MinIO into **`production`** on **edge** MinIO (Skupper service **`minio-central`** in `edge1` is the usual endpoint). When it sees **`saved_model.pb`**, it publishes an MQTT notification.

   **Build image once, then deploy:** use **`bash deployment/build-push-images.sh`** from the repo root (see **`deployment/build-push-images.sh --help`**). It does **not** run as part of **`install-demo-steps.sh`**.

   After the image is on Quay, **`install-demo-steps.sh`** applies this manifest by default (after Skupper). To skip that step: **`SKIP_EDGE_MANAGER=1`**. Manual apply:

   ```bash
   oc project edge1
   oc apply -f deployment/edge/edge-manager-deployment.yaml
   ```

   **Manual equivalent** (JVM, same image tag as the default Deployment):

   ```bash
   cd /path/to/repo
   source deployment/sp-demo-images.env.sh
   cd camel/edge-manager
   ./mvnw -DskipTests package
   podman build --platform linux/amd64 -f src/main/docker/Dockerfile.jvm -t "${SP_IMAGE_EDGE_MANAGER_JVM}" .
   podman push "${SP_IMAGE_EDGE_MANAGER_JVM}"
   ```

2. Deploy the *Edge Monitor* (Quarkus + **Camel Quarkus**). \
   Forwards messages from the **Kafka** topic named after the edge namespace (e.g. **`edge1`**, produced by **central-feeder**) to **MQTT** on the AMQ Broker in **`edge1`** (**`broker-amq-mqtt-0-svc`**).

   * **Documentation:** **`camel/edge-monitor/README.md`**
   * **Short pointer:** **`camel/edge-monitor/Readme.txt`**
   * **Image naming:** `quay.io/<org>/sp-edge-to-cloud-data-pipelines-demo:edge-monitor-jvm` — **`deployment/sp-demo-images.env.sh`**.

   **Build image once, then deploy:** **`bash deployment/build-push-images.sh edge-monitor-jvm`** (or **`bash deployment/build-push-images.sh`** includes it). Not built inside **`install-demo-steps.sh`**.

   After the image is on Quay, **`install-demo-steps.sh`** applies **`deployment/edge/edge-monitor-deployment.yaml`** by default after Edge Manager. Skip with **`SKIP_EDGE_MONITOR=1`**. Manual apply:

   ```bash
   oc project edge1
   oc apply -f deployment/edge/edge-monitor-deployment.yaml
   oc rollout status deployment/edge-monitor -n edge1 --timeout=300s
   ```

   **Manual equivalent** (JVM):

   ```bash
   cd /path/to/repo
   source deployment/sp-demo-images.env.sh
   cd camel/edge-monitor
   ./mvnw -DskipTests package
   podman build --platform linux/amd64 -f src/main/docker/Dockerfile.jvm -t "${SP_IMAGE_EDGE_MONITOR_JVM}" .
   podman push "${SP_IMAGE_EDGE_MONITOR_JVM}"
   ```

3. Deploy the TensorFlow server.

   In project **`edge1`**, apply **`deployment/edge/tensorflow.yaml`**. TensorFlow Serving loads the model from MinIO bucket **`production`** in the same namespace (`S3_ENDPOINT=http://minio-service:9000`).

   ```bash
   oc project edge1
   oc apply -f deployment/edge/tensorflow.yaml
   oc rollout status deployment/tf-server -n edge1 --timeout=600s
   oc get route tf-server -n edge1 -o jsonpath='{.spec.host}{"\n"}'
   ```

   **`install-demo-steps.sh`** applies this manifest by default after Edge Monitor (skip with **`SKIP_TF_SERVING=1`**). OpenShift **Route** **`tf-server`** exposes the REST API (container port **8501**). Adjust **`MODEL_NAME`** / **`MODEL_BASE_PATH`** in the YAML if your pipeline publishes the model under a different path in **`production`**.

<br/>

### Manual inference test (TensorFlow Serving REST)

Use this after **`deployment/tf-server`** is **Ready** and the model is available in **`production`**. All steps assume **`oc`** points at the same cluster as the demo.

**Prerequisites**

- Route **`tf-server`** in **`edge1`** (HTTPS host from `oc get route`).
- Sample images under **`client/`** (e.g. **`green.jpg`**).

**Option A — helper script (recommended)**

**`client/infer.sh`** resolves the server URL from the Route (`https://<host>`), encodes the image for JSON (`base64 -w0` on Linux, **`base64 -i`** on macOS), and POSTs to **`/v1/models/tea_model_b64:predict`**.

```bash
oc login …   # same kube context as the demo cluster
cd client
./infer.sh
```

Optional environment variables:

| Variable | Purpose |
| -------- | ------- |
| **`IMAGE`** | Image path (default **`./green.jpg`**). |
| **`EDGE1_NS`** | Namespace of Route **`tf-server`** (default **`edge1`**). |
| **`SERVER`** | Full base URL (e.g. **`https://tf-server-edge1.apps…`**). If unset, **`oc get route tf-server`** is used. |
| **`OC`** | OpenShift CLI binary (default **`oc`**). |

Examples:

```bash
IMAGE=./lemon.jpg ./infer.sh
SERVER=https://tf-server-edge1.apps.example.com ./infer.sh   # no oc lookup
```

**Option B — raw `curl` (manual)**

Resolve the host, build Base64 (portable Linux vs macOS), then call the **Predict** API:

```bash
SERVER="https://$(oc get route tf-server -n edge1 -o jsonpath='{.spec.host}')"
cd client
IMG=green.jpg
if B64=$(base64 -w0 "$IMG" 2>/dev/null); then :; else B64=$(base64 -i "$IMG" 2>/dev/null | tr -d '\n'); fi
curl -sS -X POST "${SERVER}/v1/models/tea_model_b64:predict" \
  -H "content-type: application/json" \
  -d "{\"instances\":[{\"b64\":\"${B64}\"}]}"
```

**Expected response**

You should see JSON similar to:

```
"predictions": ["tea-green", "0.838234"]
```

If TLS verification fails against the cluster certificate, add **`curl -k`** (not recommended for production).

<br/>

### Pipeline install, first run, and triggers (Tekton)

**What `install-demo-steps.sh` already does (project `tf`)**

In **section 3** of **`install-demo-steps.sh`**, the same resources this chapter describes are applied in order:

| Step | Manifest | Skip |
| ---- | -------- | ---- |
| Pipeline definition | **`deployment/pipeline/pipeline.yaml`** | — |
| ServiceAccount / RBAC | **`deployment/pipeline/rbac-pipeline-sa.yaml`** | — |
| Trigger binding | **`deployment/pipeline/trigger-binding.yaml`** (applied before template in **`install-demo-steps.sh`**) | **`SKIP_TEKTON_TRIGGERS=1`** |
| Trigger template | **`deployment/pipeline/trigger-template.yaml`** | **`SKIP_TEKTON_TRIGGERS=1`** |
| Event listener | **`deployment/pipeline/event-listener.yaml`** | **`SKIP_TEKTON_TRIGGERS=1`** |
| First **PipelineRun** | **`deployment/pipeline/pipelinerun-example.yaml`** (`oc create -f`, not `apply`) | **`SKIP_PIPELINE_RUN=1`** |

After creating the **PipelineRun**, the installer runs **`oc wait --for=condition=Succeeded`** up to **`PIPELINE_RUN_TIMEOUT`** seconds (default **7200**). If the run fails or times out, the script **prints a warning** and continues (so edge deploy steps can still run). Adjust GPU or other parameters by editing **`pipelinerun-example.yaml`** or creating additional runs from the console.

You only need the **manual YAML steps below** if you are **not** using the full installer, you used **`SKIP_TEKTON_TRIGGERS=1`**, or you are reconciling drift by hand.

---

#### Manual: create the Pipeline trigger resources

The next stage makes the pipeline triggerable so the platform can start training when external events arrive (e.g. HTTP to the EventListener, or later Kafka/Camel in this guide).

1. **Create a Pipeline trigger**

   Switch to the **`tf`** project where the **`train-model`** **Pipeline** exists.

   1. Deploy **deployment/pipeline/trigger-binding.yaml**
   1. Deploy **deployment/pipeline/trigger-template.yaml**
   1. Deploy **deployment/pipeline/event-listener.yaml**

2. **Trigger the pipeline**

   To manually test the pipeline trigger, from OpenShifts's UI console, open a terminal by clicking the icon `>_` in the upper-right corner of the screen.

   Copy/Paste and execute the following `curl` command:

    ```bash
    curl -v \
    -H 'content-Type: application/json' \
    -d '{"id-edge":"edge1"}' \
    http://el-train-model-listener.tf.svc:8080
    ```
   The output of the command above should show the status response:
    ```
    HTTP/1.1 202 Accepted
    ```
   Switch to the Pipelines view to inspect if a new pipeline execution has started.

   a. When the pipeline succeeds, a new model version will show up in the `edge1-models` S3 bucket.
   
   b. The pipeline also pushes the new model to the `edge1-ready` bucket. The *Edge Manager* moves the model to the *Edge Minio* instance, into the `production` bucket.  The Model server will detect the new version and hot reload it.

3. Deploy a Kafka cluster

   The platform uses Kafka to produce/consume events to trigger the pipeline automatically.

   **Compatibility of `deployment/central/kafka.yaml`**

   * **Operator:** **Red Hat AMQ Streams** (Strimzi-based) must be installed; CRDs use **`kafka.strimzi.io`**.
   * **API:** **`kafka.strimzi.io/v1beta2`** for **`Kafka`** and **`KafkaNodePool`**. Strimzi **0.46+** no longer supports ZooKeeper-only clusters; this manifest uses **KRaft** with **node pools** (see annotations on the `Kafka` CR).
   * **Kafka version:** **`spec.kafka.version`** and **`spec.kafka.metadataVersion`** must match versions **supported by your operator** (for example **`4.0.0`** with **`metadataVersion: 4.0-IV3`**). Verify with:
     ```bash
     oc explain kafka.spec.kafka.version
     ```
     or *Supported Kafka versions* in [Deploying and managing AMQ Streams on OpenShift](https://docs.redhat.com/en/documentation/red_hat_amq_streams/). If status shows **`UnsupportedKafkaVersionException`**, align **`version`** / **`metadataVersion`** with your operator’s examples (e.g. **4.1.0** if listed).
   * **Topology:** One **`KafkaNodePool`** with roles **controller** and **broker**, **ephemeral** storage, **replicas: 1** — suitable for demos; production should follow Red Hat sizing and storage guidance.

   **Manual install (operator + cluster)**

   The operator is usually installed **cluster-wide** (for example namespace **`openshift-operators`**). The **Kafka** custom resource lives in project **`central`** (same as MinIO in this demo).

   **A. Operator from the web console**

   1. **Operators → OperatorHub** → search **AMQ Streams** or **Streams for Apache Kafka**.
   1. **Install** → pick **All namespaces on the cluster** (typical) or a dedicated namespace per your policy.
   1. Wait until the operator **ClusterServiceVersion** shows **Succeeded**.

   **B. Operator from the CLI (Subscription)**

   Adjust **channel** if your cluster catalog differs (inspect with **`oc get packagemanifest amq-streams -n openshift-marketplace -o yaml`**).

   ```bash
   oc apply -f - <<'EOF'
   apiVersion: operators.coreos.com/v1alpha1
   kind: Subscription
   metadata:
     name: amq-streams
     namespace: openshift-operators
   spec:
     channel: stable
     name: amq-streams
     source: redhat-operators
     sourceNamespace: openshift-marketplace
     installPlanApproval: Automatic
   EOF

   oc get csv -n openshift-operators -w
   # Wait until the AMQ Streams CSV shows Phase: Succeeded (Ctrl+C to stop watching).
   ```

   **C. Kafka cluster CR**

   **`install-demo-steps.sh`** applies **`deployment/central/kafka.yaml`** in **`central`** after MinIO (unless **`SKIP_KAFKA=1`**). For a manual apply, ensure project **`central`** exists. If an older **ZooKeeper-based** `Kafka` named **`my-cluster`** is already present, remove it before applying the KRaft manifest: **`oc delete kafka my-cluster -n central`** (skip if it does not exist). Then:

   ```bash
   oc project central
   oc apply -f deployment/central/kafka.yaml
   oc wait kafka/my-cluster -n central --for=condition=Ready --timeout=600s
   ```

   If **`oc wait`** does not know the condition on your **`oc`** version:

   ```bash
   oc get kafka my-cluster -n central -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
   ```

   **D. Sanity checks**

   ```bash
   oc get kafka,kafkanodepool,pod -n central -l strimzi.io/cluster=my-cluster
   ```

4. Deploy the Camel delivery system

    This Camel service (namespace **`central`**) consumes Kafka topic **`trigger`** and POSTs to the Tekton **EventListener** in **`tf`** (`el-train-model-listener.tf.svc:8080` by default).

    **Install script:** after Tekton triggers, **`install-demo-steps.sh`** applies **`deployment/central/central-delivery-deployment.yaml`** unless **`SKIP_CENTRAL_DELIVERY=1`** (image **`:central-delivery-jvm`** must already be on Quay).

    **Manual flow (same Quay repo as edge-manager, different tag `central-delivery-jvm`):**

    1. Build and push the image from the repo root — see **`camel/central-delivery/README.md`** (or **`bash deployment/build-push-images.sh central-delivery-jvm`**).
    2. Apply **`deployment/central/central-delivery-deployment.yaml`** with **`oc project central`**.

    Shorter pointers: **`camel/central-delivery/Readme.txt`**.

    When successfully deployed, the app should connect to Kafka and consume **`trigger`**. If the broker does not auto-create topics, define **`trigger`** (e.g. `KafkaTopic` CR or a one-off producer). Verify the deployment is **Running** and pipeline runs fire when events arrive.

    > [!CAUTION]
    > You might need to wait until the topic exists and the consumer has joined the group, be patient.



<br/>


### Deploy the data ingestion system

A **Camel** service on **`central`** accepts ZIP uploads of training images, unpacks them into MinIO bucket **`{edgeId}-data`** (e.g. **`edge1-data`**), and publishes **Kafka** messages (including topic **`trigger`** for the pipeline path via **central-delivery**).

**Install script:** after **central-delivery**, **`install-demo-steps.sh`** applies **`deployment/central/central-feeder-deployment.yaml`** unless **`SKIP_CENTRAL_FEEDER=1`**. The manifest creates Deployment **`central-feeder`** and Service **`feeder`** with annotation **`skupper.io/proxy: http`** so **Skupper** (step 3.d) can expose **`feeder`** to **`edge1`** without a manual `kubectl annotate`.

**Manual flow** (same Quay repo, tag **`:central-feeder-jvm`**):

1. Build and push — **`camel/central-feeder/README.md`** or **`bash deployment/build-push-images.sh central-feeder-jvm`**.
2. **`oc project central`** and **`oc apply -f deployment/central/central-feeder-deployment.yaml`**.
3. If you did not use the YAML annotation, annotate the Service once: **`oc annotate service feeder skupper.io/proxy=http -n central --overwrite`**.

**Optional Route on central** (debug / curl from your laptop; not required for Skupper from edge):

```bash
oc expose svc/feeder -n central
```

Upload example (ZIP with **`images/.../*.jpg`** layout; see **`dataset`** notes in **`camel/central-feeder/README.md`**):

```bash
ROUTE=$(oc get route feeder -n central -o jsonpath='{.spec.host}')
curl -v -T data.zip "https://${ROUTE}/zip?edgeId=edge1"
```

Shorter pointers: **`camel/central-feeder/Readme.txt`**.

<br/>

### Test the end to end solution

This final test validates all the platform stages are healthy. We should see the following processes in motion:

1. A client sends training data for a new product.
1. The feeder system (Camel) ingests the data, stores it in S3, and sends a trigger signal.
1. The delivery system (Camel) receives the signal and triggers the Pipeline.
1. The Pipeline trains a new model and pushes it to S3 storage.
1. The edge manager (Camel) detects a new model and moves it to local S3 storage.
1. The edge ML Server (TensorFlow) detects a new model and hot deploys it.
1. The edge monitor (Camel) can forward Kafka traffic for the edge topic to MQTT (optional observability path when **Edge Monitor** is deployed).
1. The platform has now evolved and capable of detecting the new product.

<br/>

Procedure:

1. Check the current edge model version in `production`.
   
   The `edge1` Minio S3 bucket should show model version `2` under:
   * **production/models/tea_model_b64**

1. Push training data

   Build **`data.zip`** with the **`images/`** layout (see **`camel/central-feeder/README.md`**). Then call **`/zip?edgeId=edge1`** on the feeder HTTP endpoint — either a **Route on `central`** or the **Skupper-exposed** service on **`edge1`** (whatever your cluster exposes; check **`oc get route,svc -n central`** and **`oc get route,svc -n edge1`** for **`feeder`**).

    > [!CAUTION]
    > Large ZIP uploads can take a while.

   Example if you exposed **`feeder`** on **`central`**:

   ```bash
   ROUTE=$(oc get route feeder -n central -o jsonpath='{.spec.host}')
   curl -v -k -T data.zip "https://${ROUTE}/zip?edgeId=edge1"
   ```
1. When the upload completes you should see a new pipeline execution has started.

1. When the pipeline execution completes you should see a new version `3` deployed under:
   * **production/models/tea_model_b64**

1. Test the new model

   Send a new inference request against the ML Server. From the repository **`client/`** directory, run **`./infer.sh`** (see **[Manual inference test (TensorFlow Serving REST)](#manual-inference-test-tensorflow-serving-rest)** for prerequisites, environment variables, and a raw **`curl`** example).


<br/>

### Deploy the AI-powered (intelligent) App

The App connects edge devices to the platform and integrates with the various systems. \
It includes an interface capable of:
* Get price tags for products (inferencing)
* Send training data (data ingesting)
* Monitoring platform activity  


#### Install dependencies

Some components use **Apache Camel K** (community operator), not the legacy **Red Hat Integration – Camel K 1.10.x** line.

* Install **Camel K** from OperatorHub: publisher **The Apache Software Foundation**, channel aligned with your cluster (e.g. **stable** or **latest** for **2.x**). Install **cluster-wide** (or ensure the operator watches **`edge1`**).
* Install the **`kamel` CLI** for the same **major.minor** as the operator (see [Camel K installation](https://camel.apache.org/camel-k/next/installation/installation.html)). Check with:
  ```bash
  kamel version
  oc get csv -A | grep -i camel-k
  ```
* The integration **`price-engine.xml`** targets **Camel 4** DSL used by current Camel K **2.x** runtimes (`platform-http`, `jq`, JSON data formats). If the Integration fails at runtime with missing components, add explicit dependencies, for example:
  ```bash
  kamel run ... --dependency=camel:jackson --dependency=camel:jq
  ```

#### Install systems

Under the **`edge1`** namespace, perform the following actions:

1. Deploy the **Price Engine** (catalogue REST API).
   
   Camel K integration from **`camel/edge-shopper/camel-price`** (`price-engine.xml`). The ConfigMap must be mounted so **`catalogue.json`** appears as **`/deployments/config/catalogue.json`** inside the integration (see `--resource` below).

   Run every command from the **repository root** (so `deployment/…` and `camel/…` paths resolve).

   ```bash
   oc project edge1
   oc create configmap catalogue \
     --from-file=camel/edge-shopper/camel-price/catalogue.json -n edge1 \
     --dry-run=client -o yaml | oc apply -f -
   kamel run camel/edge-shopper/camel-price/price-engine.xml -n edge1 --name price-engine \
     --resource configmap:catalogue@/deployments/config
   ```

   Wait until the integration is ready, then expose HTTP (service name matches the integration name unless overridden):

   ```bash
   oc wait --for=condition=Ready integration/price-engine -n edge1 --timeout=600s
   oc expose svc price-engine -n edge1
   ```

   If your Camel K version uses different mount defaults, inspect the running pod and adjust the `--resource …@path` or the `file:/deployments/config/catalogue.json` URIs in **`price-engine.xml`** accordingly.

   **`catalogue.json`** is shared with **Edge Shopper**. Each product entry may include **`"trainable": true|false`**: price-engine ignores it for pricing; the Shopper **ingestion / training labels** UI lists only **`trainable: true`** (those products must still exist in the same catalogue so **`/item`** and **`/price`** resolve). **`other`** is typically **`trainable: false`**.

1. **Edge Monitor** — use **`camel/edge-monitor/README.md`** and **`deployment/edge/edge-monitor-deployment.yaml`**; **`install-demo-steps.sh`** deploys it after Edge Manager ( **`SKIP_EDGE_MONITOR=1`** to skip). Bridges **Kafka** (topic **`edge1`**, etc.) to **MQTT** on the edge broker.

1. Deploy the *Edge Shopper* (Quarkus + **Camel Quarkus** — same pattern as Edge Manager / Edge Monitor).

   * **Documentation:** **`camel/edge-shopper/Readme.md`**
   * **Image:** `quay.io/<org>/sp-edge-to-cloud-data-pipelines-demo:edge-shopper-jvm` — **`deployment/sp-demo-images.env.sh`**.

   **Build and push:** **`bash deployment/build-push-images.sh edge-shopper-jvm`** (included in **`bash deployment/build-push-images.sh`** with no args).

   **Deploy:** ConfigMap **`catalogue`** must exist (same as Price Engine). **`install-demo-steps.sh`** applies **`deployment/edge/edge-shopper-deployment.yaml`** after Camel K price-engine by default, ensures **`catalogue`**, creates Route **`camel-edge`** → Service **`edge-shopper`**. Skip with **`SKIP_EDGE_SHOPPER=1`**.

   ```bash
   oc project edge1
   oc create configmap catalogue \
     --from-file=camel/edge-shopper/camel-price/catalogue.json -n edge1 \
     --dry-run=client -o yaml | oc apply -f -
   oc apply -f deployment/edge/edge-shopper-deployment.yaml
   oc rollout status deployment/edge-shopper -n edge1 --timeout=300s
   oc create route edge camel-edge --service=edge-shopper -n edge1
   ```

   Open the **camel-edge** route URL in a browser (detection, ingestion with dynamic training labels from **`catalogue.json`**, monitoring).

#### Updating the product catalogue (ConfigMap only — no image rebuild)

Both **price-engine** (Camel K) and **edge-shopper** read the same **`catalogue`** ConfigMap in **`edge1`**. The data key is **`catalogue.json`** (created with **`--from-file=camel/edge-shopper/camel-price/catalogue.json`**). You can parameterize products, prices, and training labels by **only** changing that ConfigMap; you do **not** need to rebuild the Shopper or price-engine images for catalogue edits.

**Recommended (keeps Git as source of truth)**

1. Edit **`camel/edge-shopper/camel-price/catalogue.json`** in your clone (valid JSON; each entry: **`item`**, **`label`**, **`price`**, optional **`trainable`** boolean for Shopper ingestion — see above).
2. Re-apply the ConfigMap from the **repository root**:

   ```bash
   oc project edge1
   oc create configmap catalogue \
     --from-file=camel/edge-shopper/camel-price/catalogue.json -n edge1 \
     --dry-run=client -o yaml | oc apply -f -
   ```

3. **Reload runtimes** so both apps see the new file (mounted volumes are not always picked up instantly; a restart is reliable):

   ```bash
   oc rollout restart deployment/edge-shopper -n edge1
   oc rollout status deployment/edge-shopper -n edge1 --timeout=300s

   oc rollout restart deployment/price-engine -n edge1
   oc rollout status deployment/price-engine -n edge1 --timeout=300s
   ```

   If **`deployment/price-engine`** does not exist yet, restart the integration workload instead, for example:

   ```bash
   oc delete pod -n edge1 -l camel.apache.org/integration=price-engine --wait=true
   ```

**Alternative (cluster only)**

- **`oc edit configmap catalogue -n edge1`** and change the **`catalogue.json`** entry under **`data:`**. Then run the same **`rollout restart`** / pod delete steps as above. Note: this drifts from the file in Git unless you copy changes back into **`camel/edge-shopper/camel-price/catalogue.json`**.

**`install-demo-steps.sh`** uses the same **`oc create configmap catalogue … | apply`** pattern when it provisions Camel K and Edge Shopper, so re-running that apply after an edit is equivalent to step 2.
