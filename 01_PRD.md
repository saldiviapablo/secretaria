# PRD — Secretaria Virtual con IA

**Proyecto:** Secretaria Virtual con IA  
**Repositorio previsto:** `saldiviapablo/secretaria`  
**Documento:** `docs/01_PRD.md`  
**Versión:** 1.2  
**Fecha:** 2026-08-29  
**Estado:** APROBADO Y CONGELADO — Baseline V1

---

## 0. Historial de revisión

### v1.2 — Auditoría integral aprobada
Esta versión incorpora la auditoría completa de los requisitos definidos durante la conversación y corrige omisiones de la v1.1. En particular:

- prioridad manual + prioridad inferida por IA;
- horario de silencio recurrente + modo descanso temporal;
- procesamiento automático en segundo plano;
- preservación explícita del mensaje original de Telegram y sus identificadores;
- evidencia con enlace/original de Drive + reenvío/reproducción en Telegram;
- reportes por día, semana, mes o rango personalizado y sobre cualquier información, no solo tareas;
- hora configurable para el resumen nocturno;
- reintentos y control de entrega de recordatorios;
- captura histórica de páginas web cuando sea técnicamente posible;
- configuración inferior de Telegram mediante menú de comandos en V1, sin exigir una Mini App;
- unificación explícita de todos los canales en la misma memoria de Supabase;
- preparación futura para credenciales y conexiones propias por usuario.

---

## 1. Visión del producto

Construir una secretaria virtual personal, proactiva y con memoria histórica permanente, capaz de recibir información por múltiples canales, comprenderla mediante inteligencia artificial, almacenarla con trazabilidad completa, detectar y administrar tareas, recordar compromisos, responder consultas sobre información pasada y generar reportes cuando el usuario lo solicite.

La interacción principal será mediante un bot de Telegram en lenguaje natural. El usuario no deberá aprender comandos rígidos para las operaciones habituales. También se habilitará acceso desde ChatGPT mediante MCP para consultar y operar el mismo sistema.

La experiencia buscada es la de una secretaria de confianza: el usuario habla, escribe, manda archivos, dibuja o pregunta; el sistema entiende, clasifica, relaciona, recuerda, sigue, avisa y recupera.

---

## 2. Principio rector

> **Automatizar todo lo posible, pero nunca inventar información cuando una ambigüedad pueda modificar tareas, personas, fechas, horarios, proyectos o memoria histórica.**

La seguridad, la trazabilidad y la posibilidad de volver a la fuente original deberán prevalecer sobre la conveniencia o una respuesta aparentemente más inteligente.

---

## 3. Objetivos principales

1. Centralizar notas de voz, transcripciones, mensajes, documentos, dibujos, diagramas, imágenes, páginas web y otras fuentes en una única memoria consultable.
2. Conservar los originales y la evidencia de origen de cada información.
3. Detectar automáticamente tareas, actividades realizadas, fechas, horarios, personas, proyectos, compromisos, ideas, decisiones y relaciones.
4. Mantener memoria semántica para recuperar información por significado y no solamente por palabras exactas.
5. Proporcionar recordatorios automáticos y seguimiento proactivo sin resultar molesto.
6. Permitir consultas y acciones naturales desde Telegram y ChatGPT.
7. Generar reportes escritos en Telegram y, solo a pedido explícito, documentos PDF o Excel.
8. Mantener historial permanente y trazabilidad de cambios.
9. Preparar la arquitectura desde V1 para una futura versión multiusuario.
10. Permitir que la secretaria tenga una identidad y un nombre configurable por el usuario.
11. Procesar la información automáticamente en segundo plano para reducir al mínimo la administración manual por parte del usuario.

---

## 4. Usuario objetivo y evolución futura

V1 será de uso personal y tendrá un único usuario operativo.

La arquitectura deberá incorporar `user_id`, aislamiento de datos y controles de acceso desde el comienzo para permitir una futura versión multiusuario sin rediseñar el núcleo de la base de datos.

En una futura versión, cada usuario podrá asociar, según la arquitectura que se defina:

- sus propias API keys de proveedores de IA;
- su propia conexión de ChatGPT/MCP;
- sus propias cuentas o servicios externos;
- y, si se requiere un nombre de bot visible independiente por usuario, su propio bot/token de Telegram.

---

## 5. Canales de entrada

El sistema deberá aceptar, según corresponda a cada integración:

