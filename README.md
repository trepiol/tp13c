# TP13C OWASP ZAP GitHub Actions Kubernetes K3s K3d local

Para integrar la aplicación de notas con el stack de monitoreo y OWASP ZAP en un clúster de Kubernetes (k3s/k3d), se presenta el siguiente plan de trabajo estructurado en 4 sprints. Este plan combina las bases técnicas de los TP07 (CI/CD), TP08 (Monitoreo), TP09/TP10 (Kubernetes/Helm) y la documentación de ZAP Automation Framework.

## Antes de arrancar

Esta carpeta ya trae armado y probado todo lo que corresponde a guías anteriores, ordenado por de dónde sale cada cosa:

- `guia-06/app/` — Notes App (backend Flask + PostgreSQL + frontend Nginx), la misma de TP06/TP07, con el backend ya instrumentado con `prometheus_client` y el endpoint `/metrics` (esto es parte del Sprint 2, ver más abajo).
- `guia-08/k8s/monitoring/` — manifiestos de Prometheus, Grafana, Node Exporter y cAdvisor.
- `guia-09/k8s/base/` — Namespace, Secret, PVC de Postgres, Deployments y Services de backend/frontend, e Ingress.
- `scripts/create-cluster.sh` y `scripts/build-and-deploy.sh` — arman el clúster k3d y despliegan todo lo anterior.

Lo que falta y es el objetivo real de este TP (Sprints 3 y 4): el plan de ZAP, el Job de Kubernetes que lo ejecuta, el job de seguridad del pipeline y el script de verificación final. Con eso vas a terminar con una carpeta `guia-13/` propia, igual que las anteriores.

## Sprint 1: Infraestructura K8s y Despliegue de la App

Objetivo: preparar el clúster local y desplegar la aplicación de notas.

Preparación del clúster con k3d — crear el clúster exponiendo los puertos necesarios para la aplicación, Grafana y Prometheus:

```bash
k3d cluster create notes-cluster -p "8080:80@loadbalancer" -p "3000:3000@loadbalancer" -p "9090:9090@loadbalancer" --agents 2
```

Despliegue de la aplicación: utilizar los manifiestos del TP09 (Namespace, Secret, PVC, Deployment, Service), configurando la base de datos PostgreSQL mediante un PersistentVolumeClaim para asegurar la persistencia.

Configuración de Ingress: instalar el NGINX Ingress Controller para gestionar el acceso vía hostname, y definir las rutas para el frontend y la API en el manifiesto de Ingress.

Todo esto ya está resuelto en `scripts/create-cluster.sh` (usa el puerto 18080 en vez de 8080 para no chocar con otros servicios locales, y agrega health-checks de puertos antes de crear el clúster) y en `scripts/build-and-deploy.sh`, que aplica en orden los manifiestos de `guia-09/k8s/base/`. Corré:

```bash
chmod +x scripts/*.sh
./scripts/create-cluster.sh
./scripts/build-and-deploy.sh
```

El segundo script también instala el NGINX Ingress Controller con Helm antes de aplicar los manifiestos, así que al terminar ya tenés la app respondiendo en `http://127.0.0.1:18080` (con el header `Host: notes.local`).

## Sprint 2: Observability Stack (Los 4 Componentes)

Objetivo: instrumentar la app e integrar el monitoreo completo.

Instrumentación del backend: importar `prometheus_client` en la app Flask para exponer métricas en el endpoint `/metrics` (requests, latencia, errores). Ya está hecho en `guia-06/app/backend/app.py`: `app_requests_total` (Counter por método/endpoint/status), `app_request_duration_seconds` (Histogram de latencia), `app_notes_total` (Gauge con la cantidad de notas en la DB), `app_db_errors_total` (Counter de errores de conexión) y `app_info` (Gauge con versión/entorno), todo expuesto en `/metrics` con `generate_latest()`.

Despliegue del monitoreo:

- Prometheus: configurar los jobs de scrape para la app, Node Exporter y cAdvisor.
- Node Exporter: desplegar como DaemonSet para obtener métricas del host (CPU, RAM, disco).
- cAdvisor: desplegar para recolectar estadísticas de uso de los contenedores.
- Grafana: configurar el provisioning automático de la fuente de datos (Prometheus) y el dashboard JSON con los paneles de métricas.

Los cuatro manifiestos están en `guia-08/k8s/monitoring/` (`05-prometheus.yaml`, `06-node-exporter.yaml`, `07-cadvisor.yaml`, `08-grafana.yaml`) y `build-and-deploy.sh` ya los aplica y espera cada rollout.

Verificación local: utilizar un script de verificación similar al del TP08 para asegurar que todos los servicios y targets estén "UP". Con el clúster arriba:

```bash
curl http://127.0.0.1:9090/-/ready
curl http://127.0.0.1:9090/api/v1/targets
curl http://127.0.0.1:3000/api/health
```

Grafana queda accesible en `http://127.0.0.1:3000`.

## Sprint 3: CI/CD y Preparación de OWASP ZAP

Objetivo: automatizar el pipeline y configurar el framework de seguridad.

GitHub Actions Workflow: basarse en el workflow del TP07 con jobs de Lint, Test y Build/Push. Configurar los secretos en GitHub: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `KUBECONFIG` (base64) y los necesarios para ZAP.

Creá `.github/workflows/autoscan.yml` en la raíz de esta carpeta con al menos estos jobs:

```yaml
name: TP13C CI CD and ZAP

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validar Python y shell
        run: |
          python -m compileall -q guia-06/app/backend/app.py
          bash -n scripts/*.sh

  test:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - name: Construir imágenes como prueba
        run: |
          docker build -t notes-backend:test guia-06/app/backend
          docker build -t notes-frontend:test guia-06/app/frontend

  build_push:
    runs-on: ubuntu-latest
    needs: test
    if: github.event_name == 'push'
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: guia-06/app/backend
          push: true
          tags: ${{ secrets.DOCKERHUB_USERNAME }}/notes-backend:${{ github.sha }}
      - uses: docker/build-push-action@v6
        with:
          context: guia-06/app/frontend
          push: true
          tags: ${{ secrets.DOCKERHUB_USERNAME }}/notes-frontend:${{ github.sha }}
```

El job `zap` (Sprint 4) se agrega abajo.

Plan de ZAP (Automation Framework): crear un archivo `zap.yaml` para controlar el escaneo. Este archivo debe incluir:

- Environment: URL de la app en el clúster.
- Jobs: `spider` (rastreo), `ajaxSpider` (para el frontend dinámico), `activeScan` (ataques) y `report`.

Creá `guia-13/zap.yaml` (nueva carpeta, es lo que este TP te toca armar):

```yaml
---
env:
  contexts:
    - name: notes-kubernetes
      urls:
        - "http://frontend-service.devops-portfolio.svc.cluster.local"
      includePaths:
        - "http://frontend-service\\.devops-portfolio\\.svc\\.cluster\\.local/.*"
  parameters:
    failOnError: true
    failOnWarning: false
    progressToStdout: true

jobs:
  - type: spider
    parameters:
      context: notes-kubernetes
      url: "http://frontend-service.devops-portfolio.svc.cluster.local"
      maxDuration: 2

  - type: spiderAjax
    parameters:
      context: notes-kubernetes
      url: "http://frontend-service.devops-portfolio.svc.cluster.local"
      maxDuration: 2
      browserId: firefox-headless

  - type: passiveScan-wait
    parameters:
      maxDuration: 5

  - type: activeScan
    parameters:
      context: notes-kubernetes
      policy: "Default Policy"
      maxScanDurationInMins: 5

  - type: report
    parameters:
      template: traditional-html
      reportDir: /zap/wrk/reports
      reportFile: zap-k8s-report.html
      reportTitle: "Notes App Kubernetes - Security Scan"

  - type: report
    parameters:
      template: traditional-json
      reportDir: /zap/wrk/reports
      reportFile: zap-k8s-report.json
      reportTitle: "Notes App Kubernetes - Security Scan"
```

