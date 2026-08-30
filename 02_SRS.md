# SRS — Secretaria Virtual con IA

**Proyecto:** Secretaria Virtual con IA  
**Repositorio previsto:** `saldiviapablo/secretaria`  
**Documento:** `02_SRS.md`  
**Versión:** 1.1  
**Fecha:** 2026-08-29  
**Estado:** APROBADO Y CONGELADO — Baseline SRS V1  
**Documento fuente:** `01_PRD.md`

---

# 0. Resultado de auditoría

Esta versión incorpora una auditoría técnica y de coherencia contra el PRD V1 aprobado, las decisiones funcionales tomadas durante el diseño y las capacidades/limitaciones actuales de los componentes previstos.

Se agregaron o reforzaron especialmente:

- límites y fallback para archivos grandes de Telegram;
- ejecución de n8n en el NAS como objetivo de despliegue de V1, sin ejecutar modelos de IA localmente;
- protección contra prompt injection proveniente de documentos, páginas web, diagramas o transcripciones;
- backups y pruebas de restauración para que “memoria permanente” no dependa de una sola plataforma;
- hechos históricos con fecha de validez y fecha de registro;
- experiencia conversacional y trato de la secretaria;
- monitoreo operativo y alertas de fallos;
- control de costos y uso de APIs;
- repositorio GitHub privado y Antigravity como entorno principal de desarrollo;
- tratamiento de mensajes editados;
- verificación de integridad de originales;
- reglas de recuperación cuando no existe evidencia suficiente;
- seguridad de webhooks/MCP y restricción de acceso a la base;
- manejo explícito de archivos de Telegram que excedan los límites de la API Bot estándar.

# 1. Propósito

Este documento define los requisitos funcionales, no funcionales, de datos, seguridad, integración y operación que deberá cumplir la V1 de la Secretaria Virtual con IA.

El objetivo del SRS es convertir el PRD aprobado en requisitos:

- numerados;
- verificables;
- trazables;
- implementables;
- testeables.

Antigravity deberá utilizar este documento como fuente de requisitos técnicos junto con `01_PRD.md` y los documentos de arquitectura posteriores.

Cuando exista una contradicción entre una implementación propuesta y un requisito aprobado de este SRS, prevalecerá el requisito hasta que exista una modificación formal del documento.

---

# 2. Principio técnico rector

**Automatizar todo lo posible, pero nunca inventar información cuando una ambigüedad pueda modificar tareas, personas, fechas, horarios, proyectos o memoria histórica.**

El sistema deberá priorizar:

1. exactitud;
2. trazabilidad;
3. conservación del original;
4. idempotencia;
5. seguridad;
6. capacidad de recuperación;
7. experiencia conversacional natural.

---

# 3. Convención de requisitos

Los requisitos utilizarán los siguientes prefijos:

| Prefijo | Área |
|---|---|
| SYS | Sistema general |
| USR | Usuario y perfil |
| ING | Ingesta |
| MEM | Memoria |
| SRC | Fuentes y originales |
| TG | Telegram |
| AUD | Audio |
| TRN | Transcripción |
| VIS | Imágenes, dibujos y diagramas |
| WEB | Páginas web |
| TASK | Tareas |
| PRI | Prioridades |
| DATE | Fechas y horarios |
| ENT | Personas y entidades |
| FACT | Hechos y conocimiento histórico |
| PROJ | Proyectos y relaciones |
| CLR | Clarificaciones |
| REM | Recordatorios |
| DND | Descanso / silencio |
| BRF | Buenos días / cierre diario |
| REP | Reportes |
| PDF | PDF |
| XLS | Excel |
| IA | Inteligencia artificial |
| EMB | Embeddings y búsqueda semántica |
| MCP | MCP / ChatGPT |
| GDR | Google Drive |
| N8N | n8n |
| DB | Supabase / base de datos |
| IDP | Identidad de la secretaria |
| SEC | Seguridad |
| AUDIT | Auditoría |
| DUP | Duplicados / idempotencia |
| REL | Fiabilidad / resiliencia |
| PERF | Rendimiento y costo |
| UX | Experiencia conversacional |
| BCK | Backup y recuperación |
| OPS | Operación y monitoreo |
| DEV | Desarrollo y control de cambios |
| MULTI | Futuro multiusuario |
| TEST | Verificación |
| OOS | Fuera de alcance |

---

# 4. Requisitos generales del sistema

### SYS-001 — Memoria unificada
Toda información incorporada desde Telegram, Google Drive, ChatGPT/MCP u otras fuentes habilitadas deberá terminar relacionada con una única memoria lógica del usuario.

### SYS-002 — Separación de capas
El sistema deberá distinguir entre:

- original;
- interpretación de IA;
- estado/acción derivada.

Estas capas no deberán sobrescribirse entre sí.

### SYS-003 — Procesamiento automático
Las entradas nuevas deberán procesarse automáticamente sin intervención manual, salvo cuando exista ambigüedad, error, falta de información necesaria o una acción que requiera respuesta del usuario.

### SYS-004 — Operación 24/7
Mientras n8n y las integraciones dependientes estén disponibles, el sistema deberá poder procesar entradas y recordatorios de forma continua.

### SYS-005 — Orquestación
n8n deberá actuar como orquestador central de los flujos operativos.

### SYS-006 — Fuente de verdad operativa
Supabase deberá ser la fuente de verdad para la memoria estructurada, tareas, estados, configuraciones, recordatorios, auditoría y relaciones.

### SYS-007 — Almacenamiento de originales
Google Drive deberá funcionar como repositorio principal de originales de V1 cuando exista un archivo persistente que conservar.

### SYS-008 — Multiproveedor de IA
El sistema deberá soportar más de un proveedor/modelo de IA sin requerir rediseñar el núcleo de memoria.

### SYS-009 — No dependencia de comandos rígidos
Las operaciones principales deberán poder ejecutarse mediante lenguaje natural.

### SYS-010 — Trazabilidad
Toda acción relevante deberá poder rastrearse hasta la entrada u origen que la generó.

---

# 5. Usuario y configuración

### USR-001 — Usuario único V1
V1 deberá operar con un único usuario funcional.

### USR-002 — Identificador de usuario
Las tablas y registros pertenecientes al usuario deberán incluir `user_id` o una relación equivalente preparada para aislamiento futuro.

### USR-003 — Zona horaria
El usuario deberá tener una zona horaria configurable.

### USR-004 — Zona horaria inicial
La zona horaria deberá utilizarse para resolver fechas relativas, programar recordatorios, saludos y resúmenes.

### USR-005 — Configuración conversacional
El usuario deberá poder cambiar preferencias operativas mediante lenguaje natural.

### USR-006 — Configuración persistente
Las preferencias deberán persistirse en Supabase y no depender exclusivamente del estado de un workflow de n8n.

### USR-007 — Idioma
El sistema deberá tener un idioma principal configurable. V1 deberá funcionar correctamente en español y conservar la posibilidad de incorporar otros idiomas posteriormente.

### USR-008 — Locale
La interpretación de fechas, horas, números y respuestas deberá respetar el locale configurado del usuario cuando sea relevante.

---

# 6. Ingesta

### ING-001 — Registro previo
Toda entrada deberá registrarse antes de comenzar el procesamiento costoso o irreversible.

### ING-002 — Estado de procesamiento
Cada ingesta deberá tener un estado identificable, como mínimo:

- recibida;
- procesando;
- esperando aclaración;
- completada;
- error;
- descartada por duplicado.

### ING-003 — Reintentos
Una ingesta fallida deberá poder reintentarse sin generar registros duplicados.

### ING-004 — Identificador de origen
Toda ingesta deberá conservar identificadores externos disponibles, como `message_id`, `file_id`, `drive_file_id`, URL u otros.

### ING-005 — Tipo de entrada
El sistema deberá identificar el tipo de entrada antes de seleccionar el flujo de procesamiento.

### ING-006 — Origen
Toda ingesta deberá registrar un origen normalizado, por ejemplo:

- `telegram_text`;
- `telegram_audio`;
- `telegram_file`;
- `google_drive`;
- `chatgpt_mcp`;
- `web`;
- `external_app`.