- mensajes de texto de Telegram;
- mensajes de voz y audios de Telegram;
- archivos enviados por Telegram;
- transcripciones ya generadas;
- archivos de audio provenientes de grabadoras o aplicaciones externas;
- Google Drive;
- PDF;
- documentos de texto y Word;
- Excel y otros documentos tabulares compatibles;
- fotografías;
- capturas de pantalla;
- dibujos y notas manuscritas digitalizadas;
- diagramas y diagramas de flujo;
- páginas web o enlaces que el usuario decida guardar;
- ChatGPT mediante MCP;
- fuentes adicionales que puedan agregarse posteriormente.

La incorporación de una nueva fuente no deberá requerir rediseñar la memoria central.

---

## 6. Procesamiento automático en segundo plano

El funcionamiento normal deberá requerir la menor intervención posible.

Cuando llegue una nueva entrada, el sistema deberá poder, automáticamente y sin pedir confirmaciones innecesarias:

1. registrar que la entrada llegó;
2. preservar el original;
3. detectar duplicados;
4. extraer o transcribir el contenido;
5. interpretarlo mediante IA;
6. crear memoria semántica;
7. relacionarlo con entidades, proyectos u otras memorias;
8. detectar tareas, compromisos, decisiones o hechos;
9. crear acciones operativas cuando la información sea suficientemente clara;
10. programar recordatorios cuando corresponda.

El usuario solo deberá ser interrumpido cuando falte información relevante, exista una ambigüedad real, se requiera una decisión del usuario o sea necesario comunicar algo importante.

---

## 7. Memoria general

Para el usuario existirá una única memoria general.

El usuario no tendrá que clasificar manualmente cada entrada en carpetas, áreas o categorías rígidas. La IA podrá asignar automáticamente:

- etiquetas;
- temas;
- relaciones;
- entidades;
- proyectos;
- contexto;
- importancia;
- embeddings para búsqueda semántica.

Sin embargo, la información que requiera precisión operativa no deberá quedar únicamente como etiquetas. Tareas, personas, fechas, horarios, proyectos, estados, vencimientos y recordatorios deberán almacenarse también como datos estructurados.

Toda información procedente de Telegram, Google Drive, ChatGPT/MCP u otros canales deberá terminar en la misma memoria lógica del usuario en Supabase, conservando siempre su origen.

---

## 8. Permanencia y trazabilidad

La memoria histórica será permanente.

Las interfaces normales del producto —incluidos Telegram y MCP— no deberán ofrecer borrado físico de memoria histórica.

El sistema podrá:

- corregir;
- invalidar;
- archivar;
- marcar como histórico;
- cancelar una tarea;
- reemplazar una interpretación vigente;

pero deberá conservar el estado anterior y el historial de cambios.

Se distinguirán conceptualmente tres capas:

1. **Original:** lo que realmente llegó al sistema.
2. **Interpretación:** lo que una IA entendió del original.
3. **Acción/estado:** lo que el sistema creó o modificó a partir de esa interpretación.

Una corrección nunca deberá destruir el original ni ocultar silenciosamente la versión anterior.

---

## 9. Conservación de originales

Cuando exista un archivo original, deberá conservarse de forma permanente según la política de almacenamiento del sistema.

Para audios y archivos se conservará, cuando esté disponible:

- archivo original;
- nombre original;
- tipo MIME;
- tamaño;
- fecha y hora de ingreso;
- origen;
- identificadores de Telegram;
- identificadores de Google Drive;
- duración;
- huella SHA-256;
- relación con la memoria derivada.

Google Drive será el repositorio principal de originales de V1. Supabase almacenará la información estructurada, las relaciones y las referencias necesarias para recuperar esos originales.

El mismo archivo recibido por diferentes canales no deberá duplicar innecesariamente el procesamiento. La huella SHA-256, los identificadores de origen y mecanismos de idempotencia deberán ayudar a detectar duplicados.

Si un contenido idéntico aparece en dos fuentes diferentes, el sistema deberá poder registrar ambas ubicaciones/orígenes sin interpretar que se trata de dos hechos independientes.

---

## 10. Preservación específica de Telegram

Cuando una entrada provenga de Telegram, se deberá conservar, cuando esté disponible:

- contenido original del mensaje;
- fecha y hora del mensaje;
- identificador del mensaje;
- identificador del chat;
- identificador del archivo o `file_id` cuando exista;
- tipo de mensaje;
- archivo original cuando corresponda;
- relación con la memoria creada;
- relación con cualquier respuesta o aclaración posterior.

La interpretación de IA nunca deberá reemplazar el mensaje original.

---

## 11. Transcripciones

