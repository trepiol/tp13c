# ZAP by Checkmarx — Manual técnico paso a paso

Escaneos de seguridad en Docker y Kubernetes. Spider · Passive Scan · Active Scan · Fuzzing · Automation Framework.

Herramienta: ZAP by Checkmarx (ex OWASP ZAP). Versión de referencia: `zap-stable` (imagen Docker oficial `zaproxy/zaproxy`). Audiencia: DevSecOps, pentesters, equipos de seguridad. Plataformas cubiertas: Docker · Kubernetes. Modalidades: Passive Scan · Active Scan · Spider (tradicional + AJAX) · Fuzzing. Marco de automatización: Automation Framework (YAML), recomendado desde 2024. Fecha de elaboración: julio 2026.

Este manual es de referencia general (no es específico de Kubernetes); el paso a paso de este TP puntual está en el `README.md` de esta misma carpeta.

## Ruta de aprendizaje

Este manual, tal como está en la consigna original, plantea 8 capítulos que llevan de cero a un flujo completo de escaneo (Docker → Automation Framework), con comandos exactos. El índice original prometía más capítulos (9 a 13, sobre despliegue en Kubernetes, interpretación de alertas, generación de reportes, integración CI/CD y checklist final) y una tabla de troubleshooting de errores comunes, pero el documento fuente no llega a desarrollarlos — se corta después del punto 8.3. Se deja el índice completo tal cual figura en la consigna (abajo) para que quede claro qué prometía, pero los capítulos 9 a 13 **no existen** en este manual: la parte de Kubernetes específica de este TP está resuelta en el `README.md`, no acá.

### Índice de contenidos

1. Conceptos clave y arquitectura de ZAP
2. Instalación de la imagen Docker oficial
3. Escaneo Pasivo (Passive Scan) en Docker
4. Spider Tradicional en Docker
5. Spider AJAX en Docker
6. Escaneo Activo (Active Scan) en Docker
7. Fuzzing en Docker
8. Automation Framework (YAML) — método recomendado
9. Despliegue en Kubernetes *(no desarrollado en el documento original)*
10. Lectura e interpretación de alertas *(no desarrollado en el documento original)*
11. Generación de reportes *(no desarrollado en el documento original)*
12. Integración CI/CD *(no desarrollado en el documento original)*
13. Buenas prácticas y checklist final *(no desarrollado en el documento original)*

## 1. Conceptos clave y arquitectura de ZAP

ZAP (Zed Attack Proxy) es una herramienta DAST (Dynamic Application Security Testing) de código abierto mantenida actualmente por Checkmarx bajo la Linux Foundation. Actúa como proxy man-in-the-middle entre el navegador/cliente y la aplicación objetivo, interceptando y analizando todo el tráfico HTTP/HTTPS.

### 1.1 Modalidades de análisis

**Passive Scan:** ZAP analiza todo el tráfico que pasa por su proxy sin modificar peticiones ni respuestas. Es seguro ejecutarlo contra producción, no lanza ataques. Detecta headers de seguridad ausentes, cookies inseguras, información sensible en respuestas, versiones de librerías vulnerables.

**Active Scan:** ZAP lanza ataques reales contra el objetivo: SQLi, XSS, SSRF, command injection, etc. Solo ejecutar con autorización explícita por escrito sobre el entorno objetivo. Puede generar carga significativa y alterar datos en la aplicación.

**Spider (tradicional):** rastreador que descubre URLs analizando el HTML de las respuestas (etiquetas `<a>`, formularios, etc.). Rápido pero limitado en aplicaciones SPA / heavy JavaScript.

**Spider AJAX (Modern Spider):** usa un navegador real (Selenium/Playwright) para ejecutar JavaScript y descubrir rutas dinámicas. Más lento pero imprescindible en Angular, React, Vue, Next.js.

**Fuzzing:** envía grandes volúmenes de datos inesperados/malformados a parámetros específicos. Técnica complementaria al Active Scan para encontrar vulnerabilidades en entradas concretas. Requiere identificar primero la petición objetivo mediante Spider o exploración manual.

### 1.2 Imágenes Docker oficiales

ZAP publica sus imágenes en GitHub Container Registry (ghcr.io). Las imágenes en Docker Hub (`owasp/`) están obsoletas desde 2023.

```text
ghcr.io/zaproxy/zaproxy:stable   ← imagen recomendada para producción/CI
ghcr.io/zaproxy/zaproxy:weekly   ← últimas funcionalidades, puede ser inestable
ghcr.io/zaproxy/zaproxy:bare     ← solo ZAP, sin scripts de escaneo empaquetados
```

