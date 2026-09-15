// Run after the native PracticeAnalysisTests --emit-request. Uses the actual SDK/server.
import {readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import assert from 'node:assert/strict';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
const directory=resolve(process.argv[2]);
const request=JSON.parse(await readFile(join(directory,'practice-request.json'),'utf8'));
await writeFile(join(directory,'practice-lease.json'),JSON.stringify({requestID:request.requestID,updatedAt:Date.now()/1000,status:'pending'}));
const client=new Client({name:'kanpeki-native-contract',version:'1.0.0'});
try {
 await client.connect(new StdioClientTransport({command:process.execPath,args:[resolve('integrations/mcp/server.mjs'),'--stdio'],env:{...process.env,KANPEKI_MCP_DIR:directory},stderr:'pipe'}));
 const data=await client.callTool({name:'get_practice_report',arguments:{source:'analysis'}});
 assert.ok(!data.isError);assert.deepEqual(JSON.parse(data.content[0].text).facts,request.facts);
 const fact=request.facts.find(f=>f.text.includes('あの資料は予備評価です。'));assert.ok(fact);
 const item={kind:'improvement',text:'予備評価の条件を説明してください。',evidenceIDs:[fact.id]};
 if(request.schemaVersion === 2) item.coaching={targetEvidenceID:fact.id,change:'予備評価の対象と条件を一文で補足してください。',rehearsal:'この説明だけを、条件を補ってもう一度話してください。'};
 const submitted=await client.callTool({name:'submit_practice_analysis',arguments:{requestID:request.requestID,presentationID:request.presentationID,items:[item]}});
 assert.ok(!submitted.isError);assert.equal(JSON.parse(submitted.content[0].text).applied,false);
 console.log('Native request → MCP SDK → grounded result succeeded. Run native --verify-exchange next.');
} finally {await client.close();}