Los audios podrán ser transcritos automáticamente mediante proveedores de IA configurables.

Se realizará una prueba A/B con audios reales del usuario para seleccionar el motor principal de transcripción.

El sistema deberá poder conservar múltiples versiones de una transcripción si un audio es procesado por más de un modelo.

La transcripción literal de cada ejecución deberá mantenerse disponible y no deberá ser sobrescrita silenciosamente por una versión corregida o resumida por IA.

Cuando existan timestamps, deberán conservarse para permitir recuperar el fragmento correspondiente del audio.

El usuario deberá poder solicitar la fuente de una afirmación y recibir, cuando esté disponible:

- identificación del archivo de origen;
- fecha;
- transcripción literal relevante;
- rango temporal del audio;
- enlace o referencia al original almacenado;
- audio original nuevamente reproducible/enviable dentro del chat de Telegram.

La capacidad de recortar y enviar exclusivamente un fragmento de audio podrá evaluarse como mejora posterior; V1 deberá garantizar como mínimo el acceso al audio original completo y al rango temporal relevante.

---

## 12. Comprensión de imágenes, dibujos y diagramas

La IA deberá poder procesar dibujos, fotografías, capturas de pantalla y diagramas.

Según el contenido, deberá intentar extraer:

- texto;
- texto manuscrito;
- bloques;
- flechas;
- relaciones;
- secuencias;
- conceptos;
- tareas;
- ideas;
- decisiones;
- proyectos asociados.

La imagen original deberá conservarse.

El resultado interpretado deberá quedar relacionado con el original y ser corregible sin modificarlo.

---

## 13. Páginas web y enlaces

Cuando el usuario decida guardar una página web, el sistema deberá conservar como mínimo:

- URL;
- título cuando esté disponible;
- fecha y hora de captura;
- contenido extraído relevante;
- relación con la memoria creada.

Cuando sea técnicamente viable y razonable, deberá conservar también una representación o snapshot del contenido visto en ese momento, de modo que cambios futuros en la página no alteren la evidencia histórica de lo que fue almacenado.

---

## 14. Gestión automática de tareas

Cuando una entrada contenga una tarea suficientemente clara, el sistema deberá crearla automáticamente sin pedir una confirmación adicional.

Ejemplo:

> “Mañana a las 15 tengo que llamar a Juan Pérez por el presupuesto.”

Deberá crear una tarea con la información estructurada correspondiente.

El sistema también permitirá registrar una actividad ya realizada aunque nunca hubiera existido previamente como tarea pendiente.

Ejemplo:

> “Acabo de terminar un reporte para mi jefe sobre costos operativos.”

Deberá registrarse como actividad/tarea completada y aparecer en los reportes históricos de trabajo realizado.

Los posibles estados incluirán como mínimo:

- pendiente;
- en progreso;
- completada;
- pospuesta;
- cancelada.

Las tareas canceladas o corregidas seguirán formando parte del historial.

---

## 15. Prioridades de tareas

Las tareas podrán manejar como mínimo las siguientes prioridades explícitas:

- urgente;
- alta;
- normal;
- baja.

El usuario podrá asignar o modificar la prioridad mediante lenguaje natural.

Cuando el usuario no la indique, la IA podrá inferir una prioridad según contexto, vencimiento, esfuerzo, consecuencias y tipo de tarea.

La prioridad indicada expresamente por el usuario deberá prevalecer sobre una prioridad inferida automáticamente, salvo que el usuario posteriormente autorice su modificación.

La prioridad podrá influir en:

- frecuencia de seguimiento;
- anticipación de recordatorios;
- orden en resúmenes;
- posibilidad de atravesar el modo descanso en situaciones realmente críticas.

---

## 16. Finalización natural de tareas

El usuario podrá completar tareas usando lenguaje natural.

Ejemplo:

> “Ya llamé a Juan.”

Si existe una única coincidencia inequívoca, el sistema podrá completar la tarea correspondiente.

Si existen varias personas o tareas plausibles, el sistema deberá preguntar antes de modificar el estado.

Ejemplo:

> “Tengo dos personas llamadas Juan relacionadas con tus tareas: Juan Pérez y Juan Gómez. ¿A cuál te referís?”

Una vez aclarado, el sistema deberá confirmar qué tarea fue modificada y conservar el evento en el historial.

---

## 17. Regla de ambigüedad

La seguridad tendrá prioridad sobre la inferencia.

Si una ambigüedad puede modificar:

- una persona;
- una tarea;
- una fecha;
- un horario;
- un proyecto;
- un compromiso;
- un dato de memoria histórica;

la IA deberá solicitar aclaración en lugar de adivinar.

Aunque el sistema tenga una alta probabilidad de saber a quién se refiere el usuario, si existen múltiples candidatos reales deberá preguntar.

---

## 18. Fechas y horarios

El sistema deberá comprender expresiones relativas como:

- hoy;
- mañana;
- pasado mañana;
- este miércoles;
- el miércoles que viene;
- el miércoles de la semana próxima;
- dentro de dos horas;
- esta tarde.

La resolución deberá realizarse utilizando la fecha/hora real de captura y la zona horaria configurada del usuario.

Se deberá conservar:

- expresión original;
- fecha/hora en que fue dicha;
- zona horaria;
- fecha resuelta;
- hora resuelta, si existe.

El sistema no deberá inventar `00:00` cuando el usuario especifica una fecha pero no una hora.

Si falta un dato importante podrá preguntar, pero deberá permitir respuestas como “todavía no sé la hora”, dejando el dato pendiente para completarlo después.

Cuando una tarea quede sin hora, el sistema podrá volver a preguntar de manera razonable más adelante si disponer de ese horario mejora los recordatorios o la planificación.

---

## 19. Preguntas contextuales

Cuando falte información útil para un compromiso, la secretaria podrá hacer preguntas relacionadas.

Ejemplo:

> Usuario: “El miércoles tengo turno médico.”

La secretaria podrá preguntar:

- “¿A qué hora?”
- “¿Con qué médico?”
- “¿Querés recordar algo para preguntarle ese día?”

El mismo principio se aplicará a reuniones, eventos, llamadas, entregas u otros compromisos cuando sea razonable.

La secretaria no deberá convertir estas preguntas en un interrogatorio innecesario.

---

## 20. Personas y entidades

El sistema deberá mantener una memoria de personas y otras entidades relacionadas con la información del usuario.

Podrá relacionar una persona con:

- tareas;
- reuniones;
- notas;
- proyectos;
- decisiones;
- compromisos;
- organizaciones;
- información histórica.

Podrá registrar alias o variantes de nombres, pero los alias no podrán utilizarse para resolver automáticamente una identidad cuando existan varias personas compatibles.

Si existen dos o más personas plausibles con el mismo nombre, el sistema deberá pedir aclaración antes de ejecutar una modificación relevante.

---

## 21. Proyectos y clasificación automática

El usuario no deberá administrar una jerarquía rígida de áreas para que el sistema funcione.

La IA podrá detectar y relacionar automáticamente información perteneciente al mismo proyecto.

Ejemplo:

- una nota de voz de hoy;
- un diagrama de la semana anterior;
- una tarea de mañana;

podrán quedar asociados al mismo proyecto si existe evidencia suficiente.

Si la relación es ambigua y tiene consecuencias operativas, el sistema deberá pedir confirmación.

El usuario podrá consultar la memoria utilizando conceptos generales como trabajo, personal, fotografía o desarrollo aunque estos funcionen internamente como etiquetas/temas y no como una jerarquía manual obligatoria.

---

## 22. Recordatorios híbridos

La secretaria será proactiva.

Los recordatorios combinarán:

1. reglas fijas configurables;
2. decisiones inteligentes de IA basadas en el tipo de tarea.

Regla base inicial:

- aviso estándar 3 horas antes cuando corresponda.

Ejemplo de ajuste inteligente:

- llamada a las 15:00 → aviso fijo 3 horas antes + aviso adicional cercano, por ejemplo 10 minutos antes;
- informe que debe estar listo al día siguiente → aviso anticipado y seguimiento periódico razonable.

El sistema podrá decidir avisar con mayor anticipación cuando una tarea requiera preparación significativa.

La IA deberá evitar un nivel de insistencia molesto.

---

## 23. Seguimiento de tareas no confirmadas

Si una tarea llega a su fecha/hora objetivo y continúa pendiente, el sistema deberá seguirla hasta que el usuario la marque como:

- realizada;
- pospuesta;
- cancelada;
- aún pendiente.

El seguimiento deberá ser configurable y adaptarse al tipo, prioridad, urgencia y esfuerzo estimado de la tarea.

---

## 24. Fiabilidad de recordatorios

Un recordatorio importante no deberá perderse silenciosamente por un fallo temporal de Telegram, Internet, n8n u otro componente.

El producto deberá contemplar:

- registro de recordatorios pendientes;
- registro del intento de entrega;
- reintentos razonables ante fallos temporales;
- prevención de envíos duplicados;
- verificación periódica de recordatorios vencidos que todavía no tengan una entrega exitosa.

La implementación técnica exacta se definirá en el SRS y la arquitectura.

---

## 25. Horario de silencio recurrente

El usuario podrá configurar un horario habitual durante el cual la secretaria no deberá enviar notificaciones normales.

Ejemplo:

- silencio diario desde las 22:30 hasta las 08:00.

Durante ese horario:

- el sistema continuará procesando información;
- las tareas y recuerdos seguirán registrándose;
- las notificaciones normales quedarán retenidas o reprogramadas;
- solo situaciones configuradas como verdaderamente críticas podrán atravesar el silencio.

El horario deberá poder modificarse conversacionalmente.

---

## 26. Modo descanso temporal

Además del horario recurrente, la secretaria deberá tener un modo descanso/no molestar temporal activable por lenguaje natural sin exigir un comando exacto.

Ejemplos aceptables:

- “No me molestes.”
- “Ponete en modo descanso.”
- “No me avises más por hoy.”
- “Silencio hasta mañana.”
- “No me mandes nada por tres horas.”

Si falta información, la secretaria deberá preguntar desde cuándo y/o hasta cuándo debe aplicarse.

Ejemplo:

> “¿Querés que empiece desde ahora? ¿Hasta qué hora?”

Durante el modo descanso:

- el procesamiento interno continuará;
- se seguirán guardando entradas;
- se seguirán detectando tareas;
- se seguirá actualizando la memoria;
- se evitarán las notificaciones normales.

Al finalizar el descanso temporal, el sistema deberá volver automáticamente al horario y comportamiento habitual previamente configurados.

---

## 27. Mensaje de buenos días

A una hora configurable, la secretaria podrá enviar un saludo de buenos días con trato cordial y un resumen útil.

Podrá incluir:

- tareas del día;
- tareas vencidas;
- próximos compromisos;
- eventos importantes;
- tareas posiblemente olvidadas;
- información ingresada durante el modo descanso;
- asuntos que la IA considere relevantes.

La hora deberá poder modificarse conversacionalmente.

Cuando corresponda, el mensaje de buenos días servirá también como reanudación natural después del período de silencio o descanso.

---

## 28. Resumen de cierre del día

El usuario podrá habilitar o deshabilitar un cierre diario y configurar la hora de recepción.

Podrá incluir:

- tareas completadas;
- tareas que continúan pendientes;
- tareas pospuestas;
- compromisos del día siguiente;
- actividades realizadas;
- situaciones sin estado claro que convenga confirmar.

La hora deberá poder modificarse conversacionalmente.

---

## 29. Informes y reportes

El usuario podrá solicitar reportes por lenguaje natural.

Los reportes podrán abarcar no solamente tareas, sino cualquier información existente en la memoria que pueda recuperarse de forma confiable: actividades, proyectos, decisiones, personas, ideas, compromisos, documentos, notas u otros elementos.

El usuario podrá pedir períodos como:

- hoy;
- ayer;
- esta semana;
- la semana pasada;
- este mes;
- un mes determinado;
- un rango de fechas personalizado.

Ejemplos:

- “¿Qué hice hoy?”
- “¿Qué tareas terminé esta semana?”
- “Dame un reporte de agosto.”
- “Mostrame todo lo relacionado con Juan Pérez en este proyecto.”
- “¿Qué decisiones tomé sobre este tema?”
- “Dame un reporte desde el 5 hasta el 18 de agosto.”

Por defecto, el resultado deberá presentarse primero como texto dentro de Telegram.

No se deberá generar automáticamente un documento.

Solo si el usuario lo pide de manera explícita:

- “Haceme un PDF con esto.”
- “Haceme un Excel con estas tareas.”

se generará el archivo correspondiente.

Los documentos generados deberán mantener relación con la consulta y las fuentes que los originaron, para que posteriormente pueda reconstruirse de dónde salió el contenido del informe.

---

## 30. Telegram como interfaz principal

Telegram será una interfaz de control conversacional completa.

El usuario podrá, mediante texto, voz, archivos y botones cuando sea conveniente:

- agregar información;
- crear tareas;
- completar tareas;
- posponer tareas;
- cambiar prioridades;
- corregir memoria;
- consultar memoria;
- consultar personas;
- consultar proyectos;
- consultar pendientes;
- solicitar reportes;
- pedir PDF/Excel;
- activar modo descanso;
- modificar horarios;
- modificar preferencias;
- reproducir originales cuando estén disponibles;
- administrar la identidad de la secretaria.

