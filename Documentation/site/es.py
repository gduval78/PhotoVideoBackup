UI = {
    "guide_title": "PhotoVideoBackup — Guía del usuario",
    "tagline": "Copia tus fotos y vídeos en un SSD externo, una tarjeta SD o un NAS — desde tu iPhone o tu móvil Android.",
    "version_line": "Guía de PhotoVideoBackup 2.6 (iPhone, iOS 16 o posterior) y 1.0 (Android 9 o posterior)",
    "toc": "Contenido",
    "privacy_link": "Política de privacidad",
    "contact": "Soporte",
    "back": "Volver a la guía del usuario",
    "footer": "PhotoVideoBackup · Fotos y vídeos, copiados con seguridad",
    "chooser_tagline": "Copia tus fotos y vídeos con seguridad",
    "chooser_privacy": "Política de privacidad",
}

GUIDE = [
    ("what", "¿Qué es PhotoVideoBackup?", [
        ("p", "PhotoVideoBackup copia tus fotos y vídeos desde el móvil — o desde una tarjeta de memoria de cámara — a un SSD portátil, una unidad USB o un <b>NAS</b>. Tus archivos nunca pasan por un servicio en línea: la aplicación no tiene servidor ni cuenta."),
        ("ul", ["El almacenamiento del móvil está lleno y quieres liberar espacio con seguridad.", "Vuelves de un viaje con una tarjeta SD llena de material (DJI, GoPro, Insta360, Blackmagic…) y quieres ponerlo a salvo de inmediato.", "Quieres una copia personal que no dependa de iCloud ni de Google Fotos."]),
        ("p", "<b>¿Qué la hace fiable?</b> Cada archivo copiado se vuelve a leer y se comprueba con una huella matemática (SHA-256). Si un solo byte es incorrecto, la aplicación te avisa: nunca tendrás una copia dañada sin saberlo."),
        ("p", "La aplicación solo <b>copia</b>. Nunca mueve ni borra nada del origen, salvo que lo pidas expresamente después de una copia (véase «Historial e informes»)."),
    ]),
    ("pro", "Gratis y Pro", [
        ("p", "PhotoVideoBackup se descarga gratis. Una compra <b>Pro</b> — pago único, <b>sin suscripción</b> — desbloquea las funciones avanzadas:"),
        ("table", ["Función", "Gratis", "Pro"], [
            ["Copiar la biblioteca de fotos a una unidad o carpeta", "✓", "✓"],
            ["Explorar y previsualizar las copias (con vista previa de LUT)", "✓", "✓"],
            ["Copiar tarjetas de cámara y unidades USB (SD, DJI, GoPro, Insta360…)", "—", "✓"],
            ["Réplica en una segunda unidad", "—", "✓"],
            ["Copiar a un NAS por Wi-Fi", "—", "✓"],
            ["Gradar vídeos LOG con una LUT (exportación H.265)", "—", "✓"],
        ]),
        ("fig", "paywall", "La pantalla de actualización. Ábrela cuando quieras desde la pestaña Ajustes."),
    ]),
    ("need", "Lo que necesitas", [
        ("table", ["", "iPhone / iPad", "Android"], [
            ["El dispositivo", "Un iPhone con puerto USB-C (iPhone 15 o posterior), iOS 16 o posterior", "Un móvil o tableta Android, Android 9 o posterior"],
            ["Una unidad", "Cualquier SSD USB-C (Samsung T7, SanDisk Extreme, WD My Passport…)", "Cualquier SSD o memoria USB-C, o una carpeta del móvil"],
            ["Un hub o lector (opcional)", "Un pequeño hub USB-C para conectar a la vez un SSD y un lector de tarjetas", "Un lector de tarjetas USB-C o un hub OTG"],
        ]),
        ("note", "Copiar mucho vídeo consume batería. Conecta el móvil al cargador o empieza con buena carga."),
    ]),
    ("start", "Primer inicio y permisos", [
        ("p", "Una pantalla de bienvenida presenta la aplicación y cinco montajes típicos — desde el sencillo móvil → SSD hasta un NAS al que se llega por VPN. Toca <b>Comenzar</b>."),
        ("fig", "onboarding_simple", "El montaje más sencillo: móvil → SSD."),
        ("ul", ["<b>iPhone / iPad</b>: permite el <b>acceso completo</b> a tu biblioteca de fotos. Sin él, la aplicación no puede leer tus fotos.", "<b>Android</b>: permite el acceso a tus fotos y vídeos. Permite también el acceso a la <b>ubicación de tus fotos</b> — sin ello, Android elimina los datos GPS de los archivos que entrega y la copia no sería el original. Permite las notificaciones para que te avisen al terminar una copia."]),
        ("note", "La aplicación solo lee tus fotos para copiarlas. No las modifica, no las comparte y no las envía a ninguna parte."),
    ]),
    ("setup", "Define el nombre del dispositivo y el destino", [
        ("ol", ["Abre la pestaña <b>Ajustes</b>. En la sección <b>Dispositivo</b>, escribe un <b>nombre de carpeta</b> — por ejemplo <i>iPhone de Ana</i> o <i>Pixel 8</i>. Será el nombre de la carpeta en la unidad, de modo que dos móviles que copian en la misma unidad quedan separados. Una copia no empieza hasta que haya un nombre.", "Conecta tu unidad.", "En <b>Destinos</b>, toca <b>Elegir…</b> y selecciona la unidad, o una carpeta de ella, en el explorador de archivos del sistema. En Android también puedes elegir una carpeta del almacenamiento del móvil.", "El nombre de la unidad aparece en Ajustes y en la pestaña Copia, con su espacio libre. Solo lo haces una vez: la aplicación reconoce la unidad la próxima vez."]),
        ("fig", "settings_configured", "Ajustes: nombre del dispositivo y primer destino."),
        ("note", "Un destino también puede ser una carpeta de <b>iCloud Drive</b> (iPhone) — la aplicación libera la copia local cuando iCloud confirma la subida, para que el móvil no se llene."),
    ]),
    ("photos", "Copia tus fotos y vídeos", [
        ("p", "Abre la pestaña <b>Copia</b>. Arriba ves tus destinos con su espacio libre. En <b>Fuentes</b>, la fila <b>Biblioteca de Fotos</b> muestra el nombre de tu dispositivo. Toca su botón <b>Copia</b>."),
        ("fig", "dashboard_ready", "La pestaña Copia: destino conectado, biblioteca de fotos lista."),
        ("p", "La aplicación analiza la biblioteca y después copia. La <b>primera copia es la más larga</b>; las siguientes solo copian lo nuevo y son mucho más rápidas."),
        ("ul", ["Las fotos guardadas solo en iCloud / Google Fotos se descargan primero — hace falta conexión y algo de tiempo.", "La aplicación copia cada archivo directamente al destino, así que funciona incluso con el móvil casi lleno.", "Puedes salir de la aplicación: una notificación te avisa cuando termina la copia."]),
    ]),
    ("sd", "Copia una tarjeta de cámara (Pro)", [
        ("ol", ["Conecta el lector de tarjetas al móvil e inserta la tarjeta (usa un hub si el SSD debe seguir conectado).", "En la pestaña Copia, toca <b>Agregar fuente (tarjeta SD, USB…)</b>, localiza la tarjeta en el explorador de archivos y confirma.", "Ponle un nombre a la fuente — <i>Blackmagic</i>, <i>Viaje a Japón</i>… El tipo de dispositivo se reconoce solo.", "Toca <b>Copia</b> en la fila de la fuente."]),
        ("table", ["Dispositivo reconocido", "Qué se copia"], [
            ["DJI Mini 3 Pro", "Fotos, vídeos, DNG y la telemetría (.srt)"],
            ["DJI 360 / Action (Neo 2…)", "Vídeos, fotos, DNG, audio y la telemetría (.srt)"],
            ["Insta360 (X5…)", "Archivos .insv, .insp y .lrv"],
            ["GoPro HERO", "Vídeos y fotos; se omiten los archivos proxy (.lrv) y de miniaturas (.thm)"],
            ["Cualquier otro", "Formatos habituales de foto, vídeo y RAW"],
        ]),
        ("note", "Una tarjeta expulsada y vuelta a insertar necesita un toque en <b>Reconectar</b>: el sistema da a la aplicación un acceso nuevo cada vez que se monta la tarjeta. El nombre y el tipo de la fuente se conservan."),
        ("p", "Para quitar una fuente de la lista, usa el <b>–</b> rojo (iPhone) o el botón de quitar de la fila (Android). No se borra ningún archivo."),
    ]),
    ("progress", "Mientras se copia", [
        ("p", "Aparece un panel <b>Copia en progreso</b> en cuanto tocas Copia. Primero <b>Preparando…</b> (conexión con tus destinos) y luego <b>Analizando el origen…</b> con un contador en vivo de archivos encontrados — en una biblioteca grande puede tardar un poco, no está bloqueado."),
        ("fig", "progress_backup", "Copia en progreso: porcentaje, archivos hechos, tiempo restante, archivo actual."),
        ("table", ["Fase", "Qué hace la aplicación"], [
            ["Análisis", "Cuenta los archivos y comprueba cuáles hay que copiar."],
            ["Copia", "Escribe el archivo en el destino."],
            ["Verificación", "Vuelve a leer la copia y la compara con el original."],
            ["Omitidos", "El archivo ya está copiado — nada que hacer."],
        ]),
        ("note", "No desconectes la unidad ni la tarjeta mientras se copia. Si una unidad desaparece pese a todo, los demás destinos continúan y la sesión se marca como <b>Parcial</b>."),
        ("p", "Un botón <b>Detener</b> termina la copia limpiamente en cualquier momento. Ajustes → Copia también tiene un límite <b>Máx. archivos por sesión</b>: déjalo vacío para ilimitado."),
    ]),
    ("done", "Cuando termina la copia", [
        ("fig", "completion_banner", "El aviso final: copiados, omitidos, fallidos, tamaño y duración."),
        ("table", ["Cifra", "Significado"], [
            ["Copiados", "Archivos guardados por primera vez en el destino."],
            ["Omitidos", "Archivos que ya estaban — normal y sin riesgo."],
            ["Fallidos", "Archivos que no se pudieron copiar (raro)."],
        ]),
        ("p", "Un fallo proviene de una tarjeta dañada, una unidad llena, una conexión cortada o un único archivo demasiado grande para el espacio libre — solo ese archivo se señala y el resto continúa. Libera espacio o reconecta y vuelve a lanzar la copia: se recuperan los que faltan."),
    ]),
    ("history", "Historial e informes", [
        ("p", "La pestaña <b>Historial</b> lista cada copia: origen, destinos, estructura de carpetas, número de archivos y un color — verde si todo fue bien, naranja para <b>Parcial</b>, rojo si hubo fallos."),
        ("fig", "history_list", "Historial: una sesión terminada."),
        ("p", "<b>Parcial</b> significa que la copia se detuvo antes de terminar, por una de tres razones que el informe indica: tocaste <b>Detener</b>, se alcanzó el <b>límite de archivos</b> o un <b>destino se desconectó</b>. Reconecta la unidad y vuelve a lanzar — continúa donde se quedó."),
        ("p", "Toca una sesión para ver su informe: resumen, estado SHA-256 y listas de archivos copiados, omitidos y fallidos — con el motivo de cada fallo. Con dos destinos, el informe muestra cada unidad por separado."),
        ("fig", "report_summary", "Un informe de sesión."),
        ("p", "<b>Eliminar archivos fuente…</b> libera espacio en la tarjeta o en la biblioteca cuando estás conforme con la copia. Solo ofrece los archivos copiados <i>y</i> verificados, y para confirmar debes escribir un código de cuatro cifras. Tu copia no se toca. En iPhone y Android, el sistema pide una confirmación más para las fotos."),
        ("fig", "report_delete_confirm", "Escribir el código confirma el borrado."),
        ("note", "<b>Borrar historial</b> solo elimina los registros dentro de la aplicación. Tus archivos siguen donde están."),
    ]),
    ("browse", "Explora, mira y comparte tus copias", [
        ("p", "La pestaña <b>Explorar</b> muestra, dentro de la aplicación, lo que hay en tus unidades: una carpeta por dispositivo, luego tus carpetas por fecha y después una cuadrícula de miniaturas. Toca una foto para abrirla a pantalla completa — desliza para cambiar de archivo, pellizca para ampliar — o toca un vídeo para reproducirlo. La unidad debe estar conectada."),
        ("fig", "browse_device_folders", "Explorar: las carpetas de dispositivo de una unidad."),
        ("fig", "browse_media_grid", "La cuadrícula de medios de un día."),
        ("p", "Para enviar archivos a otro sitio: toca <b>Seleccionar</b>, marca los archivos y luego <b>Compartir</b> — AirDrop, mensajes, correo, otra aplicación."),
        ("fig", "android_viewer", "Android: el visor a pantalla completa."),
        ("p", "En un NAS, Explorar lista los archivos y descarga cada uno solo cuando lo abres."),
    ]),
    ("naming", "Carpetas y nombres de archivo", [
        ("p", "En <b>Ajustes → Copia</b>, <b>Estructura de carpetas</b> define cómo se organiza una carpeta de dispositivo: <i>Flat</i> (plana), <i>By month</i> (por mes), <i>By date</i> (por fecha, predeterminada) o <i>By year / month</i> (año / mes). La pestaña Explorar se adapta a lo que haya en la unidad."),
        ("p", "<b>Nombre de archivos</b> da a cada archivo su nombre definitivo <b>en el momento de su primera copia</b> — nunca se guarda con el nombre de la cámara para renombrarlo después. Activa <b>Renombrar archivos durante la copia</b> y edita el patrón: toca un símbolo para insertarlo, todo lo demás es texto literal. Una línea <b>Ejemplo</b> muestra el resultado."),
        ("fig", "settings_file_naming", "Nombre de archivos: patrón, símbolos y ejemplo en vivo."),
        ("table", ["Símbolo", "Se sustituye por"], [
            ["{YYYY} {MM} {DD}", "Año, mes y día de la captura"],
            ["{hh} {mm} {ss}", "Hora, minuto y segundo de la captura (hora local)"],
            ["{device}", "El nombre de la carpeta del dispositivo, sin espacios"],
            ["{original}", "El nombre original del archivo, sin su extensión"],
        ]),
        ("ul", ["<b>Nunca se sobrescribe nada.</b> Si el nombre lo usa un archivo distinto, el nuevo recibe un sufijo <code>-1</code>, <code>-2</code>… Incluye los segundos en el patrón para que dos tomas simultáneas conserven nombres distintos.", "<b>Los duplicados se reconocen por ese nombre.</b> Un archivo ya copiado se omite — aunque lo hayas retocado después — y un archivo distinto con el mismo nombre se mantiene aparte.", "<b>Los archivos existentes no se renombran.</b> El perfil se aplica a los archivos copiados a partir de ahora. Con el perfil desactivado (predeterminado) los archivos conservan el nombre de la cámara."]),
        ("p", "También puedes añadir <b>extensiones de archivo adicionales</b> para copiarlas junto a los medios — por ejemplo registros GPS <code>gpx</code>."),
    ]),
    ("lut", "LUT Grade: dar su aspecto al material LOG (Pro)", [
        ("p", "El material grabado en <b>LOG</b> (DJI D-Log M, GoPro Protune…) se ve plano y gris hasta que se aplica una <b>LUT</b>. En Explorar, asigna una LUT a una carpeta de dispositivo para previsualizar y gradar sin salir de la aplicación."),
        ("ol", ["Abre una carpeta de dispositivo y, en <b>LUT Grade</b>, toca <b>Asignar LUT…</b> y luego <b>Importar LUT (.cube)…</b>. Sirve cualquier archivo <code>.cube</code> estándar (DaVinci Resolve, Final Cut Pro, el fabricante de tu cámara).", "Toca cualquier vídeo de esa carpeta: se reproduce con la LUT aplicada en tiempo real. Esta vista previa es <b>gratuita</b>.", "Para crear copias permanentes (Pro), toca <b>Seleccionar</b>, elige los vídeos y luego <b>Clasificar</b>. Cada uno se recodifica en <b>H.265</b> con la LUT incorporada, en una carpeta hermana llamada <b>Dispositivo (Graded)</b>."]),
        ("fig", "browse_lut_picker", "Elegir una LUT para una carpeta."),
        ("fig", "android_lut", "Android: la sección LUT Grade de una carpeta de dispositivo."),
        ("ul", ["El gradado se hace vídeo a vídeo, nunca «todo» — una carpeta suele mezclar clips LOG y normales, y una LUT LOG estropearía los normales.", "Los archivos ya gradados se omiten, así que puedes repetir sin riesgo. Cancela cuando quieras: los terminados se conservan.", "El gradado es exigente: mantén la aplicación abierta y la unidad conectada. El móvil puede calentarse.", "En un NAS, los clips se descargan, se gradan en el móvil y se suben a una carpeta <b>Dispositivo (Graded)</b> del NAS — más lento y consume datos."]),
    ]),
    ("mirror", "Dos destinos a la vez (Pro)", [
        ("p", "En Ajustes, añade un segundo destino: cada archivo se copia en los dos a la vez — dos unidades, o una unidad y un NAS. La copia no dura el doble. Si un destino falla o desaparece, <b>el otro continúa</b>, y el informe dice qué falta en cuál."),
        ("note", "Si al empezar solo está conectada una de las dos unidades, la aplicación copia igualmente en ella y marca la sesión como incompleta para la otra."),
    ]),
    ("nas", "Copia a un NAS por Wi-Fi (Pro)", [
        ("p", "En lugar de una unidad — o además de ella — puedes copiar directamente a un <b>NAS</b> (Synology, QNAP, TrueNAS, cualquier equipo que hable SMB) por la red. Sin cable, sin nube, y cada archivo se verifica con SHA-256."),
        ("ol", ["En el NAS, activa el <b>uso compartido de archivos SMB</b> y da a un usuario acceso de lectura y escritura a una carpeta compartida.", "En la aplicación: <b>Ajustes → Destinos → NAS (SMB)</b>.", "Rellena el <b>host</b> (p. ej. <code>192.168.1.20</code>), el <b>recurso compartido</b> (p. ej. <code>photo</code>), una <b>carpeta</b> opcional, y tu <b>usuario</b> y <b>contraseña</b>. La contraseña se guarda en el llavero de iOS o en el Keystore de Android.", "Toca <b>Probar conexión</b>: un mensaje confirma la conexión y cuántos elementos se han encontrado. Luego <b>Guardar</b>."]),
        ("p", "El NAS aparece ahora en la pestaña Copia con su espacio libre. Puedes copiar <b>fuera de casa</b> si el NAS es accesible — lo más sencillo y seguro es una VPN como <b>Tailscale</b>: instálala en el NAS y en el móvil, y usa la dirección <code>100.x.x.x</code> del NAS como host."),
        ("note", "Con datos móviles, un aviso naranja te advierte de que los vídeos grandes pueden consumir muchos datos; <b>Detener</b> interrumpe la copia (queda marcada como Parcial)."),
    ]),
    ("android", "Android e iPhone: en qué se diferencian", [
        ("p", "Las dos aplicaciones comparten el mismo motor: misma detección de duplicados, mismo nombrado, misma verificación SHA-256, mismo índice — una copia empezada en una es reconocida por la otra."),
        ("table", ["", "iPhone / iPad", "Android"], [
            ["Fuente de biblioteca", "Biblioteca de Fotos", "Galería (fotos y vídeos)"],
            ["Destino", "Carpeta elegida en Archivos (SSD, iCloud Drive, SMB)", "Carpeta elegida con el selector del sistema (SSD, USB, almacenamiento del móvil), NAS"],
            ["Segundo plano", "Unos 30 segundos; después la pantalla se mantiene encendida durante la copia", "Una notificación en primer plano lo mantiene en marcha, con botón Detener"],
            ["Pro", "Compra dentro de la app (App Store)", "Compra única (Google Play)"],
            ["Mac", "Funciona en Mac con chip Apple («diseñada para iPad»)", "—"],
        ]),
        ("note", "En Android, un destino dentro del almacenamiento propio del móvil se oculta de la galería (un archivo <code>.nomedia</code>) para que la copia no se vuelva a copiar."),
        ("fig", "android_backup", "Android: la pestaña Copia."),
        ("fig", "android_settings", "Android: Ajustes."),
    ]),
    ("faq", "Preguntas frecuentes", [
        ("p", "<b>¿Copiará dos veces el mismo archivo si vuelvo a lanzarla?</b> No. Cada archivo recibe un nombre en el destino y la siguiente copia lo busca con ese nombre. Si los registros de la aplicación indican que viene del mismo original, se omite — aunque lo hayas retocado después. Solo los archivos realmente distintos con el mismo nombre reciben un sufijo <code>-1</code>, <code>-2</code>…, y nunca se sobrescribe nada."),
        ("p", "<b>¿Dónde recuerda la aplicación lo que ha copiado?</b> En su propia base de datos y en un pequeño <b>archivo oculto, <code>.pvb-index.json</code>, en la raíz de cada destino</b>. Esa copia viaja con la copia de seguridad: tras reinstalar, o desde otro móvil, la aplicación la lee y no vuelve a copiar. Puedes dejarla en paz; si la borras, la aplicación la reconstruye."),
        ("p", "<b>¿Puedo copiar a un NAS y a una unidad a la vez?</b> Sí — cada destino conectado recibe la copia al mismo tiempo."),
        ("p", "<b>La conexión con mi NAS agota el tiempo de espera.</b> Normalmente el NAS no es accesible: comprueba que estás en la misma Wi-Fi (o que la VPN está activa), que el recurso compartido SMB está habilitado y que el cortafuegos del NAS permite la conexión."),
        ("p", "<b>¿Puedo usar dos móviles con la misma unidad?</b> Sí. Da a cada uno un nombre de carpeta distinto en Ajustes; cada uno crea su propia carpeta en la unidad."),
        ("p", "<b>La barra marca 3 % y parece atascada.</b> Los primeros archivos suelen ser vídeos grandes. Espera unos minutos."),
        ("p", "<b>Mi tarjeta aparece como «Documents».</b> Algunas cámaras usan una carpeta genérica. Escribe un nombre descriptivo al añadir la fuente."),
        ("p", "<b>¿Puedo copiar con el móvil casi lleno?</b> Sí. Los archivos se envían en flujo al destino, así que solo se retienen unos pocos megabytes a la vez. Solo una copia a un NAS <i>solo</i> necesita espacio para un archivo cada vez. Un archivo que de verdad no cabe se señala como fallido y el resto continúa."),
        ("p", "<b>¿Se envían mis datos a alguna parte?</b> No. Todo ocurre entre tu móvil y tu unidad o NAS. La aplicación no tiene servidor ni cuenta. El único tráfico de red va al NAS que configuras tú y a la descarga, por parte del sistema, de tus propias fotos de iCloud / Google."),
        ("p", "<b>¿Qué idiomas?</b> Inglés, francés, alemán, español, italiano, portugués, chino simplificado y ruso. La aplicación sigue el idioma del móvil; puedes forzar uno en <b>Ajustes → Idioma</b>, sin reiniciar."),
    ]),
]