Las imágenes `owasp/zap2docker-stable` y `owasp/zap2docker-weekly` en Docker Hub están deprecadas. Usar siempre `ghcr.io/zaproxy/zaproxy`.

### 1.3 Escaneos empaquetados vs Automation Framework

ZAP ofrece dos aproximaciones de automatización: **Packaged Scans** (`baseline`, `full-scan`, `api-scan`), scripts Python preconfigurados que simplifican la ejecución por línea de comandos, ideales para comenzar; y el **Automation Framework** (AF), un archivo YAML que define todos los pasos del escaneo, el método recomendado para flujos no triviales, CI/CD, y cualquier configuración avanzada.

Para entornos productivos y Kubernetes, usar siempre el Automation Framework. Los packaged scans son el punto de entrada más rápido.

## 2. Instalación de la imagen Docker oficial

Prerrequisitos: Docker Engine 20.x o superior instalado y el daemon activo.

```bash
# 2.1 Descargar la imagen
docker pull ghcr.io/zaproxy/zaproxy:stable

# 2.2 Verificar la imagen
docker images | grep zaproxy
```

### 2.3 Estructura de directorios de trabajo recomendada

Crear un directorio local que se montará como volumen en el contenedor para guardar reportes y configuraciones:

```bash
mkdir -p ~/zap-work/{reports,config,scripts}
cd ~/zap-work
```

El flag `-v $(pwd):/zap/wrk/:rw` monta el directorio actual en `/zap/wrk` dentro del contenedor. Todos los reportes generados aparecerán en tu directorio local. En PowerShell usar `${PWD}` en lugar de `$(pwd)`.

## 3. Escaneo Pasivo (Passive Scan) en Docker — Baseline Scan

El Baseline Scan es el método más sencillo para iniciar. Ejecuta el Spider tradicional durante 1 minuto por defecto y luego espera a que termine el escaneo pasivo. No realiza ataques activos.

```bash
# 3.1 Comando básico
docker run -t ghcr.io/zaproxy/zaproxy:stable zap-baseline.py \
  -t https://tu-aplicacion.ejemplo.com

# 3.2 Comando con reporte HTML
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py \
  -t https://tu-aplicacion.ejemplo.com \
  -r reports/baseline-report.html
```

### 3.3 Parámetros más usados del baseline scan

| Parámetro | Ejemplo | Descripción |
|---|---|---|
| `-t` | `-t https://app.com` | URL objetivo (obligatorio) |
| `-r` | `-r report.html` | Reporte HTML en `/zap/wrk/` |
| `-J` | `-J report.json` | Reporte JSON |
| `-m` | `-m 5` | Minutos de spider (def: 1) |
| `-g` | `-g gen.conf` | Genera archivo de config de reglas |
| `-c` | `-c config.conf` | Usa archivo de config personalizado |
| `-I` | `-I` | No falla al encontrar alertas (útil en CI) |

### 3.4 Personalizar reglas con archivo de configuración

Primero generar el archivo de configuración por defecto:

```bash
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py -t https://tu-app.com -g gen.conf
```

Editar `gen.conf` (quedará en `~/zap-work/gen.conf`):

```text
# Cambiar WARN a IGNORE para ignorar la regla
# Cambiar WARN a FAIL para que el scan falle si encuentra esta alerta
10020	WARN	(X-Frame-Options Header)
10038	IGNORE	(Content Security Policy)
10049	FAIL	(Storable and Cacheable Content)
```

## 4. Spider Tradicional en Docker

El Spider tradicional recorre la aplicación descubriendo URLs al analizar el HTML: etiquetas `<a>`, atributos `href`, formularios, recursos referenciados. Es el punto de partida para cualquier análisis.

### 4.1 Ejecutar spider en modo daemon y usar la API

Para controlar ZAP por API REST, lanzarlo como daemon:

```bash
docker run -u zap -p 8080:8080 -d \
  ghcr.io/zaproxy/zaproxy:stable \
  zap.sh -daemon -host 0.0.0.0 -port 8080 \
  -config api.addrs.addr.name=.* \
  -config api.addrs.addr.regex=true
```

### 4.2 Iniciar spider vía API REST

```bash
# Iniciar spider contra la URL objetivo
curl "http://localhost:8080/JSON/spider/action/scan/?url=https://tu-app.com"

# Consultar progreso del spider (0-100)
curl "http://localhost:8080/JSON/spider/view/status/?scanId=0"

# Obtener URLs descubiertas
curl "http://localhost:8080/JSON/spider/view/results/?scanId=0"
```

