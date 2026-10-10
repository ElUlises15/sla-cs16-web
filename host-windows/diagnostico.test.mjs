import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../web/public/diagnostico.js', import.meta.url), 'utf8');
async function harness() {
    const elements = {
        '#resultado': { textContent: '' }, '#probar': { disabled: true },
        '#sala': { value: '1', options: [], append(option) { this.options.push(option); } },
    };
    const timers = new Map(); let timerId = 0, pc, ws;
    class PC {
        constructor(config) { this.config = config; this.candidates = []; pc = this; }
        async setRemoteDescription(description) { this.remote = description; }
        async addIceCandidate(candidate) { assert.ok(this.remote); this.candidates.push(candidate); }
        async createAnswer() { return { type: 'answer', sdp: 'answer-sdp' }; }
        async setLocalDescription(description) { this.local = description; }
        close() { this.closed = true; }
    }
    class WS {
        static OPEN = 1;
        constructor(url) { this.url = url; this.readyState = 1; this.sent = []; ws = this; }
        send(msg) { this.sent.push(JSON.parse(msg)); }
        close() { this.closed = true; }
    }
    const context = vm.createContext({
        document: { querySelector: (s) => elements[s], createElement: () => ({}) },
        fetch: async () => ({ ok: true, json: async () => ({ salas: [{ id: '1', nombre: 'Test', online: true }] }) }),
        location: { protocol: 'https:', host: 'cs.example.com' },
        RTCPeerConnection: PC, WebSocket: WS, TextEncoder, Uint8Array, ArrayBuffer,
        setTimeout(fn, ms) { timers.set(++timerId, { fn, ms }); return timerId; },
        clearTimeout(id) { timers.delete(id); },
    });
    await vm.runInContext(`(async()=>{${source}\n})()`, context);
    elements['#probar'].onclick();
    const flush = async () => { for (let i = 0; i < 15; i++) await Promise.resolve(); };
    const message = async (msg) => { ws.onmessage({ data: JSON.stringify(msg) }); await flush(); };
    return { elements, timers, pc, ws, message, log: () => elements['#resultado'].textContent };
}
test('diagnostico serializa ICE antes de oferta y usa WSS sin TURN externo', async () => {
    const h = await harness();
    assert.equal(h.ws.url, 'wss://cs.example.com/signal?sala=1');
    assert.deepEqual(Array.from(h.pc.config.iceServers), []);
    await h.message({ type: 'candidate', candidate: 'candidate:1', mid: '0' });
    assert.equal(h.pc.candidates.length, 0);
    await h.message({ type: 'offer', sdp: 'offer-sdp' });
    assert.equal(h.pc.candidates.length, 1);
    assert.deepEqual(h.ws.sent[0], { type: 'answer', sdp: 'answer-sdp' });
    h.pc.onicecandidate({ candidate: { candidate: 'local', sdpMid: '0' } });
    assert.equal(h.ws.sent[1].candidate, 'local');
});
test('diagnostico consulta A2S_INFO y responde challenge sin afirmar exito prematuro', async () => {
    const h = await harness();
    const sent = [];
    const channel = { readyState: 'open', send: (data) => sent.push(Buffer.from(data)) };
    h.pc.ondatachannel({ channel }); channel.onopen();
    assert.match(h.log(), /DataChannel/);
    assert.doesNotMatch(h.log(), /sala CS respondió/);
    for (const t of h.timers.values()) if (t.ms === 200) t.fn();
    assert.equal(sent[0].subarray(4).toString(), 'TSource Engine Query\0');
    assert.deepEqual([...sent[0].subarray(0, 4)], [255,255,255,255]);
    channel.onmessage({ data: new Uint8Array([255,255,255,255,0x41,1,2,3,4]).buffer });
    assert.deepEqual([...sent[1].subarray(-4)], [1,2,3,4]);
    assert.doesNotMatch(h.log(), /sala CS respondió/);
    channel.onmessage({ data: new Uint8Array([255,255,255,255,0x49,48,0]).buffer });
    assert.match(h.log(), /sala CS respondió/);
    assert.equal(h.pc.closed, true); assert.equal(h.ws.closed, true);
    assert.equal(h.elements['#probar'].disabled, false);
});
test('diagnostico timeout explica UDP y cierra recursos', async () => {
    const h = await harness();
    for (const t of h.timers.values()) if (t.ms === 25000) t.fn();
    assert.match(h.log(), /ERROR.*UDP 27018/);
    assert.equal(h.pc.closed, true); assert.equal(h.ws.closed, true);
    assert.equal(h.elements['#probar'].disabled, false);
});
