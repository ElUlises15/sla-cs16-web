const salida = document.querySelector('#resultado');
const boton = document.querySelector('#probar');
const sala = document.querySelector('#sala');
const log = (s) => { salida.textContent += `${s}\n`; };
try {
    const r = await fetch('/api/salas', { cache: 'no-store' });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const estado = await r.json();
    for (const s of estado.salas) {
        const option = document.createElement('option');
        option.value = s.id; option.textContent = `${s.nombre} (${s.online ? 'online' : 'offline'})`;
        sala.append(option);
    }
    boton.disabled = sala.options.length === 0;
    log('[OK] HTTPS/web y listado de salas. Falta probar UDP.');
} catch (e) { log(`[ERROR] ${e.message}`); }

boton.onclick = () => {
    boton.disabled = true;
    salida.textContent = '';
    const pc = new RTCPeerConnection({ iceServers: [] });
    const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/signal?sala=${encodeURIComponent(sala.value)}`);
    let terminado = false, remoteSet = false;
    const pendientes = [];
    const fin = (mensaje) => {
        if (terminado) return;
        terminado = true;
        clearTimeout(timer); pc.close(); ws.close(); boton.disabled = false; log(mensaje);
    };
    const timer = setTimeout(() => fin('[ERROR] Timeout. Revisá UDP 27018, router/firewalls, CGNAT, IP anunciada o si la sala está llena. HTTPS por sí solo no prueba UDP.'), 25000);
    pc.onicecandidate = ({ candidate }) => {
        if (candidate && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'candidate', candidate: candidate.candidate, mid: candidate.sdpMid }));
    };
    pc.ondatachannel = ({ channel }) => {
        channel.binaryType = 'arraybuffer';
        channel.onopen = () => {
            log('[OK] DataChannel WebRTC abierto: hay tráfico UDP bidireccional en esta conexión.');
            // Misma consulta A2S_INFO que web/consulta.mjs.
            const query = new TextEncoder().encode('TSource Engine Query\0');
            const packet = new Uint8Array(4 + query.length); packet.fill(255, 0, 4); packet.set(query, 4);
            setTimeout(() => { if (!terminado && channel.readyState === 'open') channel.send(packet); }, 200);
        };
        channel.onmessage = ({ data }) => {
            if (!(data instanceof ArrayBuffer)) return;
            const p = new Uint8Array(data);
            if (p.length < 5 || !p.slice(0, 4).every((v) => v === 255)) return;
            if (p[4] === 0x41 && p.length >= 9) {
                const query = new TextEncoder().encode('TSource Engine Query\0');
                const packet = new Uint8Array(4 + query.length + 4);
                packet.fill(255, 0, 4); packet.set(query, 4); packet.set(p.slice(5, 9), 4 + query.length);
                channel.send(packet);
            } else if (p[4] === 0x49 || p[4] === 0x6d) {
                fin('[OK] La sala CS respondió a través del bridge. HTTPS + WebRTC/UDP + sala comprobados desde ESTA red.');
            }
        };
        channel.onclose = () => fin('[ERROR] Canal cerrado antes de recibir respuesta CS.');
    };
    // Serializar ofertas/candidatos para evitar carreras durante setRemoteDescription.
    let cola = Promise.resolve();
    ws.onmessage = ({ data }) => {
        cola = cola.then(async () => {
            if (terminado) return;
            const msg = JSON.parse(data);
            if (msg.type === 'offer') {
                await pc.setRemoteDescription({ type: 'offer', sdp: msg.sdp }); remoteSet = true;
                for (const c of pendientes.splice(0)) await pc.addIceCandidate(c);
                const answer = await pc.createAnswer(); await pc.setLocalDescription(answer);
                ws.send(JSON.stringify({ type: 'answer', sdp: answer.sdp }));
                log('[OK] Señalización WSS y oferta ICE recibidas.');
            } else if (msg.type === 'candidate') {
                const c = { candidate: msg.candidate, sdpMid: msg.mid ?? '0' };
                if (remoteSet) await pc.addIceCandidate(c); else pendientes.push(c);
            }
        }).catch((e) => fin(`[ERROR] WebRTC: ${e.message}`));
    };
    ws.onerror = () => fin('[ERROR] No pudo abrirse WSS /signal. Revisá HTTPS/Caddy.');
    ws.onclose = () => fin('[ERROR] Señalización cerrada. Revisá límite por IP, cupo de sala y logs.');
};
