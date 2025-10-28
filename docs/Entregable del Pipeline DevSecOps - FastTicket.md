## Informe de Justificación del Pipeline DevSecOps - FastTicket

**Repositorio:** [https://github.com/fercanap/Projecto-final-testing](https://github.com/fercanap/Projecto-final-testing)

**Acceso temporal a la solución:**

* **Backend:** [http://54.81.153.212/health](http://54.81.153.212/health)
* **Frontend:** [http://34.196.33.223/](http://34.196.33.223/)

*(Disponible hasta el 27 de octubre a las 23:00 CDT)*

**Integrantes:** Fernando Canales & Edwin Morales

### A. Justificación del Orden: SAST antes de DAST (Principio *Shift-Left*)

El pipeline de FastTicket implementa el principio de *Shift-Left Security*, priorizando la detección temprana de vulnerabilidades antes de que el código sea desplegado o expuesto a entornos de staging o producción. Por esta razón, las pruebas **SAST (Static Application Security Testing)** se ejecutan antes de **DAST (Dynamic Application Security Testing)**.

El SAST analiza el código fuente y las dependencias directamente desde el repositorio, permitiendo detectar errores lógicos, inyecciones, fugas de información o manejo inadecuado de secretos antes de construir las imágenes Docker. Esto reduce costos de corrección y evita vulnerabilidades en fases posteriores.

Por el contrario, DAST analiza la aplicación ya desplegada. Si se ejecutara primero, requeriría un entorno activo (mayor tiempo y costo) y podría exponer un servicio inseguro. Colocar SAST antes garantiza que el código que llega a staging ya ha pasado controles estáticos y de calidad.

### B. Equilibrio entre Seguridad y Velocidad

El pipeline de FastTicket fue diseñado para cumplir simultáneamente con los requisitos de **alta seguridad** y **alta velocidad** mediante automatización, paralelismo y gates de aprobación.

* **Seguridad continua**: Se integran herramientas automáticas en cada fase:

  * *CodeQL* para SAST (análisis de código fuente).
  * *pip-audit* y *npm audit* para SCA (Software Composition Analysis) en backend y frontend.
  * *Trivy* para escaneo de contenedores durante el *build*.
  * *tfsec* y *checkov* para revisar configuraciones IaC de Terraform.
  * *OWASP ZAP Baseline* ejecutado sobre el entorno *staging* para DAST.
* **Velocidad del pipeline**:

  * Uso de *GitHub Actions* con *caching* y *concurrency groups* para reducir tiempos de ejecución.
  * Los *jobs* SAST, SCA y build corren en paralelo.
  * Las validaciones solo detienen el flujo si los *gates* detectan vulnerabilidades de severidad *High* o *Critical*.

El diseño permite que los equipos desplieguen rápido en *staging* sin comprometer la seguridad, siguiendo el principio de *Continuous Security* y *Fast Feedback Loops*.

### C. Protecciones Críticas del *Hardening* en FastTicket

El proceso de *hardening* del entorno busca proteger la **integridad, confidencialidad y disponibilidad** del sistema FastTicket, que maneja datos sensibles de usuarios y transacciones tipo e-commerce. Las medidas clave incluyen:

1. **Protección de secretos y credenciales**: uso de *Kubernetes Secrets* cifrados y autenticación OIDC entre GitHub y AWS (sin llaves estáticas).
2. **Seguridad de la cadena de suministro**: validación de dependencias (SCA), imágenes base minimalistas, y escaneo Trivy para evitar vulnerabilidades en contenedores.
3. **Control de red y RBAC**: roles mínimos en EKS, *namespaces* separados por entorno y límites de acceso basados en *least privilege*.
4. **Hardening de Kubernetes y EKS**: actualizaciones automáticas, políticas *PodSecurity*, y ejecución de pods como usuarios no privilegiados.
5. **Disponibilidad y resiliencia**: uso de *LoadBalancers* y *health probes* para garantizar continuidad del servicio.

Estas acciones aseguran que el entorno *staging* y *production* mantengan una postura de seguridad sólida sin afectar el *time-to-deploy*. El enfoque prioriza la protección de datos personales, tokens de pago y la prevención de vulnerabilidades comunes como inyecciones, accesos indebidos o configuraciones inseguras.

---

**Conclusión:**
El pipeline DevSecOps de FastTicket demuestra un equilibrio efectivo entre velocidad y seguridad mediante la integración de controles automáticos, el cumplimiento del principio *Shift-Left* y la aplicación de *hardening* en todo el ciclo de vida, garantizando un despliegue confiable y seguro.