### ING-007 — Fecha de captura
Toda ingesta deberá conservar la fecha/hora real en que fue recibida o registrada.

### ING-008 — Fallo parcial
Si una etapa falla, el sistema deberá conservar suficiente estado para continuar o reintentar sin perder el original.

---

# 7. Memoria

### MEM-001 — Memoria permanente
La memoria histórica no deberá eliminarse mediante operaciones normales desde Telegram o MCP.

### MEM-002 — Correcciones no destructivas
Una corrección deberá crear una nueva versión, estado o registro relacionado en lugar de destruir la información previa.

### MEM-003 — Estado vigente
Cuando existan varias versiones de un mismo dato, el sistema deberá poder distinguir cuál es la versión vigente.

### MEM-004 — Estado histórico
Las versiones anteriores deberán permanecer disponibles para consultas históricas y auditoría.

### MEM-005 — Memoria semántica
El sistema deberá permitir recuperar información por significado, además de palabras exactas.

### MEM-006 — Memoria estructurada
Los datos operativamente relevantes deberán almacenarse en estructura relacional y no exclusivamente en texto libre o JSON.

### MEM-007 — Fuente asociada
Todo recuerdo derivado deberá poder relacionarse con una o más fuentes originales.

### MEM-008 — Relaciones entre memorias
El sistema deberá poder relacionar memorias entre sí, por ejemplo:

- continuación;
- complemento;
- contradicción;
- reemplazo;
- basada en;
- relacionada con.

### MEM-009 — Consulta histórica
El usuario deberá poder consultar información por fecha, rango temporal, persona, proyecto, tema o significado.

### MEM-010 — Evidencia
Cuando el usuario solicite evidencia, el sistema deberá diferenciar claramente:

- texto original;
- interpretación;
- inferencia;
- acción derivada.

### MEM-011 — Ausencia de evidencia
Si la recuperación no encuentra evidencia suficiente para responder una consulta histórica, el sistema deberá indicarlo claramente en lugar de completar la respuesta con información inventada.

### MEM-012 — Sin expiración automática
La memoria histórica del usuario no deberá eliminarse por TTL, caducidad automática o políticas de limpieza de logs.

La limpieza de datos técnicos temporales de n8n podrá realizarse siempre que no elimine la memoria, originales, trazabilidad o auditoría del producto.

---

# 8. Fuentes y archivos originales

### SRC-001 — Conservación del original
Los archivos originales deberán preservarse cuando exista un archivo persistente.

### SRC-002 — SHA-256
Todo archivo original deberá recibir una huella SHA-256 cuando sea técnicamente posible.

### SRC-003 — Metadatos
Los archivos deberán conservar, cuando estén disponibles:

- nombre;
- MIME type;
- tamaño;
- duración;
- fecha;
- origen;
- identificadores externos;
- hash.

### SRC-004 — Ubicaciones múltiples
Un mismo archivo podrá tener múltiples ubicaciones/orígenes sin duplicarse como archivo lógico.

### SRC-005 — Relación con memoria
Cada archivo deberá poder relacionarse con una o más memorias.

### SRC-006 — Recuperación
El sistema deberá poder recuperar la referencia o archivo original desde la memoria asociada.

### SRC-007 — Drive como archivo maestro V1
Cuando un original deba conservarse, la arquitectura deberá permitir archivarlo en Google Drive y registrar su ubicación.

### SRC-008 — Verificación de integridad
Después de archivar un original, el sistema deberá conservar información suficiente para verificar posteriormente su integridad mediante SHA-256 u otro mecanismo equivalente aprobado.

### SRC-009 — Original inmutable
Los procesos de interpretación, transcripción, conversión o generación de previews no deberán modificar silenciosamente el archivo original archivado.

---

# 9. Telegram

### TG-001 — Interfaz principal
Telegram deberá ser la interfaz conversacional principal de V1.

### TG-002 — Texto
El bot deberá aceptar mensajes de texto.

### TG-003 — Voz
El bot deberá aceptar mensajes de voz y audios.

### TG-004 — Archivos
El bot deberá aceptar archivos compatibles.

### TG-005 — Conversación natural
El usuario no deberá necesitar comandos para crear, completar, consultar o modificar tareas en los casos habituales.

### TG-006 — Comandos opcionales
Podrán existir comandos como accesos rápidos y configuración.

### TG-007 — Mensaje original
Cada mensaje relevante de Telegram deberá conservar:

- contenido original;
- `message_id`;
- `chat_id`;
- fecha/hora;
- tipo;
- `file_id` cuando exista.

### TG-008 — Contexto de conversación
Las respuestas breves del usuario a preguntas de aclaración deberán poder vincularse con la aclaración pendiente correcta.

### TG-009 — Recuperación de audio en Telegram
Cuando el tamaño y formato estén soportados por Telegram, el sistema deberá poder enviar nuevamente el audio original al chat para reproducirlo directamente.

Si Telegram no permite reenviarlo por tamaño o formato, el bot deberá proporcionar un fallback claro, como el enlace/referencia segura al original de Google Drive.

### TG-010 — Configuración
Deberá existir una entrada de Configuración accesible desde la zona inferior del chat mediante el menú de comandos de Telegram en V1.

### TG-011 — Confirmaciones
Después de una modificación relevante, el bot deberá confirmar de forma clara qué cambió.

### TG-012 — Reportes en texto
Los reportes deberán entregarse primero en texto salvo petición explícita de archivo.

### TG-013 — Límite de descarga
Antes de depender de la descarga de un archivo mediante la Bot API estándar, el sistema deberá considerar el límite vigente de descarga de Telegram y validar el tamaño cuando esté disponible.

### TG-014 — Archivo superior al límite
Si un archivo no puede descargarse mediante la Bot API estándar por su tamaño, el sistema no deberá perder la entrada ni fallar silenciosamente.

V1 deberá proporcionar al menos una alternativa soportada, como solicitar que el archivo se incorpore mediante Google Drive. La arquitectura podrá habilitar posteriormente un Local Bot API Server para eliminar el límite estándar de descarga.

### TG-015 — Mensajes editados
Cuando Telegram entregue un evento de mensaje editado, el sistema deberá registrar la nueva versión sin destruir la versión original previamente almacenada.

### TG-016 — Identidad autorizada
Las operaciones de V1 deberán aceptar comandos y modificaciones solo desde el usuario/chat de Telegram autorizado.

### TG-017 — Seguridad de webhook
Si se utiliza webhook, el endpoint deberá validar el origen mediante el mecanismo de secreto soportado por Telegram y operar sobre HTTPS.

---

# 10. Audio

### AUD-001 — Descarga
n8n deberá poder descargar el archivo de audio recibido por Telegram o una fuente externa.

### AUD-002 — Preservación
El audio original deberá conservarse sin alteración.

### AUD-003 — Duración
Cuando sea posible, deberá registrarse la duración.

### AUD-004 — Transcripción automática
Todo audio marcado para procesamiento deberá enviarse automáticamente al motor de transcripción seleccionado.

### AUD-005 — Evidencia temporal
Cuando el motor proporcione timestamps, deberán conservarse.

### AUD-006 — Reproducción posterior
El usuario deberá poder recuperar y escuchar el audio original desde Telegram cuando el tamaño y formato lo permitan. En caso contrario deberá recibir una vía segura para acceder al original archivado.

### AUD-007 — Múltiples motores
La arquitectura deberá permitir procesar un mismo audio con más de un motor para evaluación A/B.

### AUD-008 — Audio grande
El flujo de audio deberá detectar cuando un archivo supera el límite de descarga de la Bot API estándar y activar el mecanismo de fallback definido en TG-014.

---

# 11. Transcripción

### TRN-001 — Versionado
Cada ejecución de transcripción deberá almacenarse como una versión identificable.

### TRN-002 — Proveedor y modelo
Cada transcripción deberá registrar proveedor y modelo utilizado.

### TRN-003 — Texto literal
La salida literal del motor deberá preservarse.

### TRN-004 — Preferida
El sistema deberá poder marcar una versión de transcripción como preferida sin eliminar las demás.