Usamos `frontend-service.devops-portfolio.svc.cluster.local` (el DNS interno del Service) en vez de `notes.local`/Ingress: así ZAP le pega directo al Service sin depender de que el Ingress esté expuesto, y funciona igual corriendo el escaneo como Job dentro del clúster (que es lo que hacemos en el Sprint 4).

Configuración de Fuzzing: definir payloads personalizados para probar endpoints críticos de la API de notas (creación/eliminación). El Active Scan de arriba ya prueba payloads sobre `/api/notes` automáticamente (inyección, XSS) al descubrir esos endpoints por el Spider; si querés fuzzing dirigido a un parámetro puntual, se agrega un job `type: script` con un fuzzer propio, como se explica en la sección de Fuzzing del manual de ZAP (`MANUAL-ZAP.md`).

## Sprint 4: Integración de Seguridad y Análisis

Objetivo: ejecutar escaneos no triviales en el pipeline y auditar resultados.

Job de seguridad en GitHub Actions: agregar un paso que ejecute la imagen `zaproxy/zap-stable` utilizando el plan creado:

```yaml
- name: ZAP Scan
  run: |
    docker run -v $(pwd):/zap/wrk/:rw -t zaproxy/zap-stable zap.sh -cmd -autorun /zap/wrk/zap.yaml
```

Ese comando funciona si ZAP y la app comparten red directamente (por ejemplo con Docker Compose, como en TP13B). Acá la app vive **dentro de un clúster de Kubernetes**, así que en vez de correr ZAP como contenedor suelto lo corremos como **Job de Kubernetes**, que sí puede resolver `frontend-service.devops-portfolio.svc.cluster.local` por DNS interno. Creá `guia-13/k8s/04-zap-job.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: zap-reports
  namespace: devops-portfolio
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: zap-automation-plan
  namespace: devops-portfolio
data:
  zap.yaml: |
    # (pegar acá el contenido de guia-13/zap.yaml)
---
apiVersion: batch/v1
kind: Job
metadata:
  name: zap-security-scan
  namespace: devops-portfolio
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: zap
          image: ghcr.io/zaproxy/zaproxy:stable
          command: ["zap.sh"]
          args: ["-cmd", "-port", "8091", "-autorun", "/zap/config/zap.yaml"]
          volumeMounts:
            - {name: plan, mountPath: /zap/config, readOnly: true}
            - {name: reports, mountPath: /zap/wrk/reports}
      volumes:
        - {name: plan, configMap: {name: zap-automation-plan}}
        - {name: reports, persistentVolumeClaim: {claimName: zap-reports}}
```

Y agregá el job `zap` al workflow:

```yaml
  zap:
    runs-on: ubuntu-latest
    needs: [lint, test]
    steps:
      - uses: actions/checkout@v4
      - name: Instalar k3d
        run: curl --fail --silent https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
      - name: Crear clúster y desplegar
        run: |
          chmod +x scripts/*.sh
          ./scripts/create-cluster.sh
          ./scripts/build-and-deploy.sh
      - name: Ejecutar ZAP contra el clúster local
        run: |
          kubectl apply -f guia-13/k8s/04-zap-job.yaml
          kubectl wait --for=condition=complete job/zap-security-scan -n devops-portfolio --timeout=12m
      - name: Subir reportes ZAP
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: zap-kubernetes-reports
          path: guia-13/reportes/
```

Un runner de GitHub Actions no puede llegar al k3d que corre en tu máquina, así que el job `zap` crea su **propio** clúster efímero dentro del runner (por eso reinstala k3d y vuelve a correr los scripts del Sprint 1) y recién ahí lanza el Job de ZAP contra ese clúster nuevo.

Análisis de resultados: configurar el job para que genere reportes en formato HTML o SARIF JSON, y subir el reporte como artifact de la acción de GitHub para su revisión. Ya está en el paso de arriba (`actions/upload-artifact@v4`).