### 4.3 Spider dentro del Full Scan (recomendado para Docker)

El full-scan ejecuta spider + passive scan + active scan en un solo comando:

```bash
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap-full-scan.py \
  -t https://tu-app.com \
  -r reports/full-report.html
```

El full scan puede tardar mucho tiempo (horas en aplicaciones grandes) porque ejecuta el Active Scan completo. Usar con precaución y solo con autorización.

## 5. Spider AJAX (Modern Spider) en Docker

El Spider AJAX usa un navegador real controlado por Selenium/Playwright para ejecutar JavaScript y descubrir rutas dinámicas. Es esencial para SPAs (Single Page Applications).

### 5.1 Activar AJAX spider en el baseline scan

```bash
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py \
  -t https://tu-app.com \
  -j \
  -r reports/ajax-baseline-report.html
```

El flag `-j` activa el AJAX spider después del spider tradicional.

### 5.2 AJAX spider vía API REST

```bash
# Iniciar AJAX spider
curl "http://localhost:8080/JSON/ajaxSpider/action/scan/?url=https://tu-app.com"

# Estado: running o stopped
curl "http://localhost:8080/JSON/ajaxSpider/view/status/"

# URLs descubiertas por el AJAX spider
curl "http://localhost:8080/JSON/ajaxSpider/view/results/"
```

### 5.3 Configuración avanzada del AJAX spider vía Automation Framework

```yaml
jobs:
  - type: spiderAjax
    parameters:
      url: "https://tu-app.com"
      maxDuration: 10          # minutos máximos
      maxCrawlDepth: 10
      numberOfBrowsers: 4      # navegadores paralelos
      browserId: "firefox-headless"
      clickElemsOnce: true
      randomInputs: true
```

Para aplicaciones con autenticación, configurar primero el contexto de autenticación en el YAML del Automation Framework antes de lanzar el AJAX spider.

## 6. Escaneo Activo (Active Scan) en Docker

El Active Scan lanza ataques reales contra la aplicación para descubrir vulnerabilidades explotables: SQL Injection, XSS, SSRF, Command Injection, Path Traversal, CSRF, etc. Obligatorio: obtener autorización escrita antes de ejecutar cualquier escaneo activo. Puede modificar datos, generar carga o bloquear servicios.

### 6.1 Full Scan (spider + passive + active)

```bash
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap-full-scan.py \
  -t https://tu-app.com \
  -j \
  -r reports/full-scan-report.html \
  -J reports/full-scan-report.json
```

### 6.2 Active Scan vía API REST

```bash
# Iniciar active scan (asegurarse de haber hecho spider antes)
curl "http://localhost:8080/JSON/ascan/action/scan/?url=https://tu-app.com&recurse=true"

# Progreso del active scan (0-100)
curl "http://localhost:8080/JSON/ascan/view/status/?scanId=0"

# Alertas encontradas
curl "http://localhost:8080/JSON/core/view/alerts/?baseurl=https://tu-app.com"
```

### 6.3 Active Scan para APIs (OpenAPI/Swagger/GraphQL)

```bash
# Escaneo de API definida en OpenAPI
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap-api-scan.py \
  -t https://tu-app.com/openapi.json \
  -f openapi \
  -r reports/api-scan-report.html

# Escaneo de API GraphQL
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap-api-scan.py \
  -t https://tu-app.com/graphql \
  -f graphql \
  -r reports/graphql-scan-report.html
```

### 6.4 Configurar política de escaneo activo (scan policy)

En el Automation Framework se puede configurar la política del active scan para excluir o ajustar reglas:

```yaml
jobs:
  - type: activeScan
    parameters:
      context: "Mi Contexto"
      policy: ""              # vacío = política por defecto
      maxRuleDurationInMins: 5
      maxScanDurationInMins: 60
      addQueryParam: false
      delayInMs: 0
      handleAntiCSRFTokens: true
```

## 7. Fuzzing en Docker

El Fuzzing en ZAP envía datos inesperados, malformados o maliciosos a parámetros específicos de peticiones HTTP para descubrir vulnerabilidades que el Active Scan estándar podría pasar por alto.

### 7.1 Fuzzing mediante la GUI de ZAP con Webswing (Docker)

Para usar la interfaz gráfica de ZAP desde Docker vía navegador:

```bash
docker run -u zap -p 8080:8080 -p 8090:8090 \
  -i ghcr.io/zaproxy/zaproxy:stable \
  zap-webswing.sh
```

Abrir en el navegador: `http://localhost:8080/zap/`. Pasos para fuzzing en la GUI: explorar la aplicación o ejecutar el spider para capturar peticiones; en el panel de History o Spider, clic derecho sobre la petición a fuzzear; seleccionar "Attack" → "Fuzz..."; en el diálogo Fuzzer, seleccionar el parámetro objetivo (resaltar el valor del campo); clic en "Add..." para añadir payloads; seleccionar el tipo de payload (File Fuzzers, Strings, Numberzz, Regex, Script); configurar opciones de concurrencia y retardo; clic en "Start Fuzzer".

### 7.2 Tipos de payloads disponibles

- **File Fuzzers (jbrofuzz):** listas predefinidas para SQLi, XSS, LDAP Injection, OS Command Injection, etc. Incluidas en el add-on "Fuzzer" de ZAP.
- **Strings:** lista manual de valores a probar.
- **Regex:** genera valores basados en expresión regular.
- **Numberzz:** secuencias numéricas (útil para pruebas de IDOR).
- **Script:** payload generado por script Groovy/Python personalizado.

### 7.3 Fuzzing vía API REST (automatizado)

```bash
# Iniciar fuzzer en una petición específica (messageId desde History)
curl "http://localhost:8080/JSON/fuzzer/action/startFuzzer/?" \
  -d "httpMessageId=42&fuzzers=[{name:'jbrofuzz/SQL Injection - Error Based'}]"
```

### 7.4 Fuzzing automatizado con Automation Framework

```yaml
jobs:
  - type: script
    parameters:
      action: add
      type: httpsender
      engine: "ECMAScript"
      name: "fuzzer-script"
      file: "/zap/wrk/scripts/fuzzer.js"
```

El fuzzing automatizado complejo (IDOR, fuzzing de múltiples parámetros) se gestiona mejor con scripts personalizados a través del Automation Framework o la API REST de ZAP.

## 8. Automation Framework (YAML) — método recomendado

El Automation Framework es el método recomendado por el equipo de ZAP para cualquier automatización no trivial. Controla ZAP completamente a través de un único archivo YAML.

### 8.1 Estructura base del archivo YAML

```yaml
---
env:
  contexts:
    - name: "Mi Aplicacion"
      urls:
        - "https://tu-app.com"
      includePaths:
        - "https://tu-app.com/.*"
      excludePaths:
        - "https://tu-app.com/logout.*"
  parameters:
    failOnError: true
    failOnWarning: false
    progressToStdout: true

jobs:
  - type: passiveScan-config
    parameters:
      maxAlertsPerRule: 10
      scanOnlyInScope: true

  - type: spider
    parameters:
      context: "Mi Aplicacion"
      url: "https://tu-app.com"
      maxDuration: 5
      maxDepth: 10

  - type: spiderAjax
    parameters:
      context: "Mi Aplicacion"
      url: "https://tu-app.com"
      maxDuration: 5

  - type: passiveScan-wait
    parameters:
      maxDuration: 10

  - type: activeScan
    parameters:
      context: "Mi Aplicacion"
      maxScanDurationInMins: 60

  - type: report
    parameters:
      template: "traditional-html"
      reportDir: "/zap/wrk/reports"
      reportFile: "zap-report"
    risks:
      - high
      - medium
      - low
      - informational
```

### 8.2 Ejecutar el Automation Framework en Docker

```bash
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap.sh -cmd -autorun /zap/wrk/zap.yaml
```

### 8.3 YAML con autenticación por formulario

```yaml
env:
  contexts:
    - name: "App con Login"
      urls:
        - "https://tu-app.com"
      authentication:
        method: "form"
        parameters:
          loginPageUrl: "https://tu-app.com/login"
          loginRequestUrl: "https://tu-app.com/auth/login"
          loginRequestBody: "username={%username%}&password={%password%}"
        verification:
          method: "response"
          loggedInRegex: "\\QWelcome\\E"
          loggedOutRegex: "\\QLogin\\E"
      sessionManagement:
        method: "cookie"
      users:
        - name: "testuser"
          credentials:
            username: "user@ejemplo.com"
            password: "${ZAP_PASSWORD}"
```

Nunca hardcodear passwords en el YAML. Usar variables de entorno como `${ZAP_PASSWORD}` y pasarlas al contenedor con `-e ZAP_PASSWORD=valor`.