PRIVACY = {
    "title": "Política de privacidad — PhotoVideoBackup",
    "updated": "Última actualización: {date}",
    "summary": "PhotoVideoBackup no recopila, almacena, transmite ni comparte ningún dato personal. No hay cuenta, ni analítica, ni publicidad, ni servidor propio.",
    "sections": [
        ("A qué accede la aplicación", [
            ("ul", ["A tus fotos y vídeos — en <b>solo lectura</b>, para copiarlos a la unidad, carpeta o NAS que elijas. En Android incluye la ubicación guardada en tus fotos, para que la copia sea idéntica al original.", "A las carpetas y tarjetas que eliges con el explorador de archivos del sistema.", "A las notificaciones, para avisarte al terminar una copia."]),
        ]),
        ("Qué sale de tu dispositivo", [
            ("ul", ["<b>Nada llega a nosotros.</b> Tus archivos solo se escriben en los destinos que eliges.", "Si configuras un NAS, la aplicación se conecta a <b>ese servidor</b>, en la dirección que escribiste, y a ningún otro sitio. La contraseña se guarda en el llavero de iOS o en el Keystore de Android.", "iOS o Android puede descargar tus propias fotos de iCloud o Google para que la aplicación las lea; lo hace el sistema, para tu cuenta.", "Las compras las gestionan Apple o Google. No recibimos ninguna información de pago."]),
        ]),
        ("Registro de diagnóstico", [
            ("p", "La aplicación guarda en tu dispositivo un pequeño registro de diagnóstico, sin contenido personal. Solo se envía si decides mandarlo por correo al soporte desde la aplicación."),
        ]),
        ("Contacto con el soporte", [
            ("p", "Si escribes al soporte, recibimos lo que envías — tu dirección y tu mensaje — y solo lo usamos para responderte."),
        ]),
    ],
}