Los comandos pueden existir como accesos rápidos, pero no deberán ser necesarios para la experiencia principal.

---

## 31. Identidad y nombre personalizable de la secretaria

La secretaria deberá tener una identidad configurable por el usuario.

### 31.1 Nacimiento / onboarding inicial

En el primer inicio, si aún no existe un nombre configurado, el bot deberá iniciar un pequeño proceso de configuración y preguntar algo equivalente a:

> “Antes de empezar, ¿cómo querés que me llame?”

La respuesta se almacenará como `assistant_name`.

Ese momento se considerará el “nacimiento” o configuración inicial de la identidad de la secretaria.

### 31.2 Nombre visible del bot en Telegram

En V1, al tratarse de un bot personal, el sistema deberá sincronizar el nombre elegido con el nombre público del bot de Telegram utilizando la capacidad oficial disponible para cambiar el nombre del bot.

El objetivo es que el nombre mostrado en el encabezado del chat pase, por ejemplo, de:

`Secretaria IA`

a:

`Clara`

El cliente de Telegram podrá requerir refrescar su información o caché antes de reflejar visualmente el cambio.

El `@username` del bot es una identidad separada y no forma parte de este requisito de cambio dinámico.

### 31.3 Cambio de nombre por conversación

El usuario podrá cambiar el nombre mediante lenguaje natural.

Ejemplos:

> “A partir de ahora quiero que te llames Clara.”

> “Quiero cambiar tu nombre a Victoria.”

El sistema deberá actualizar:

- nombre vigente de la secretaria;
- nombre visible del bot personal en Telegram;
- historial de nombres;
- fecha y origen del cambio.

### 31.4 Historial de nombres

Los nombres anteriores no deberán borrarse de la memoria histórica.

Ejemplo:

- Clara → nombre anterior;
- Victoria → nombre vigente.

El usuario podrá preguntar posteriormente:

> “¿Cómo se llamaba antes mi secretaria?”

### 31.5 Configuración desde la zona inferior de Telegram

Además del lenguaje natural, deberá existir un acceso simple a configuración desde la interfaz inferior del chat.

Para V1, sin exigir una Mini App, la opción preferida será utilizar el menú de comandos del bot accesible junto al campo de escritura e incluir una opción/comando de **Configuración**.

Desde allí deberán poder iniciarse flujos para cambiar, como mínimo:

- nombre de la secretaria;
- horario del saludo de buenos días;
- horario de cierre del día;
- horario de silencio;
- modo descanso;
- preferencias de recordatorios.

También podrán utilizarse botones conversacionales para facilitar la operación.

Una Mini App podrá evaluarse posteriormente si ofrece una mejora clara de experiencia, pero no será obligatoria para V1.

### 31.6 Límite futuro multiusuario

El nombre público del bot de Telegram pertenece al bot, no a una conversación individual.

Por lo tanto:

- en V1 personal el nombre elegido podrá reflejarse en el encabezado real del bot;
- si en el futuro muchos usuarios comparten un mismo bot, cada usuario podrá tener un `assistant_name` personal dentro del sistema y en las respuestas, pero el mismo bot compartido no podrá mostrar un encabezado diferente para cada usuario;
- si en el futuro se desea que cada usuario tenga un nombre visible diferente en el encabezado de Telegram, deberá evaluarse un bot/token independiente por usuario u otra arquitectura equivalente.

---

## 32. Trato y estilo de la secretaria

La secretaria deberá comunicarse de manera cordial, clara y natural.

El trato deberá sentirse humano y útil, sin perder precisión.

El sistema deberá evitar:

- respuestas excesivamente robóticas;
- insistencia innecesaria;
- interrogatorios largos cuando no sean necesarios;
- mensajes proactivos sin valor práctico.

El nombre configurado de la secretaria podrá utilizarse en el onboarding, saludos y otros momentos donde aporte identidad, sin necesidad de repetirlo artificialmente en cada mensaje.

---

## 33. ChatGPT y MCP

El sistema deberá poder exponer funciones controladas mediante MCP para que ChatGPT pueda operar sobre la misma memoria que utiliza Telegram.

Entre las herramientas previstas se incluyen:

- buscar memoria;
- consultar tareas;
- crear tarea;
- completar tarea;
- modificar tarea;
- buscar persona;
- consultar proyecto;
- guardar nota;
- corregir información;
- solicitar reportes;
- enviar un mensaje mediante Telegram.