### TRN-005 — No sobrescritura
Una versión corregida, resumida o interpretada por IA no deberá sobrescribir el texto literal almacenado.

### TRN-006 — Timestamps
Cuando existan, los timestamps deberán relacionarse con fragmentos del texto.

### TRN-007 — A/B
Deberá existir un procedimiento de prueba A/B con audios reales antes de fijar definitivamente el motor principal.

---

# 12. Imágenes, dibujos y diagramas

### VIS-001 — Procesamiento multimodal
El sistema deberá poder enviar imágenes y diagramas a un modelo multimodal.

### VIS-002 — OCR
El sistema deberá intentar extraer texto impreso o manuscrito cuando sea relevante.

### VIS-003 — Estructura
En diagramas deberá intentar identificar:

- bloques;
- flechas;
- relaciones;
- secuencias.

### VIS-004 — Interpretación
La IA deberá generar una interpretación estructurada del diagrama cuando sea posible.

### VIS-005 — Detección de tareas
El análisis visual podrá generar tareas, ideas, decisiones o relaciones si están suficientemente respaldadas por el contenido.

### VIS-006 — Original preservado
La imagen original nunca deberá sustituirse por la interpretación.

### VIS-007 — Ambigüedad
Si un diagrama no puede interpretarse con suficiente confianza, el sistema deberá conservarlo y marcar la interpretación como incierta en lugar de inventarla.

---

# 13. Páginas web

### WEB-001 — URL
Toda página guardada deberá conservar la URL original.

### WEB-002 — Fecha de captura
Deberá conservarse la fecha/hora en que fue incorporada.

### WEB-003 — Contenido
Deberá extraerse y almacenarse contenido textual relevante cuando sea técnicamente posible.

### WEB-004 — Título
Deberá conservarse el título cuando esté disponible.

### WEB-005 — Snapshot
Cuando sea técnicamente razonable, deberá conservarse una representación histórica del contenido visto.

### WEB-006 — Cambio futuro
La consulta posterior no deberá asumir que el contenido actual de la URL es idéntico al que se almacenó originalmente.

### WEB-007 — Contenido no confiable
El texto o instrucciones encontradas dentro de una página web deberán tratarse como contenido a analizar y no como instrucciones de control para el agente o las herramientas del sistema.

---

# 14. Tareas

### TASK-001 — Detección automática
La IA deberá detectar tareas suficientemente claras en las entradas.

### TASK-002 — Creación automática
Una tarea clara deberá poder crearse automáticamente sin confirmación adicional.

### TASK-003 — Estados
Una tarea deberá soportar como mínimo:

- pendiente;
- en progreso;
- completada;
- pospuesta;
- cancelada.

### TASK-004 — Tarea retrospectiva
El sistema deberá permitir crear directamente una tarea/actividad con estado completado cuando el usuario informe algo ya realizado.

### TASK-005 — Fuente
Cada tarea deberá conservar relación con la memoria u origen que la creó.

### TASK-006 — Creación manual natural
El usuario deberá poder crear una tarea escribiendo o hablando naturalmente.

### TASK-007 — Modificación
El usuario deberá poder modificar una tarea mediante lenguaje natural.

### TASK-008 — Completar
El usuario deberá poder marcar una tarea como completada mediante lenguaje natural.

### TASK-009 — Posponer
El usuario deberá poder posponer una tarea mediante lenguaje natural.

### TASK-010 — Cancelar
El usuario deberá poder cancelar una tarea sin borrarla del historial.

### TASK-011 — Fecha de creación
Toda tarea deberá registrar cuándo fue creada.

### TASK-012 — Fecha objetivo
La tarea podrá tener fecha objetivo con o sin hora.

### TASK-013 — Fecha completada
Una tarea completada deberá registrar cuándo se completó.

### TASK-014 — Expresión temporal original
Si la fecha provino de lenguaje natural, deberá conservarse la expresión original.

### TASK-015 — Proyecto/personas
La tarea podrá relacionarse con proyectos y personas.

### TASK-016 — Origen
La tarea deberá indicar si provino de Telegram, Drive, ChatGPT/MCP, detección automática u otra fuente.

### TASK-017 — Confirmación de finalización
Al completar una tarea mediante conversación, la respuesta deberá identificar de forma suficiente la tarea completada y, cuando sea útil, su fecha objetivo/persona relacionada para evitar confusión.

### TASK-018 — Estado desconocido
El sistema deberá distinguir entre una tarea pendiente, una tarea completada y una tarea cuyo estado aún no fue confirmado; la ausencia de confirmación no deberá interpretarse como finalización.

---

# 15. Prioridad

### PRI-001 — Valores
Las prioridades explícitas serán como mínimo:

- urgente;
- alta;
- normal;
- baja.

### PRI-002 — Manual
El usuario podrá establecer la prioridad.

### PRI-003 — Automática
La IA podrá inferir una prioridad cuando el usuario no la indique.

### PRI-004 — Precedencia
Una prioridad expresamente indicada por el usuario deberá prevalecer sobre la inferencia automática.

### PRI-005 — Influencia
La prioridad podrá influir en:

- orden de resúmenes;
- frecuencia de seguimiento;
- anticipación de avisos;
- excepción al modo silencio si se cumplen criterios críticos.

---

# 16. Fechas y horarios

### DATE-001 — Fecha actual real
Para interpretar expresiones relativas, el sistema deberá usar una fecha/hora de referencia real, no una fecha inventada por el modelo.

### DATE-002 — Zona horaria
Toda resolución deberá utilizar la zona horaria configurada del usuario.

### DATE-003 — Expresión original
Se deberá conservar la expresión temporal original.

### DATE-004 — Fecha resuelta
Se deberá almacenar la fecha absoluta resultante.

### DATE-005 — Sin hora
Si el usuario da una fecha sin hora, el sistema no deberá inventar una hora.

### DATE-006 — Hora pendiente
Una tarea podrá existir con fecha conocida y hora desconocida.

### DATE-007 — Pregunta posterior
La secretaria podrá preguntar por una hora faltante cuando sea útil.

### DATE-008 — “Hoy”
La expresión “hoy” deberá resolverse usando la fecha de captura.

### DATE-009 — “Mañana”
La expresión “mañana” deberá resolverse usando la fecha de captura.

### DATE-010 — Día de semana
Expresiones como “el miércoles” deberán resolverse de acuerdo con el contexto temporal real.

### DATE-011 — Semana próxima
Expresiones como “el miércoles de la semana que viene” deberán resolverse distinguiéndolas del miércoles inmediato cuando corresponda.

### DATE-012 — Auditoría temporal
Deberá ser posible explicar posteriormente qué expresión originó una fecha resuelta.

### DATE-013 — Fuente de tiempo
Los workflows no deberán pedir al modelo que adivine la fecha/hora actual. n8n deberá proporcionar al proceso la fecha/hora del sistema y la zona horaria configurada.

### DATE-014 — Separar captura, vencimiento y realización
Cuando corresponda, el sistema deberá distinguir entre:

- cuándo se registró la información;
- cuándo debía ocurrir;
- cuándo ocurrió realmente.

---

# 17. Personas y entidades

### ENT-001 — Entidades
El sistema deberá representar personas, organizaciones, lugares, proyectos, temas y otras entidades relevantes.

### ENT-002 — Alias
Las entidades podrán tener alias.

### ENT-003 — Personas repetidas
Si existen varias personas plausibles con el mismo nombre, el sistema deberá pedir aclaración.

### ENT-004 — No inferencia destructiva
El sistema no deberá modificar una tarea o hecho basándose únicamente en una coincidencia ambigua de nombre.

### ENT-005 — Relaciones
Las personas podrán relacionarse con tareas, memorias, proyectos, hechos y organizaciones.

### ENT-006 — Corrección
El usuario podrá corregir información sobre una entidad y la versión anterior deberá permanecer histórica.

---

# 18. Hechos y conocimiento histórico

### FACT-001 — Hechos estructurados
Los datos factuales relevantes deberán poder representarse como conocimiento estructurado relacionado con entidades y fuentes.

### FACT-002 — Fuente del hecho
Todo hecho derivado deberá poder relacionarse con la memoria/fuente de la cual fue extraído.

