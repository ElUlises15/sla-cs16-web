# Hostear SLA CS 1.6 desde tu PC Windows

Tu PC puede ser el servidor público. No necesitás un VPS si tenés **IPv4 pública**, el
ISP permite conexiones entrantes y podés configurar tu router. La PC debe permanecer
encendida, conectada y sin suspensión. La subida de tu conexión limita jugadores y ping.

## 1. Requisitos

- Windows 11, preferentemente Intel/AMD x64; PowerShell 5.1 incluido o PowerShell 7.
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) actualizado, usando
  **Linux containers**. Compose mínimo 2.24.4. El script detecta y abre Docker Desktop.
- Virtualización habilitada. Docker Desktop puede pedir habilitar WSL2 y reiniciar
  durante su instalación; **no necesitás instalar Ubuntu ni ejecutar scripts en WSL**.
  Consultá [los requisitos de Docker para Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
- [Git para Windows](https://git-scm.com/downloads/win), unos 4 GB libres para archivos
  y espacio adicional para imágenes/cache; asigná al menos 4 GB de RAM a Docker.
- Acceso a configurar router y, opcionalmente, DNS del dominio.

No se instalan programas, se modifica el router ni se cambia la IP de Windows sin
tu intervención. Docker Desktop debe instalarse/aceptarse una vez; el resto del
bootstrap usa sus contenedores existentes, incluyendo SteamCMD y Studio.

## 2. Primera instalación

Instalá Docker Desktop, abrilo una vez y esperá que el motor esté listo. Cloná en un
directorio local (preferible fuera de OneDrive):

```powershell
git clone https://github.com/ElUlises15/sla-cs16-web.git
cd sla-cs16-web
.\host-publico.ps1
```

Si Windows bloquea scripts, para **esta sesión**:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\host-publico.ps1
```

El script comprueba Docker/Compose, IPv4 LAN/gateway/MAC/DHCP, IP pública por HTTP,
puertos locales y puertos publicados por Compose. Genera `.env`, claves aleatorias,
`config/server.cfg` con cheats desactivados y tres salas si no tenías salas propias.
Construye imágenes, descarga archivos del juego mediante SteamCMD (con reintentos),
arma paquetes con Studio y levanta web, salas, Studio y Caddy. La primera vez puede
tardar varios minutos. Las siguientes usan cache y conservan claves/configuraciones.

Por defecto `ARCHIVOS=propios`: cada jugador carga sus archivos de CS de Steam en
su navegador. Si venías de modo local sin contraseña, cambia `servidor` a `propios`.
Un grupo privado existente con `ARCHIVOS=servidor` y `CONTRASENA` se conserva.

Si aún no configuraste el router, es esperable que HTTPS esté **pendiente**. No se
declara que la URL es accesible hasta probarla desde otra conexión.

## 3. Levantar servidor

```powershell
.\host-publico.ps1
.\estado-host.ps1
```

Sin dominio, `181.23.45.67` genera `https://181-23-45-67.sslip.io`. Con dominio:

```powershell
.\host-publico.ps1 -Dominio cs.slatv.live
```

Si hay múltiples adaptadores/VPN, elige la ruta IPv4 con menor métrica. Podés
seleccionar explícitamente una IP asignada a un adaptador con gateway:

```powershell
.\host-publico.ps1 -IPLan 192.168.1.50
```

Si el servicio HTTP de IP no responde, o usás VPN con una salida diferente, podés
indicar la IPv4 real del router (`-IPPublica 181.23.45.67`). No uses la IP LAN ni una
IP de documentación. El bridge anuncia esa IPv4 en ICE: debe ser la que llega a la PC.
Desconectá la VPN para evitar publicar una IP de salida que no admite forwarding.

`-SoloIniciar` omite builds y descarga, para arranques automáticos posteriores a una
primera instalación completa. Recalcula la IP pública y la configuración online.

## 4. Configurar router

El script muestra tus valores reales. Para una PC `192.168.1.50`, en *NAT / Port
Forwarding / Servidor virtual* agregá:

| Protocolo | Puerto externo | IP destino | Puerto interno | Uso |
|---|---:|---|---:|---|
| TCP | 80 | 192.168.1.50 | 80 | HTTP y validación de certificados |
| TCP | 443 | 192.168.1.50 | 443 | HTTPS y señalización WSS |
| UDP | 443 | 192.168.1.50 | 443 | HTTP/3 opcional |
| UDP | 27018 | 192.168.1.50 | 27018 | WebRTC del juego, todas las salas |

No cambies el puerto externo 27018: el bridge anuncia ese puerto. Desactivá la
administración WAN del router si ocupa 80/443. Si hay módem + router, reenviá en
ambos o configurá bridge con ayuda del proveedor. No uses DMZ ni expongas todos los
puertos. El script no usa UPnP ni modifica el router automáticamente.

**Reservá la IP LAN por DHCP** en el router usando MAC e IP que muestra el script.
DHCP habilitado indica que podría cambiar; el software no puede saber si ya existe
una reserva en el router. No cambia arbitrariamente la configuración IP de Windows.

Docker Desktop publica puertos mediante su backend: no reenvíes hacia la IP interna
WSL/Docker. Usá la IP LAN de Windows. [Detalle de red de Docker Desktop](https://docs.docker.com/desktop/features/networking/).

## 5. Configurar Windows Firewall

Desde PowerShell **como administrador**, en el directorio del repo:

```powershell
.\host-publico.ps1 -ConfigurarFirewall
```

Crea o actualiza sin duplicar las reglas `SLA-CS16 TCP 80`, `SLA-CS16 TCP 443`,
`SLA-CS16 UDP 443`, `SLA-CS16 UDP 27018`, grupo `SLA-CS16 Public Host`, perfiles
Domain/Private/Public, entrada permitida en esos puertos. No desactiva el firewall.
Revisá también reglas de bloqueo explícitas, antivirus/EDR y permisos del proceso
`com.docker.backend.exe`: una regla Allow no vence una regla Block de tu política.

Para retirar **solo estas cuatro reglas**, sin arrancar servicios:

```powershell
.\host-publico.ps1 -EliminarFirewall
# O detener y retirar reglas:
.\detener-host.ps1 -EliminarFirewall
```

## 6. Comprobar CGNAT

```powershell
.\diagnostico-red.ps1
# Copiá la direccion WAN/Internet IPv4 de la pantalla del router:
.\diagnostico-red.ps1 -WanRouter 100.72.10.20
```

La detección automática **no es concluyente**. Consulta IP pública con ipify (o
Amazon checkip de respaldo), reconoce RFC1918, loopback, link-local y
`100.64.0.0/10`. No lee credenciales ni accede automáticamente a la WAN del router.

- LAN `192.168.1.50`: normal, no prueba CGNAT.
- WAN entre `100.64.0.0` y `100.127.255.255`: probable CGNAT.
- WAN `10.x`, `172.16`–`172.31.x`, `192.168.x`: doble NAT o NAT del ISP.
- WAN pública igual a IP HTTP: no detectado, sin garantía de puertos entrantes.
- WAN distinta de IP HTTP: revisar VPN, doble NAT o NAT del ISP.

Con CGNAT, el forwarding normal probablemente no funcione. Opciones: solicitar
IPv4 pública al ISP, contratar IPv4 pública/fija o usar un VPS/relay que transporte
**UDP** (y adaptar el anuncio ICE/ruta). No se configura un relay automáticamente.
Cloudflare Tunnel común para HTTP **no resuelve el UDP del bridge**. Este proyecto
no tiene fallback TURN; una red de jugadores que bloquea UDP también puede fallar.

## 7. Probar desde fuera

Apagá Wi-Fi en el celular y usá datos móviles, o probá desde otra conexión. Abrí:

```text
https://181-23-45-67.sslip.io/diagnostico.html
```

Elegí sala y pulsá **Probar**. Comprueba HTTPS/listado, WSS, abre un DataChannel
WebRTC real y manda A2S_INFO por el bridge a la sala (incluye respuesta a challenge).
Un resultado exitoso confirma tráfico UDP bidireccional y respuesta CS **desde esa
red en ese momento**. No necesita archivos Valve ni envía RCON. Consume brevemente
un slot de conexión y respeta límites por IP/cupo; se desconecta tras la prueba.

Desde una **PC externa** también podés correr:

```powershell
.\host-windows\verificar-externo.ps1 -URL https://181-23-45-67.sslip.io
```

Esto verifica HTTPS y estado; para UDP abrí la página anterior. Un escáner de TCP o
`Test-NetConnection` no prueba UDP. El mux ICE puede no abrir su socket hasta la
primera conexión; ver un mapping Docker no demuestra accesibilidad externa.

Finalmente probá una partida real. Desde la LAN la URL pública puede fallar si el
router no soporta NAT loopback/hairpin; eso no significa que falle desde Internet.
La conexión desde LAN al bridge público también requiere hairpin UDP.

## 8. Usar dominio

```powershell
.\host-publico.ps1 -Dominio cs.slatv.live
```

Creá un registro **A** `cs.slatv.live` → tu IPv4 pública actual. En proveedores que
ofrecen proxy HTTP/CDN, usá **DNS only**. Eliminá AAAA incorrectos: el bridge actual
solo anuncia IPv4. Esperá la propagación y ejecutá diagnóstico nuevamente.

Caddy usa exclusivamente ese hostname en Windows; no suma un alias sslip adicional
cuando elegís dominio propio. Evita certificados innecesarios. Conserva datos ACME
en volúmenes y renueva automáticamente mientras el servidor esté conectado y DNS/
puertos sigan correctos. La verificación local usa curl con SNI hacia 127.0.0.1,
**sin ignorar certificados**, para evitar depender del hairpin TCP del router.

Con sslip.io, DNS se deriva de la IP sin cuenta. Dependés de disponibilidad/DNS de
ese tercero, filtros anti DNS rebinding y políticas/rate limits del emisor ACME.
No hay garantía de emisión: el proyecto sslip.io documenta episodios de
[rate limits de Let's Encrypt](https://github.com/cunnie/sslip.io/issues/108).
Si cambia la IP, cambia el hostname y la URL. No borres
volúmenes de Caddy ni repitas emisiones indiscriminadamente. Con dominio propio,
actualizá el A manualmente o mediante DDNS del proveedor/router (no configurado aquí).

Let's Encrypt necesita DNS correcto y acceso entrante TCP 80 o TCP 443 para los
challenges; este despliegue publica ambos. UDP 443 solo agrega HTTP/3. Caddy reintenta
la emisión después de corregir la red. [HTTPS automático de Caddy](https://caddyserver.com/docs/automatic-https).

## 9. Actualizar

```powershell
.\actualizar-host.ps1
```

Requiere árbol Git limpio, hace `git pull --ff-only`, reconstruye con cache,
regenera paquetes, levanta y comprueba web/salas/HTTPS local. Si hay cambios locales,
divergencia o falla pull, se detiene sin reset/stash ni borrar tus archivos. Hay un
breve corte de partidas al recrear salas/Studio. No actualiza Docker Desktop por vos.

Persisten `.env`, `config/salas.conf`, la plantilla, `build/`, `texturas/`, `mapas/`,
`marca/` y `metricas/` en bind mounts. Certificados/config Caddy y SteamCMD usan
volúmenes existentes; Windows agrega `cs-datos-salas` para archivos runtime de salas
(bans, logs, archivos de bots). `server.cfg` se regenera desde la plantilla; editá la
plantilla, no el generado. No uses `docker compose down -v` ni limpieza de volúmenes.
Respaldá archivos del repo generados y volúmenes antes de una migración de PC.

## 10. Detener

```powershell
.\detener-host.ps1
```

Detiene Caddy, salas, web y Studio sin eliminar contenedores/datos. Los servicios
tienen `restart: unless-stopped`: si los detenés explícitamente, no se reinician solos
al reiniciar Docker. La tarea opcional puede volver a iniciarlos al próximo login.
No detiene otras aplicaciones Docker de tu PC.

## 11. Iniciar automáticamente

Opcional, desde PowerShell como administrador tras completar la instalación:

```powershell
.\host-publico.ps1 -InstalarInicioAutomatico
# Retirar la tarea, sin levantar servicios:
.\host-publico.ps1 -EliminarInicioAutomatico
```

La tarea `SLA-CS16 Public Host` inicia **al iniciar sesión con ese usuario**, con
token interactivo sin guardar contraseña ni elevación permanente, usa `-SoloIniciar`
y reintenta ante fallos. No se ejecuta antes del login: Docker Desktop necesita
sesión de usuario. Para esta arquitectura no se promete servicio desatendido en el
arranque de Windows antes de iniciar sesión. No registra tarea SYSTEM ni cambia
la configuración de seguridad de Docker. Si movés el repo, reinstalá la tarea
(elimina la anterior primero); Task Scheduler muestra último resultado/logs de tarea.

Los contenedores ya pueden reiniciarse cuando vuelva Docker gracias a su política;
la tarea además refresca la IP anunciada. Si el ISP cambia la IP sin reinicio, ejecutá
`host-publico.ps1` otra vez y actualizá DNS. No instala un monitor DDNS periódico.

## 12. Solucionar problemas

```powershell
.\estado-host.ps1
.\diagnostico-red.ps1 -WanRouter 181.23.45.67
docker compose -f docker-compose.yml -f docker-compose.windows.yml --profile online logs --tail 80 caddy web servidor
```

| Síntoma | Qué revisar |
|---|---|
| Docker no arranca | Abrir Desktop una vez, backend Linux, WSL2/virtualización, reinicio pendiente, contexto `docker context ls`. |
| Puerto ocupado/reservado | IIS/otro proxy, otra app Docker, `Get-NetTCPConnection`, `Get-NetUDPEndpoint`, `netsh interface ipv4 show excludedportrange protocol=tcp`. No matar procesos ni borrar reservas arbitrariamente. |
| Bind mount/archivos compartidos fallan | Repo local fuera de OneDrive, permisos del usuario y acceso a unidad en Docker Desktop; revisar logs. |
| SteamCMD falla | Volver a ejecutar (4 intentos); alternativamente copiar carpetas valve/cstrike de Steam a build/juego. |
| Sala offline | Logs servidor, archivos del juego, mapa existente y RAM. El arranque falla si no responden todas las salas. |
| HTTPS pendiente/error certificado | DNS A real, sin AAAA incorrecto/proxy, forwarding TCP 80/443, firewall ISP/router, reloj Windows. Revisar logs Caddy y dejar que reintente. |
| HTTPS abre pero juego/diagnóstico UDP no | UDP 27018 mismo puerto exterior/interior, IP anunciada igual a WAN pública, firewall, CGNAT, red del jugador bloqueando UDP, sala llena/límite por IP. |
| Solo falla desde mi LAN | Falta NAT loopback del router; comparar con datos móviles. No se instala split DNS ni TURN automáticamente. |
| Cambió IP pública | Reejecutar host-publico; actualizar DNS A o compartir nueva URL sslip. |
| Firewall Allow no alcanza | Bloqueo explícito del backend Docker o antivirus/política corporativa; no desactivar todo el firewall. |

### Seguridad y arquitectura

Se mantiene Compose base; `docker-compose.windows.yml` es un override, no otra
infraestructura. Linux/macOS `start.sh`, LAN/online, Caddy original e instalador VPS
siguen usando exclusivamente el compose base. El lector compartido de `.env` acepta
también valores entre comillas generados por Windows, sin evaluar su contenido.
`.gitattributes` fuerza LF en shell
scripts/Dockerfiles para que el clone desde Windows no rompa ejecución Linux.

Web/Node comparte namespace con salas: CS escucha 127.0.0.1 dentro de Docker. El
bridge conserva límites por IP y descarte de RCON del navegador. Solo Caddy y el
bridge UDP se publican a la LAN/Internet. Studio `127.0.0.1:27080` y web administrativa
`127.0.0.1:27016` son locales. Caddy Windows bloquea estadísticas, métricas y rutas
Studio; `.env` no está en el directorio público ni montado en la web. No publica
Docker API, RCON ni puertos CS. Las estadísticas privadas se pueden abrir localmente
en `http://localhost:27016/estadisticas` con la clave de `.env` (no se imprime la clave).

### Pruebas reproducibles y alcance

```powershell
pwsh -NoProfile -File .\host-windows\tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\host-windows\tests.ps1
# Validacion adicional con binario Compose standalone, sin necesitar daemon:
pwsh -NoProfile -File .\host-windows\tests.ps1 -ComposeExe C:\ruta\docker-compose.exe
node --test host-windows/diagnostico.test.mjs
```

Las pruebas puras cubren IPv4/rangos/CGNAT/sslip, `.env`, idempotencia, argumentos,
JSON Docker y reglas con mocks. El binario real valida compose base y override,
aislamiento y mounts. La prueba JS simula señalización/challenge/timeout y cierre;
no demuestra conectividad real. Docker Desktop, emisión de certificados, arranque
de servidores y router necesitan una prueba real en la PC con Docker instalado y
una conexión externa. No se afirma que Internet/UDP funcionan sin esa prueba.