Script de verificación final: generar un script que automatice el diagnóstico de red (TP04) y el estado del clúster (TP09) post-despliegue. Creá `guia-13/scripts/verificar-tp13c.sh` que compruebe: nodos `Ready`, rollouts de los 7 componentes, Ingress y PVC, `/health` y `/metrics` de la app vía Ingress, targets de Prometheus `UP`, salud de Grafana, y estado del Job de ZAP. Para extraer los reportes del PVC hacia tu disco (el Job los deja en un volumen dentro del clúster, no en tu filesystem), necesitás además un script tipo `guia-13/scripts/extract-zap-reports.sh` que monte el mismo PVC en un pod temporal y haga `kubectl cp`.

Portfolio Integrador: documentar el proceso completo en el README.md principal, incluyendo screenshots del dashboard de Grafana y las alertas de ZAP.

## Instrucciones para Secretos y Verificación

Secretos necesarios: `POSTGRES_PASSWORD`, `GRAFANA_PASSWORD`, `ZAP_API_KEY` (si se usa la API de ZAP).

Script de verificación local: debe realizar un ping al host de Ingress, un curl al endpoint de salud de la app y verificar que el dashboard de Grafana responda en el puerto 3000.

Este plan asegura que el desarrollo sea incremental y que cada componente esté validado antes de pasar a la integración de seguridad avanzada con OWASP ZAP.

En la práctica, para que el workflow corra sin fallar solo hace falta cargar `DOCKERHUB_USERNAME` (tu usuario de Docker Hub, no el de GitHub) y `DOCKERHUB_TOKEN` como Secrets de GitHub (el job `zap` crea su propio clúster, así que no depende de `KUBECONFIG`; `POSTGRES_PASSWORD`/`GRAFANA_PASSWORD`/`ZAP_API_KEY` quedan documentados para cuando este pipeline apunte a un entorno real en vez de un clúster efímero).

## Estructura del proyecto

Estructura de referencia tal como aparece en la consigna original:

```text
k3d-zap-project/
├── .github/workflows/
│   └── autoscan.yml              ← pipeline completo (4 jobs)
├── k8s/base/
│   ├── 00-namespace.yaml         ← namespace devops-portfolio
│   ├── 01-postgres.yaml          ← Deployment + PVC + Secret
│   ├── 02-backend.yaml           ← Deployment Flask/Gunicorn + Service
│   ├── 03-frontend.yaml          ← Deployment Nginx + Service + Ingress
│   └── 04-zap-job.yaml           ← Job ZAP + PVC reportes + ConfigMap AF
├── app/
│   ├── backend/                  ← Flask app.py + Dockerfile + requirements
│   ├── frontend/                 ← Dockerfile Nginx
│   └── nginx/nginx.conf          ← proxy reverso a backend-service:5000
└── scripts/
    ├── create-cluster.sh         ← crea k3d + registry local
    ├── build-and-deploy.sh       ← build, push e deploy
    └── extract-zap-reports.sh    ← copia reportes del PVC al host
```

(En la consigna original el namespace de ejemplo era `flask-app` y Postgres
aparecía como `StatefulSet`; acá quedaron `devops-portfolio` y `Deployment`
para ser fieles a TP09 — ver `guia-09/k8s/base/`.)

En esta carpeta esa misma estructura está repartida por guía de origen:
`k8s/base/00..03` es `guia-09/k8s/base/`, la parte de observabilidad que no
está en el listado de arriba (porque el listado es solo de la app) es
`guia-08/k8s/monitoring/`, `app/` es `guia-06/app/`, y `k8s/base/04-zap-job.yaml`
junto con `extract-zap-reports.sh` y `verificar-tp13c.sh` van en `guia-13/`
— es lo que construís vos en este TP.

## Referencia de ZAP

El resto de la consigna original incluye un manual general de OWASP ZAP en
Docker (conceptos, imágenes oficiales, Passive Scan, Spider, Spider AJAX,
Active Scan, Fuzzing y Automation Framework) que no es específico de
Kubernetes pero sirve para entender qué hace cada job del plan antes de
tocarlo. Está en [`MANUAL-ZAP.md`](./MANUAL-ZAP.md).

## Detener el clúster

```bash
k3d cluster delete notes-cluster
```
