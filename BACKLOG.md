# Backlog

Tareas aplazadas para cerrar el solution pattern **Edge-to-Core Data Pipelines for AI/ML** (`sp-edge-to-cloud-data-pipelines-demo`).

## Imágenes GraalVM / nativo

- **edge-manager** y el resto de servicios **Quarkus** del repo: ofrecer de nuevo build **nativo** (menor RAM, arranque más rápido) además del **JVM** actual.
- Coordinar con **`NATIVE_CONTAINER_PLATFORM`** / CI **linux/amd64** y tiempos de compilación Mandrel.
- Comando de referencia: `bash deployment/build-push-images.sh edge-manager-native` → tag **`:edge-manager-native`** en el mismo repo Quay.

## Otros

- (Añade aquí integraciones, operadores, documentación o refactors pendientes.)

- [ ] Corregir y revisar notebook `workbench/export_elyra_pipeline.ipynb` para próximos usos. Pendiente de pruebas/ajustes.
    - Validar rutas de búsqueda, auto-relleno de parámetros, runtime selection, y manejo de catálogos/componentes Elyra.
    - Documentar limitaciones actuales y posibles mejoras.
    - Añadir tests/manuales de export en nuevos entornos RHOAI.