### FACT-003 — Fecha de registro
El sistema deberá distinguir cuándo se registró o aprendió un hecho.

### FACT-004 — Validez temporal
Cuando el hecho tenga naturaleza temporal, deberá poder registrar desde cuándo y hasta cuándo fue válido.

Ejemplo: una persona puede haber trabajado en una organización anteriormente y en otra actualmente.

### FACT-005 — Corrección histórica
Una corrección factual deberá poder marcar el dato previo como histórico, reemplazado o inválido sin borrarlo.

### FACT-006 — Desconocido no es falso
La ausencia de un valor no deberá interpretarse automáticamente como una negación o hecho falso.

---

# 19. Proyectos y relaciones

### PROJ-001 — Detección automática
La IA podrá detectar que varias entradas pertenecen al mismo proyecto.

### PROJ-002 — Asociación automática segura
La asociación podrá realizarse automáticamente si existe evidencia suficiente.

### PROJ-003 — Aclaración
Si la asociación tiene impacto operativo y es ambigua, el sistema deberá preguntar.

### PROJ-004 — Sin jerarquía obligatoria
El usuario no deberá crear manualmente áreas o estructuras rígidas para que el sistema funcione.

### PROJ-005 — Etiquetas generales
Conceptos como trabajo, personal, fotografía o desarrollo podrán funcionar como etiquetas/temas internos.

---

# 20. Clarificaciones

### CLR-001 — Registro
Toda pregunta de aclaración que requiera respuesta posterior deberá registrarse como pendiente.

### CLR-002 — Contexto
La aclaración deberá conservar el objeto que espera completar o modificar.

### CLR-003 — Respuesta breve
Una respuesta como “Juan Pérez” o “a las 16” deberá poder resolver la aclaración activa correspondiente.

### CLR-004 — No acción previa
Si la aclaración es necesaria para una modificación relevante, esa modificación no deberá ejecutarse hasta recibir una respuesta válida.

### CLR-005 — Expiración
Las aclaraciones podrán tener un estado de expiración o abandono para evitar que una respuesta tardía se aplique al contexto incorrecto.

### CLR-006 — Múltiples pendientes
Si existieran varias aclaraciones activas incompatibles, el sistema deberá evitar asociar arbitrariamente una respuesta.

---

# 21. Recordatorios

### REM-001 — Persistencia
Los recordatorios deberán almacenarse en Supabase y no existir únicamente como temporizadores internos de n8n.

### REM-002 — Regla base
La configuración inicial deberá permitir un aviso estándar aproximadamente 3 horas antes cuando corresponda.

### REM-003 — Avisos adicionales de IA
La IA podrá agregar recordatorios adicionales según tipo y esfuerzo de tarea.

### REM-004 — Llamada
Una llamada podrá recibir un recordatorio cercano, por ejemplo 10 minutos antes, si la IA lo considera útil.

### REM-005 — Trabajo previo
Una entrega que requiere preparación podrá recibir un recordatorio el día anterior o con anticipación equivalente.

### REM-006 — Seguimiento
Las tareas no confirmadas deberán poder generar seguimientos posteriores.

### REM-007 — No molestar
Los recordatorios normales deberán respetar horario de silencio y modo descanso.

### REM-008 — Críticos
Solo recordatorios que cumplan criterios definidos de criticidad podrán atravesar el silencio.

### REM-009 — Registro de entrega
Cada intento de notificación deberá poder registrarse.

### REM-010 — Estado
Un recordatorio deberá distinguir como mínimo:

- pendiente;
- enviado;
- fallido;
- reintentando;
- cancelado.

### REM-011 — No duplicar
Un reintento no deberá producir mensajes duplicados si ya existe una entrega exitosa.

### REM-012 — Watchdog
Deberá existir un proceso periódico que detecte recordatorios vencidos sin entrega exitosa.

---

# 22. Silencio y descanso

### DND-001 — Horario recurrente
El usuario podrá definir un horario diario de silencio.

### DND-002 — Persistencia
El horario recurrente deberá persistir en configuración.

### DND-003 — Modo temporal
El usuario podrá activar un modo descanso temporal mediante lenguaje natural.

### DND-004 — Sin frase obligatoria
No deberá exigirse una frase exacta.

### DND-005 — Pregunta
Si el usuario dice “no me molestes” sin indicar duración, la secretaria deberá preguntar hasta cuándo.

### DND-006 — Procesamiento continuo
Durante silencio o descanso, el procesamiento interno deberá continuar.

### DND-007 — Reanudación automática
Al finalizar el descanso temporal, deberá restaurarse automáticamente el comportamiento habitual.

### DND-008 — Críticos
Las excepciones críticas deberán definirse explícitamente y no basarse solo en una respuesta libre del modelo.

### DND-009 — “Hasta mañana”
Si el usuario activa descanso “hasta mañana” sin otra hora y existe un horario habitual de inicio configurado, el sistema deberá poder proponer o utilizar ese próximo horario de inicio de acuerdo con la conversación.

### DND-010 — Acumulación de avisos
Al salir del modo descanso, el sistema deberá evitar enviar una ráfaga innecesaria de notificaciones retenidas y deberá resumirlas de forma razonable cuando sea posible.

---

# 23. Buenos días y cierre diario

### BRF-001 — Buenos días configurable
El usuario podrá configurar la hora del mensaje de buenos días.

### BRF-002 — Contenido
El mensaje podrá incluir:

- pendientes;
- vencidas;
- compromisos;
- próximos eventos;
- tareas posiblemente olvidadas;
- novedades del período de descanso.

### BRF-003 — Trato
El saludo deberá ser cordial y natural.

### BRF-004 — Cierre configurable
El usuario podrá configurar la hora del resumen nocturno.

### BRF-005 — Cierre opcional
El resumen nocturno podrá habilitarse o deshabilitarse.

### BRF-006 — Contenido cierre
Podrá incluir:

- tareas realizadas;
- pendientes;
- pospuestas;
- compromisos del día siguiente;
- actividades del día.

### BRF-007 — Reanudación
Cuando el período de descanso finalice al comienzo del día, el mensaje de buenos días podrá actuar como reanudación del modo normal y resumir lo importante ocurrido durante el silencio.

---

# 24. Reportes

### REP-001 — Texto primero
Todo reporte deberá mostrarse primero como texto en Telegram.

### REP-002 — Período diario
El usuario podrá pedir reportes del día.

### REP-003 — Período semanal
El usuario podrá pedir reportes de semana.

### REP-004 — Período mensual
El usuario podrá pedir reportes de mes.

### REP-005 — Rango personalizado
El usuario podrá indicar un rango arbitrario de fechas.

### REP-006 — No solo tareas
Los reportes podrán incluir cualquier información recuperable de la memoria, no solo tareas.

### REP-007 — Consulta original
El reporte deberá conservar la consulta que lo originó.

### REP-008 — Fuentes
Cuando corresponda, deberá conservar relación con las memorias o fuentes usadas.

### REP-009 — Reutilización
El usuario deberá poder referirse posteriormente a “ese reporte” dentro de un contexto conversacional razonable.

### REP-010 — Integridad del reporte
Si existen huecos de información, errores de procesamiento conocidos o fuentes no disponibles que puedan afectar un reporte, el sistema deberá indicarlo en vez de presentar el resultado como completo con certeza.

---

# 25. PDF

### PDF-001 — Solo bajo pedido
No se deberá generar PDF automáticamente.

### PDF-002 — Pedido explícito
El usuario deberá pedir explícitamente un PDF.

### PDF-003 — Basado en reporte
Un PDF podrá generarse a partir de un reporte previamente mostrado.

### PDF-004 — Trazabilidad
El PDF deberá quedar relacionado con el reporte y sus fuentes.

### PDF-005 — Entrega
El PDF deberá poder enviarse por Telegram.

---

# 26. Excel

### XLS-001 — Solo bajo pedido
No se deberá generar Excel automáticamente.

### XLS-002 — Pedido explícito
El usuario deberá pedir explícitamente una tabla o archivo Excel.

### XLS-003 — Estructura
Los datos deberán organizarse en filas/columnas adecuadas al pedido.

