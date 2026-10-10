import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('start.sh lee env Windows sin evaluar secretos ni perder formato legacy', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sla-env-bash-'));
    const common = fileURLToPath(new URL('../scripts/comun.sh', import.meta.url)).replaceAll('\\', '/');
    try {
        fs.writeFileSync(path.join(dir, '.env'), "RCON_PASSWORD=legacy\nDOMINIO='cs.slatv.live'\nCONTRASENA='hola\\' $dolar'\nOTRA=\"doble $$dolar\"\n");
        // Git for Windows sh.exe es Bash; evita el alias bash.exe de WSL sin distro.
        const shell = process.platform === 'win32' ? 'sh' : 'bash';
        const output = execFileSync(shell, ['-c', '. "$1"; printf "%s\\n" "$(env_get RCON_PASSWORD)" "$(env_get DOMINIO)" "$(env_get CONTRASENA)" "$(env_get OTRA)"', 'test', common], { cwd: dir, encoding: 'utf8' });
        assert.deepEqual(output.trim().split('\n'), ['legacy', 'cs.slatv.live', "hola' $dolar", 'doble $dolar']);
    } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