Una tarea creada desde ChatGPT deberá almacenarse en la misma memoria/base de tareas que una tarea creada desde Telegram o detectada desde un archivo, diferenciándose únicamente por su origen y trazabilidad.

MCP no deberá exponer una capacidad general de borrar memoria histórica.

Las herramientas deberán ser específicas y con permisos limitados.

---

## 34. Google Drive

Google Drive será una fuente de entrada y el repositorio principal de originales de V1.

El usuario podrá colocar archivos en la estructura designada y el sistema deberá detectarlos y procesarlos automáticamente.

El usuario no deberá separar manualmente cada tipo de archivo en una carpeta distinta para que la memoria funcione. La clasificación deberá realizarse automáticamente cuando sea posible.

El sistema deberá conservar referencias suficientes para recuperar el archivo original posteriormente.

---

## 35. n8n

n8n será el orquestador operativo del sistema.

Entre sus responsabilidades estarán:

- recibir eventos;
- detectar entradas nuevas;
- descargar archivos;
- registrar ingestas;
- calcular huellas;
- detectar duplicados;
- enviar contenido a modelos de IA;
- validar resultados;
- consultar y actualizar Supabase;
- gestionar clarificaciones;
- ejecutar y verificar recordatorios;
- enviar mensajes de Telegram;
- gestionar reportes y documentos;
- sincronizar configuraciones permitidas del bot;
- exponer workflows/herramientas MCP seleccionadas.

Los modelos de IA no serán responsables de mantener por sí solos el estado real del sistema.

---

## 36. Supabase

Supabase será la fuente de verdad para la memoria estructurada y el estado operativo.

Almacenará, entre otros conceptos:

- usuarios y configuración;
- identidad vigente de la secretaria;
- historial de nombres;
- ingestas;
- memoria;
- fuentes;
- textos y transcripciones;
- fragmentos;
- interpretaciones;
- entidades;
- hechos;
- tareas;
- prioridades;
- recordatorios;
- entregas de notificaciones;
- clarificaciones;
- relaciones;
- embeddings;
- reportes;
- auditoría.

El modelo técnico detallado se definirá en `04_DATABASE_SCHEMA.md` y deberá respetar el modelo `DATABASE_SCHEMA_V1` aprobado.

---

## 37. Inteligencia artificial

El sistema podrá utilizar múltiples proveedores y modelos, inicialmente OpenAI y Gemini.

No se deberá utilizar necesariamente el modelo más costoso para todas las operaciones.

La arquitectura permitirá seleccionar modelos diferentes según la tarea:

- transcripción;
- interpretación textual;
- visión/diagramas;
- extracción estructurada;
- embeddings;
- razonamiento complejo;
- tareas rutinarias de bajo costo.

Los modelos concretos deberán seleccionarse mediante pruebas y no fijarse prematuramente sin evaluación.

---

## 38. Búsqueda y memoria semántica

La recuperación de información deberá combinar, cuando sea conveniente:

- búsqueda semántica;
- búsqueda textual;
- filtros estructurados;
- relaciones explícitas entre entidades y recuerdos.

El objetivo es que el usuario pueda consultar por significado aunque no recuerde las palabras originales.

Cuando el usuario pida evidencia o texto literal, la respuesta deberá diferenciar claramente información interpretada de fragmentos originales.

---

## 39. Idempotencia y duplicados

El sistema deberá estar diseñado para reintentos seguros.

Si n8n recibe dos veces el mismo evento o reintenta un workflow después de un fallo, no deberá crear tareas, recuerdos o notificaciones duplicadas por error.

Se utilizarán identificadores de origen, claves de idempotencia, huellas de archivo y otras restricciones adecuadas.

---

## 40. Proactividad

La secretaria será proactiva por diseño.

Además de responder consultas, deberá poder detectar situaciones como:

- tarea próxima sin completar;
- vencimiento olvidado;
- compromiso importante;
- actividad que requiere preparación previa;
- tarea vencida sin estado;
- información nueva relacionada con un pendiente existente.

La proactividad deberá respetar:

- prioridad;
- contexto;
- horario de silencio;
- modo descanso;
- preferencias del usuario;
- nivel razonable de insistencia.

---

## 41. Integraciones opcionales y futuras

### 41.1 Google Calendar

No será necesario para el funcionamiento de V1.

La arquitectura deberá permitir incorporarlo posteriormente como módulo opcional activable por el usuario.

### 41.2 Gmail