### XLS-004 — Trazabilidad
El Excel deberá relacionarse con la consulta y datos de origen.

### XLS-005 — Entrega
El archivo Excel deberá poder enviarse por Telegram.

---

# 27. Identidad de la secretaria

### IDP-001 — Nombre
La secretaria deberá tener un nombre configurable.

### IDP-002 — Onboarding
En el primer inicio, si no existe nombre, el bot deberá preguntar cómo quiere llamarla el usuario.

### IDP-003 — Persistencia
El nombre deberá almacenarse en Supabase.

### IDP-004 — Cambio por lenguaje natural
El usuario deberá poder cambiar el nombre mediante conversación.

### IDP-005 — Cambio desde configuración
El usuario deberá poder iniciar el cambio desde Configuración.

### IDP-006 — Sincronización Telegram
En V1 personal, el sistema deberá intentar sincronizar el nombre configurado con el nombre público del bot mediante la API oficial de Telegram.

### IDP-007 — Username separado
El cambio de nombre no deberá modificar automáticamente el `@username`.

### IDP-008 — Historial
Los nombres anteriores deberán conservarse históricamente.

### IDP-009 — Nombre vigente
El sistema deberá poder identificar qué nombre está vigente.

### IDP-010 — Auditoría
Cada cambio de nombre deberá registrar fecha y origen.

### IDP-011 — Multiusuario futuro
Si un bot compartido se usa en una versión futura, el nombre interno de cada secretaria podrá ser por usuario, pero el encabezado público del bot compartido no podrá variar por conversación.

---

# 28. Experiencia conversacional

### UX-001 — Lenguaje natural
Las respuestas deberán ser comprensibles sin conocimientos técnicos.

### UX-002 — Trato cordial
La secretaria deberá mantener un trato cordial y natural.

### UX-003 — No insistencia molesta
La proactividad y las preguntas de seguimiento deberán evitar repeticiones innecesarias.

### UX-004 — Claridad antes de acción
Cuando una acción quede bloqueada por ambigüedad, la secretaria deberá explicar brevemente qué necesita aclarar.

### UX-005 — Confirmaciones útiles
Las confirmaciones deberán indicar qué ocurrió, evitando respuestas vacías como “listo” cuando haya riesgo de confusión.

### UX-006 — Identidad no repetitiva
El nombre de la secretaria podrá utilizarse para dar identidad, pero no deberá repetirse artificialmente en cada respuesta.

---

# 29. Inteligencia artificial

### IA-001 — Modelos por función
La arquitectura deberá permitir utilizar modelos diferentes para distintas funciones.

### IA-002 — Transcripción
Podrá existir un modelo especializado de transcripción.

### IA-003 — Texto
Podrá existir un modelo para interpretación textual y extracción estructurada.

### IA-004 — Visión
Podrá existir un modelo multimodal para imágenes y diagramas.

### IA-005 — Razonamiento complejo
Podrá reservarse un modelo de mayor capacidad para consultas complejas.

### IA-006 — Modelo económico
Las operaciones rutinarias podrán usar modelos más económicos.

### IA-007 — Salida estructurada
Las operaciones que creen o modifiquen estado deberán producir salidas estructuradas validables.

### IA-008 — Validación
n8n o Supabase deberán validar datos relevantes antes de aplicar cambios.

### IA-009 — No autoridad absoluta
La IA no deberá tener autoridad directa e irrestricta para modificar el estado real de la base.

### IA-010 — Registro de modelo
Las interpretaciones deberán registrar proveedor, modelo y versión de prompt cuando corresponda.

### IA-011 — Confianza
Cuando sea útil, la interpretación podrá registrar un nivel de confianza o indicadores equivalentes.

### IA-012 — Ambigüedad
Una salida de baja confianza no deberá transformarse silenciosamente en un dato factual definitivo.

### IA-013 — Contenido como datos
Texto proveniente de audios, documentos, páginas web, PDFs, imágenes o diagramas deberá tratarse como datos no confiables. Instrucciones encontradas dentro de esos contenidos no deberán cambiar las reglas del sistema ni habilitar herramientas.

### IA-014 — Herramientas controladas
La IA solo podrá solicitar las herramientas explícitamente habilitadas por el sistema y sus argumentos deberán validarse antes de ejecutar efectos persistentes.

### IA-015 — Minimización de contexto
n8n deberá enviar a cada proveedor de IA solo el contenido razonablemente necesario para la tarea, evitando enviar toda la memoria cuando no sea necesario.

### IA-016 — Reprocesamiento
Un recuerdo podrá reinterpretarse con un modelo/prompt nuevo sin eliminar la interpretación anterior.

---

# 30. Embeddings y búsqueda

### EMB-001 — Fragmentación
Los textos extensos deberán dividirse en fragmentos recuperables.

### EMB-002 — Referencia
Cada fragmento deberá conservar referencia a su texto/original.

### EMB-003 — Timestamps
En audio, los fragmentos deberán conservar timestamps cuando estén disponibles.

### EMB-004 — Embeddings desacoplados
Los embeddings deberán almacenarse separados del texto lógico para permitir cambios de modelo.

### EMB-005 — Modelo
Cada embedding deberá registrar el modelo utilizado.

### EMB-006 — No mezclar espacios incompatibles
No deberán compararse como equivalentes embeddings producidos por modelos incompatibles.

### EMB-007 — Búsqueda semántica
El sistema deberá soportar búsqueda semántica.

### EMB-008 — Búsqueda textual
El sistema deberá soportar búsqueda textual/exacta.

### EMB-009 — Búsqueda híbrida
El sistema deberá poder combinar búsqueda semántica, textual, filtros y relaciones estructuradas.

### EMB-010 — Reindexación
Los embeddings deberán poder regenerarse sin perder la memoria original.

---

# 31. MCP / ChatGPT

### MCP-001 — Servidor de herramientas
n8n deberá poder exponer herramientas MCP seleccionadas.

### MCP-002 — Buscar memoria
ChatGPT deberá poder solicitar búsquedas de memoria mediante MCP.

### MCP-003 — Consultar tareas
ChatGPT deberá poder consultar tareas.

### MCP-004 — Crear tarea
ChatGPT deberá poder crear una tarea en la misma base utilizada por Telegram.

### MCP-005 — Completar tarea
ChatGPT deberá poder completar una tarea, aplicando las mismas reglas de ambigüedad.

### MCP-006 — Modificar tarea
ChatGPT deberá poder modificar tareas con permisos controlados.

### MCP-007 — Guardar nota
ChatGPT deberá poder incorporar una nota a la memoria.

### MCP-008 — Corregir memoria
ChatGPT deberá poder registrar correcciones sin borrar el histórico.

### MCP-009 — Enviar Telegram
ChatGPT podrá solicitar mediante MCP que n8n envíe un mensaje por Telegram.

### MCP-010 — Sin delete histórico
No deberá existir una herramienta MCP general para eliminar memoria histórica.

### MCP-011 — Permisos mínimos
Las herramientas deberán tener permisos específicos y limitados.

### MCP-012 — Auditoría
Las acciones iniciadas desde ChatGPT/MCP deberán registrar ese origen.

### MCP-013 — Autenticación
El endpoint MCP deberá requerir autenticación fuerte y transporte cifrado.

### MCP-014 — Mismas reglas de negocio
Las acciones originadas desde MCP deberán cumplir las mismas reglas de validación, ambigüedad, no borrado y auditoría que las acciones originadas desde Telegram.

### MCP-015 — Sin SQL arbitrario
El MCP de producción no deberá exponer una herramienta genérica de SQL arbitrario o acceso irrestricto a Supabase.

### MCP-016 — Separación API/MCP
El procesamiento automático de nuevas entradas deberá poder funcionar mediante APIs aun cuando ChatGPT/MCP no esté conectado. MCP será una interfaz adicional de consulta y acción, no el motor necesario para las automatizaciones 24/7.

---

# 32. Google Drive

### GDR-001 — Entrada
n8n deberá poder detectar nuevos archivos en la ubicación configurada de Drive.

### GDR-002 — Originales
Drive deberá almacenar los originales persistentes de V1.

