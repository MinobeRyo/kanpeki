import { spawn } from 'node:child_process';
import { mkdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname, join } from 'node:path';
const base=dirname(fileURLToPath(import.meta.url));
const directory=resolve(process.env.KANPEKI_MCP_DIR||join(base,'../../.build/mcp-session'));
const binary=process.env.KANPEKI_TUNNEL_BIN, key=process.env.KANPEKI_RUNTIME_KEY_FILE, tunnel=process.env.KANPEKI_TUNNEL_ID;
if(!binary||!key||!tunnel||!existsSync(binary)||!existsSync(key)) throw Error('Set KANPEKI_TUNNEL_BIN, KANPEKI_RUNTIME_KEY_FILE and KANPEKI_TUNNEL_ID. Never paste the key value into command arguments.');
mkdirSync(directory,{recursive:true,mode:0o700});
const runtime=join(base,'.runtime');mkdirSync(runtime,{recursive:true,mode:0o700});
const server=spawn(process.execPath,[join(base,'server.mjs')],{cwd:base,env:{...process.env,KANPEKI_MCP_DIR:directory},stdio:'inherit'});
let client, stopping=false, serverExited=false;
function stop(code=0){if(stopping)return;stopping=true;process.exitCode=code;server.kill('SIGTERM');client?.kill('SIGTERM');}
server.on('error',()=>stop(1));server.on('exit',code=>{serverExited=true;if(!stopping)stop(code||1);});
process.on('SIGINT',()=>stop());process.on('SIGTERM',()=>stop());
// SDK imports can take longer on a busy Mac. Start the tunnel only after health succeeds.
const deadline=Date.now()+60000;
let ready=false;
while(!stopping && Date.now()<deadline) {
 try {const response=await fetch('http://127.0.0.1:43133/healthz',{signal:AbortSignal.timeout(1000)});const health=await response.json();if(response.ok&&health.server==='kanpeki-mcp'){ready=true;break;}} catch {}
 await new Promise(resolve=>setTimeout(resolve,250));
}
if(!ready||serverExited||stopping) {stop(1);throw Error('Local MCP did not become ready within 60 seconds');}
client=spawn(binary,['run','--profile-dir',join(runtime,'profiles'),'--control-plane.tunnel-id',tunnel,'--control-plane.api-key',`file:${resolve(key)}`,'--mcp.server-url','url=http://127.0.0.1:43133/mcp','--mcp.startup-wait-timeout','10s','--health.listen-addr','127.0.0.1:0','--health.url-file',join(runtime,'health-url'),'--log.file',join(runtime,'tunnel.log')],{cwd:base,stdio:'inherit'});
client.on('error',()=>stop(1));client.on('exit',code=>{if(!stopping)stop(code||1);});
console.log(`Select this exchange folder in both native apps: ${directory}`);