Queda fuera del alcance inicial de V1 y podrá evaluarse en una versión posterior.

---

## 42. Seguridad y privacidad

El diseño deberá aplicar como mínimo:

- principio de mínimo privilegio;
- separación de credenciales;
- secretos fuera del repositorio;
- RLS en Supabase cuando corresponda;
- ausencia de borrado de memoria desde Telegram/MCP;
- registro de operaciones importantes;
- confirmación o clarificación antes de acciones ambiguas;
- separación entre originales, interpretaciones y acciones;
- aislamiento por `user_id` preparado para futuro multiusuario.

Claves de API, tokens de Telegram, claves de Supabase y secretos de Google no deberán almacenarse en GitHub.

---

## 43. Auditoría

El sistema deberá permitir reconstruir por qué existe una tarea, hecho, recordatorio, informe o respuesta.

Cuando corresponda se deberá poder seguir la cadena:

`entrada → original → transcripción/texto → interpretación IA → validación → acción → modificación posterior`

Las operaciones críticas deberán registrarse en un historial de auditoría permanente.

Los cambios de identidad de la secretaria también deberán quedar auditados.

---

## 44. Fuera de alcance inicial

Salvo decisión posterior, no forman parte de la primera implementación completa:

- Gmail;
- Google Calendar obligatorio;
- borrado remoto de memoria histórica;
- sistema público multiusuario en producción;
- selección definitiva de proveedor/modelo sin benchmark previo;
- clasificación manual obligatoria por áreas;
- Mini App de Telegram obligatoria;
- cambio dinámico del `@username` del bot;
- respuesta de voz/TTS de la secretaria como requisito obligatorio;
- recorte automático de fragmentos de audio como requisito obligatorio.

---

## 45. Criterios de éxito de V1

V1 será considerada funcionalmente exitosa cuando el usuario pueda, como mínimo:

1. enviar texto, audio y archivos por Telegram;
2. conservar el mensaje/archivo original y su trazabilidad;
3. archivar los originales en Google Drive;
4. transcribir audio;
5. comparar motores de transcripción mediante prueba A/B;
6. detectar y registrar tareas automáticamente;
7. manejar prioridad urgente/alta/normal/baja;
8. resolver fechas relativas de forma segura;
9. conservar la expresión temporal original y la fecha resuelta;
10. dejar una tarea sin hora cuando esta no sea conocida;
11. preguntar ante personas/tareas ambiguas;
12. completar una tarea por lenguaje natural;
13. registrar retrospectivamente una actividad realizada;
14. recibir recordatorios híbridos automáticos;
15. reintentar recordatorios ante fallos sin duplicarlos;
16. mantener seguimiento sobre tareas no resueltas;
17. configurar un horario de silencio recurrente;
18. activar/desactivar modo descanso temporal por conversación;
19. volver automáticamente al comportamiento habitual al terminar el descanso;
20. recibir resumen de buenos días a una hora configurable;
21. recibir cierre diario a una hora configurable;
22. consultar memoria por lenguaje natural;
23. consultar por día, semana, mes o rango personalizado;
24. recuperar fragmentos originales y audios relacionados;
25. recibir el audio original nuevamente dentro de Telegram;
26. obtener reportes escritos en Telegram sobre tareas u otra información;
27. generar PDF o Excel únicamente cuando se solicite;
28. relacionar los documentos generados con la consulta y fuentes originales;
29. procesar archivos ingresados por Google Drive;
30. interpretar imágenes y diagramas definidos para V1;
31. almacenar páginas web con contexto histórico suficiente;
32. operar funciones seleccionadas desde ChatGPT mediante MCP;
33. guardar las acciones de ChatGPT/MCP en la misma memoria central;
34. asignar un nombre a la secretaria durante el onboarding;
35. cambiar posteriormente ese nombre por lenguaje natural o configuración;
36. reflejar el nombre elegido en el nombre visible del bot personal de Telegram;
37. acceder a Configuración desde la zona inferior del chat mediante el menú de comandos de Telegram en V1;
38. conservar historial de nombres;
39. preservar la memoria histórica y el historial de cambios;
40. detectar duplicados y soportar reintentos sin crear registros repetidos.

---

## 46. Próximo documento

Una vez que esta versión sea revisada y aprobada por el usuario, deberá marcarse como:

**`PRD V1 — APPROVED / FROZEN`**

El siguiente documento será:

`docs/02_SRS.md`

El SRS convertirá cada comportamiento aprobado en requisitos numerados, verificables y trazables para implementación y pruebas por Antigravity.