### GDR-003 — Referencia
Supabase deberá conservar la referencia necesaria para recuperar cada original.

### GDR-004 — Clasificación automática
No deberá ser obligatorio separar manualmente cada tipo de archivo en carpetas distintas.

### GDR-005 — Procesamiento por tipo
n8n deberá enrutar cada archivo al procesador adecuado según tipo.

### GDR-006 — Duplicado
Un archivo que ya exista por otro origen no deberá reprocesarse innecesariamente.

### GDR-007 — Carpeta raíz
La carpeta raíz utilizada por la secretaria en Google Drive deberá ser configurable.

### GDR-008 — Metadatos de Drive
Cuando estén disponibles, deberán conservarse el nombre, ID, ubicación y metadatos necesarios para reconstruir el origen del archivo.

### GDR-009 — Archivo modificado
Si un archivo existente cambia de contenido y por lo tanto cambia su huella, el sistema deberá tratarlo como una nueva versión/contenido y conservar la trazabilidad con respecto a la versión previa cuando pueda determinarse.

---

# 33. n8n

### N8N-001 — Orquestador
n8n será el componente encargado de coordinar los flujos.

### N8N-002 — Credenciales
Las credenciales deberán almacenarse mediante mecanismos seguros de n8n o variables de entorno.

### N8N-003 — Drive
n8n deberá conectarse a Google Drive.

### N8N-004 — Telegram
n8n deberá conectarse al bot de Telegram.

### N8N-005 — Supabase
n8n deberá consultar y modificar Supabase mediante interfaces controladas.

### N8N-006 — IA
n8n deberá poder invocar OpenAI, Gemini u otros proveedores configurados.

### N8N-007 — MCP
n8n deberá poder actuar como capa de herramientas MCP cuando se habilite esa integración.

### N8N-008 — Reintentos
Los workflows deberán diseñarse para reintentos seguros.

### N8N-009 — Logging
Los workflows críticos deberán producir logs o estados que permitan diagnosticar errores.

### N8N-010 — Modularidad
Los flujos deberán dividirse por responsabilidades y no concentrar toda la lógica en un único workflow gigante.

### N8N-011 — Exportación/versionado
Los workflows deberán poder exportarse y versionarse en el repositorio del proyecto.

### N8N-012 — Despliegue V1
El objetivo de despliegue de V1 será n8n self-hosted en el NAS del usuario, preferentemente mediante una instalación reproducible/contenedorizada compatible con el hardware disponible.

### N8N-013 — IA fuera del NAS
V1 no deberá requerir ejecutar modelos LLM, visión o transcripción pesados en el NAS. El procesamiento de IA se realizará mediante APIs externas configuradas.

### N8N-014 — Binarios temporales
n8n no será el archivo permanente de audios/documentos. Los binarios deberán archivarse en el repositorio persistente y los datos temporales de ejecución podrán limpiarse según una política segura.

### N8N-015 — Acceso externo seguro
Si Telegram, MCP u otros servicios requieren alcanzar n8n desde Internet, el endpoint deberá exponerse mediante HTTPS y una arquitectura de red segura que no publique innecesariamente servicios internos del NAS.

### N8N-016 — Seguridad de instancia
La instalación self-hosted deberá contemplar actualizaciones, autenticación del panel, cifrado de credenciales y revisiones periódicas de seguridad de n8n.

---

# 34. Supabase / base de datos

### DB-001 — PostgreSQL
Supabase/PostgreSQL será la base principal.

### DB-002 — Esquema versionado
Los cambios estructurales deberán implementarse mediante migraciones versionadas.

### DB-003 — UUID
Las entidades principales deberán utilizar identificadores robustos, preferentemente UUID.

### DB-004 — user_id
Las tablas de datos del usuario deberán estar preparadas para aislamiento por `user_id`.

### DB-005 — RLS
Las tablas expuestas deberán usar RLS cuando corresponda.

### DB-006 — Datos estructurados
Fechas, estados, IDs, prioridades y relaciones deberán utilizar columnas y relaciones apropiadas.

### DB-007 — JSONB limitado
JSONB podrá utilizarse para metadatos variables, pero no deberá sustituir indiscriminadamente el modelo relacional.

### DB-008 — Auditoría
Las modificaciones relevantes deberán poder registrarse en `audit_log`.

### DB-009 — Sin borrado desde interfaces normales
Las operaciones normales de Telegram/MCP no deberán ejecutar `DELETE` físico sobre memoria histórica.

### DB-010 — Integridad referencial
Las relaciones críticas deberán protegerse mediante foreign keys o mecanismos equivalentes.

### DB-011 — Índices
Los índices deberán definirse según patrones de consulta y no agregarse indiscriminadamente.

---

# 35. Modelo lógico de datos obligatorio

La implementación posterior de `04_DATABASE_SCHEMA.md` deberá contemplar como mínimo las siguientes entidades lógicas aprobadas:

1. `profiles`
2. `user_settings`
3. `ingestions`
4. `memory_items`
5. `memory_relations`
6. `assets`
7. `asset_locations`
8. `memory_asset_links`
9. `source_texts`
10. `memory_chunks`
11. `embeddings`
12. `interpretations`
13. `entities`
14. `entity_aliases`
15. `memory_entity_links`
16. `facts`
17. `tasks`
18. `reminders`
19. `notification_deliveries`
20. `pending_clarifications`
21. `reports`
22. `audit_log`

### DB-012 — Extensiones futuras
Podrán agregarse tablas auxiliares si son justificadas por integridad, rendimiento, seguridad o mantenibilidad, pero no deberán eliminarse o fusionarse las responsabilidades conceptuales anteriores sin una revisión arquitectónica aprobada.

### DB-013 — Identidad de la secretaria
La identidad vigente podrá almacenarse en `user_settings` o en una tabla auxiliar justificada; el historial de nombres deberá conservarse mediante auditoría o estructura histórica equivalente.

### DB-014 — Acceso operativo restringido
Los workflows de producción deberán preferir funciones/RPC, roles o credenciales con permisos mínimos en lugar de otorgar acceso administrativo irrestricto a toda la base cuando no sea necesario.

### DB-015 — Auditoría append-only
Los roles operativos normales no deberán poder modificar o borrar arbitrariamente registros históricos de auditoría.

---

# 36. Auditoría

### AUDIT-001 — Registro permanente
Las modificaciones relevantes deberán registrar auditoría.

### AUDIT-002 — Antes/después
Cuando corresponda, deberá conservarse el estado anterior y posterior.

### AUDIT-003 — Actor/origen
La auditoría deberá indicar quién o qué originó el cambio:

- Telegram;
- ChatGPT/MCP;
- n8n;
- sistema;
- usuario;
- IA.

### AUDIT-004 — Fecha
Toda entrada de auditoría deberá tener timestamp.

### AUDIT-005 — Tareas
Cambios de estado de tareas deberán auditarse.

### AUDIT-006 — Correcciones
Correcciones de memoria deberán auditarse.

### AUDIT-007 — Configuración
Cambios relevantes de configuración deberán auditarse.

### AUDIT-008 — Identidad
Cambios de nombre de la secretaria deberán auditarse.

### AUDIT-009 — Base
Para cambios críticos se podrán utilizar triggers de PostgreSQL para reducir dependencia del workflow.

---

# 37. Duplicados e idempotencia

### DUP-001 — Clave de idempotencia
Las ingestas deberán disponer de una clave de idempotencia o combinación equivalente.

### DUP-002 — Hash
Los archivos deberán poder deduplicarse mediante SHA-256.

### DUP-003 — Telegram
Los identificadores de Telegram deberán ayudar a detectar eventos repetidos.

### DUP-004 — Drive
Los identificadores y hash de Drive deberán ayudar a evitar reprocesamiento.

### DUP-005 — Tarea duplicada
Un reintento del mismo evento no deberá crear una segunda tarea.

### DUP-006 — Notificación duplicada
Un reintento de envío no deberá generar una segunda notificación si la primera ya fue confirmada como exitosa.

### DUP-007 — Orígenes múltiples
Un mismo archivo recibido por dos fuentes podrá registrar ambas ubicaciones sin duplicar el contenido lógico.

---

# 38. Seguridad

### SEC-001 — Secretos fuera de Git
Ninguna API key, token o secreto deberá incluirse en GitHub.

### SEC-002 — Variables/credenciales seguras
Las claves deberán almacenarse en n8n Credentials, Supabase Secrets, variables de entorno o mecanismo equivalente.

### SEC-003 — Service role
La clave `service_role` de Supabase no deberá exponerse a clientes no confiables.

### SEC-004 — Mínimo privilegio
Cada integración deberá usar el mínimo permiso necesario.

### SEC-005 — MCP restringido
MCP no deberá exponer herramientas administrativas generales.

### SEC-006 — No borrar memoria
Telegram y MCP no deberán disponer de borrado físico de memoria histórica.

### SEC-007 — RLS
El diseño deberá prepararse para RLS por usuario.

### SEC-008 — Autorización de Telegram
El bot personal deberá restringir operaciones sensibles al usuario/chat autorizado de V1.

### SEC-009 — Logging sin secretos
Los logs no deberán exponer claves o tokens completos.

### SEC-010 — Prompt injection
El sistema deberá asumir que documentos, páginas web, transcripciones y archivos pueden contener instrucciones maliciosas o accidentales. Esas instrucciones no deberán poder anular los prompts de sistema ni autorizar herramientas.

### SEC-011 — No ejecución de archivos
Los archivos incorporados como memoria deberán tratarse como contenido. No deberán ejecutarse scripts, macros, binarios o código contenido en ellos como parte del procesamiento normal.

### SEC-012 — MCP cifrado
La comunicación MCP remota deberá utilizar TLS/HTTPS y autenticación.

### SEC-013 — Webhooks autenticados
Los webhooks que soporten secretos de verificación deberán utilizarlos.

### SEC-014 — Acceso a Supabase
Las credenciales administrativas de Supabase deberán reservarse para operaciones que realmente las necesiten y no exponerse a la IA como herramienta genérica.

### SEC-015 — Minimización de datos
Los workflows deberán evitar enviar a proveedores externos datos no necesarios para completar la operación solicitada.

---

# 39. Fiabilidad y resiliencia

### REL-001 — Error de proveedor IA
Si un proveedor de IA falla, la entrada deberá quedar en estado recuperable.

### REL-002 — Error de Drive
Si falla el archivo del original, el sistema deberá registrar el error y reintentar según política.

### REL-003 — Error de Telegram
Los fallos temporales de Telegram deberán admitir reintentos.

### REL-004 — Error de Supabase
No deberá marcarse una operación como completada si el estado esencial no pudo persistirse.

### REL-005 — Continuación
Después de un reinicio de n8n, los trabajos pendientes deberán poder identificarse desde Supabase.

### REL-006 — Watchdog
Deberá existir un proceso de control de trabajos/recordatorios vencidos.

### REL-007 — Estado visible
Los errores importantes deberán quedar registrados para diagnóstico.

### REL-008 — Monitoreo de Telegram
El sistema deberá supervisar la salud del mecanismo de recepción de Telegram. Si se utiliza webhook, deberá vigilarse el estado del webhook y las fallas reiteradas.

### REL-009 — Ventana de actualizaciones
La operación deberá considerar que Telegram no conserva indefinidamente las actualizaciones no recibidas. El sistema deberá detectar indisponibilidades prolongadas antes de que puedan producir pérdida de eventos.

### REL-010 — Recuperación después de reinicio
Un reinicio del NAS o de n8n no deberá provocar que una tarea persistida o un recordatorio pendiente desaparezca.

### REL-011 — Dependencia degradada
Cuando un proveedor secundario falle, el sistema deberá poder seguir conservando las entradas aunque la interpretación quede pendiente.

---

# 40. Rendimiento y costo

### PERF-001 — No enviar toda la memoria
Las consultas a IA deberán recuperar solo el contexto relevante.

### PERF-002 — RAG
Las consultas históricas deberán utilizar recuperación previa de fragmentos relevantes antes de invocar un modelo generativo cuando corresponda.

### PERF-003 — Modelo adecuado
No deberá utilizarse automáticamente el modelo más caro para operaciones simples.

### PERF-004 — Procesar una vez
Un original ya procesado no deberá volver a procesarse salvo reprocesamiento explícito, prueba A/B o cambio justificado.

### PERF-005 — Embeddings regenerables
Los embeddings deberán considerarse datos derivados regenerables.

### PERF-006 — Original prioritario
La conservación del original deberá tener prioridad sobre caches o artefactos regenerables.

### PERF-007 — Medición de uso IA
El sistema deberá registrar, cuando los proveedores lo permitan, el modelo utilizado y métricas de consumo necesarias para estimar costos.

### PERF-008 — Control de gasto
La arquitectura deberá permitir definir posteriormente un límite o alerta mensual de gasto de APIs sin rediseñar los workflows principales.

### PERF-009 — Optimización de contexto
La cantidad de fragmentos recuperados y enviados al modelo deberá ser configurable y evaluarse según calidad/costo.

---

# 41. Backup y recuperación

### BCK-001 — Backup de base
La información crítica almacenada en Supabase deberá contar con una estrategia periódica de backup independiente de la operación diaria.

### BCK-002 — Originales
Los originales considerados permanentes deberán contar con una estrategia de recuperación ante borrado accidental o pérdida del repositorio principal.

### BCK-003 — Copia independiente
La estrategia deberá evitar que una sola credencial, cuenta o error lógico pueda eliminar simultáneamente la única copia de todos los datos críticos.

### BCK-004 — Restauración probada
Antes de declarar V1 estable deberá ejecutarse al menos una prueba documentada de restauración de la base y de recuperación de un original.

### BCK-005 — Configuración y workflows
La configuración reproducible, migraciones y exportaciones de workflows deberán conservarse en el repositorio del proyecto.

### BCK-006 — Objetivos de recuperación
`03_ARQUITECTURA.md` deberá definir objetivos razonables de RPO/RTO para la V1 personal.

---

# 42. Operación y monitoreo

### OPS-001 — Health checks
Deberán existir verificaciones periódicas del estado de n8n y de las integraciones críticas.

### OPS-002 — Fallos repetidos
Fallos reiterados en Telegram, Drive, Supabase o proveedores de IA deberán generar una alerta operacional visible.

### OPS-003 — Cola pendiente
Deberá poder identificarse cuántas ingestas, transcripciones, interpretaciones y recordatorios permanecen pendientes o en error.

### OPS-004 — Logs técnicos
Los logs técnicos podrán tener retención limitada y depurarse, siempre que no sean la única copia de memoria, auditoría o evidencia.

### OPS-005 — Versiones
Deberán registrarse las versiones relevantes de n8n y componentes críticos utilizados en producción para facilitar diagnóstico y upgrades.

### OPS-006 — Seguridad periódica
La instalación n8n self-hosted deberá someterse a revisiones de seguridad periódicas, incluyendo las herramientas de auditoría disponibles en n8n.

---

# 43. Desarrollo y control de cambios

### DEV-001 — Repositorio
El código, documentación, migraciones y archivos versionables del proyecto deberán mantenerse en el repositorio privado `saldiviapablo/secretaria`.

### DEV-002 — Antigravity
Antigravity será el entorno/agente principal utilizado para implementar el proyecto, pero deberá obedecer PRD, SRS y documentos arquitectónicos aprobados.

### DEV-003 — Sin cambios estructurales improvisados
Antigravity no deberá cambiar por iniciativa propia decisiones arquitectónicas congeladas.

### DEV-004 — Migraciones
Los cambios de esquema de Supabase deberán generarse como migraciones versionadas.

### DEV-005 — Workflows
Los workflows de n8n deberán exportarse en un formato versionable.

### DEV-006 — Secretos
Ningún secreto real deberá incluirse en archivos del repositorio.

### DEV-007 — Cambios trazables
Los cambios deberán poder asociarse a requisitos del SRS y a pruebas cuando corresponda.

---

# 44. Futuro multiusuario

### MULTI-001 — Preparación
El esquema deberá estar preparado para múltiples usuarios desde V1.

### MULTI-002 — Aislamiento
Los registros deberán poder aislarse por usuario.

### MULTI-003 — Credenciales propias
Una futura versión deberá poder evolucionar hacia credenciales propias por usuario.

### MULTI-004 — Nombre de secretaria
Cada usuario podrá tener su propio nombre interno de secretaria.

### MULTI-005 — Telegram compartido
Si se utiliza un bot compartido, el nombre visible del encabezado será común al bot.

### MULTI-006 — Bot individual
Para nombre visible independiente por usuario, se deberá evaluar un bot/token individual.

---

# 45. Requisitos fuera de alcance de V1

Los siguientes elementos no serán requisitos obligatorios de V1:

### OOS-001
Integración Gmail.

### OOS-002
Google Calendar obligatorio.

### OOS-003
Mini App de Telegram obligatoria.

### OOS-004
Síntesis de voz/TTS como respuesta estándar.

### OOS-005
Recorte automático de fragmentos de audio.

### OOS-006
Cambio automático del `@username` del bot.

### OOS-007
Despliegue público multiusuario.

### OOS-008
Borrado remoto de memoria histórica.

---

# 46. Requisitos de verificación

### TEST-001 — Trazabilidad
Cada requisito funcional deberá tener al menos un caso de prueba asociado antes de declarar V1 terminada.

### TEST-002 — Pruebas de fechas
Deberán probarse expresiones relativas con distintos días de la semana y límites de mes/año.

### TEST-003 — Ambigüedad de personas
Deberá probarse el caso de dos personas con el mismo nombre.

### TEST-004 — Duplicados
Deberá probarse que un mismo evento procesado dos veces no crea duplicados.

### TEST-005 — Reintento recordatorio
Deberá probarse un fallo de envío seguido de reintento.

### TEST-006 — Memoria histórica
Deberá probarse una corrección y verificar que el dato anterior permanezca recuperable.

### TEST-007 — Evidencia
Deberá probarse que una respuesta pueda llevar al texto/audio original.

### TEST-008 — Modo descanso
Deberá probarse que no envía avisos normales durante descanso y reanuda después.

### TEST-009 — MCP
Deberá probarse creación y consulta de tarea desde ChatGPT/MCP sin separar la memoria.

### TEST-010 — Nombre
Deberá probarse onboarding, cambio de nombre, persistencia e historial.

### TEST-011 — PDF/Excel
Deberá verificarse que solo se generen archivos bajo pedido explícito.

### TEST-012 — Reportes
Deberán probarse día, semana, mes y rango personalizado.

### TEST-013 — A/B de transcripción
Deberá existir un benchmark documentado antes de elegir motor principal definitivo.

### TEST-014 — Archivo Telegram grande
Deberá probarse un archivo que supere el límite de descarga de la Bot API estándar y verificar el fallback sin pérdida de la entrada.

### TEST-015 — Prompt injection
Deberá probarse un documento o página que incluya instrucciones maliciosas para verificar que no pueda invocar herramientas ni modificar reglas del sistema.

### TEST-016 — Restauración
Deberá ejecutarse una prueba de restauración de base y recuperación de originales.

### TEST-017 — Hechos históricos
Deberá probarse un hecho que cambia con el tiempo y verificar que puedan consultarse estado actual e histórico.

### TEST-018 — Reinicio
Deberá probarse un reinicio de n8n/NAS con tareas y recordatorios pendientes.

### TEST-019 — Webhook
Deberá verificarse la autenticación del webhook de Telegram si se utiliza ese modo.

### TEST-020 — Sin evidencia
Deberá comprobarse que el sistema no invente una respuesta cuando no existen fuentes suficientes.

### TEST-021 — Mensaje editado
Deberá probarse el versionado de un mensaje editado cuando Telegram entregue dicho evento.

---

# 47. Criterios de aceptación global de V1

La V1 no deberá considerarse terminada hasta que se cumplan simultáneamente estas condiciones:

1. Los flujos críticos están implementados.
2. Los requisitos obligatorios de este SRS están cubiertos.
3. Existe trazabilidad requisito → prueba.
4. No existen fallos conocidos que puedan provocar pérdida silenciosa de memoria.
5. No existen fallos conocidos que permitan borrar memoria histórica desde Telegram o MCP.
6. Las fechas relativas críticas están validadas.
7. La ambigüedad de personas/tareas está validada.
8. Los recordatorios tienen persistencia y recuperación.
9. Los originales pueden recuperarse.
10. La búsqueda semántica y textual funciona.
11. Telegram y MCP operan sobre la misma memoria.
12. La identidad/nombre de la secretaria funciona según V1.
13. Los secretos no están versionados.
14. Las migraciones de Supabase están versionadas.
15. Los workflows de n8n están exportados/versionados.
16. El Test Plan de V1 está aprobado y ejecutado.
17. Existe una estrategia de backup y se probó al menos una restauración.
18. Se verificó el fallback de archivos grandes de Telegram.
19. Se verificaron controles básicos contra prompt injection.
20. n8n puede reiniciarse sin perder tareas o recordatorios persistidos.

---

# 48. Matriz resumida de trazabilidad con PRD

| Área del PRD | Requisitos SRS principales |
|---|---|
| Memoria general | MEM-001 a MEM-012, EMB-001 a EMB-010 |
| Originales | SRC-001 a SRC-009 |
| Telegram | TG-001 a TG-017 |
| Audio/transcripción | AUD-001 a AUD-008, TRN-001 a TRN-007 |
| Diagramas | VIS-001 a VIS-007 |
| Tareas | TASK-001 a TASK-018 |
| Prioridades | PRI-001 a PRI-005 |
| Fechas | DATE-001 a DATE-014 |
| Personas | ENT-001 a ENT-006 |
| Hechos históricos | FACT-001 a FACT-006 |
| Proyectos | PROJ-001 a PROJ-005 |
| Clarificaciones | CLR-001 a CLR-006 |
| Recordatorios | REM-001 a REM-012 |
| Descanso | DND-001 a DND-010 |
| Resúmenes | BRF-001 a BRF-007 |
| Reportes | REP-001 a REP-010 |
| PDF / Excel | PDF-001 a PDF-005, XLS-001 a XLS-005 |
| Identidad | IDP-001 a IDP-011 |
| Experiencia conversacional | UX-001 a UX-006 |
| Inteligencia artificial | IA-001 a IA-016 |
| ChatGPT/MCP | MCP-001 a MCP-016 |
| Google Drive | GDR-001 a GDR-009 |
| n8n | N8N-001 a N8N-016 |
| Supabase | DB-001 a DB-015 |
| Seguridad | SEC-001 a SEC-015 |
| Auditoría | AUDIT-001 a AUDIT-009 |
| Duplicados | DUP-001 a DUP-007 |
| Resiliencia | REL-001 a REL-011 |
| Rendimiento/costo | PERF-001 a PERF-009 |
| Backup | BCK-001 a BCK-006 |
| Operación | OPS-001 a OPS-006 |
| Desarrollo | DEV-001 a DEV-007 |
| Multiusuario futuro | MULTI-001 a MULTI-006 |

---

# 49. Regla para Antigravity

Antes de implementar o modificar una función, Antigravity deberá:

1. identificar qué requisito(s) del SRS afecta;
2. evitar cambiar el significado del requisito sin aprobación;
3. implementar de manera compatible con `01_PRD.md`;
4. mantener migraciones y workflows versionados;
5. agregar o actualizar pruebas;
6. informar cualquier conflicto entre requisitos antes de improvisar una solución.

Antigravity no deberá rediseñar por iniciativa propia los principios aprobados de memoria permanente, ambigüedad, trazabilidad, no borrado, fechas, idempotencia o separación original/interpretación/acción.

---

# 50. Próximo documento

Una vez auditado y aprobado este SRS, el siguiente documento será:

`03_ARQUITECTURA.md`

Ese documento definirá cómo se distribuyen técnicamente las responsabilidades entre:

- Telegram;
- n8n;
- Google Drive;
- Supabase;
- OpenAI;
- Gemini;
- MCP;
- GitHub;
- Antigravity.

`03_ARQUITECTURA.md` no deberá redefinir los requisitos de este SRS; deberá diseñar una solución que los cumpla.
