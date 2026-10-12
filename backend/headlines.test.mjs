import {test} from 'node:test';
import assert from 'node:assert/strict';
import {prepareHeadlines,parseHeadlines} from './headlines.mjs';
import {nativeRoutes} from './native.mjs';
const pages=[{page:1,text:'Pretraining learns language. Fine tuning learns instructions. Data quality matters. Neural architecture shapes computation. Evaluation measures performance. Reward modelling represents preferences.'}];
const labels=['Pretraining','Fine tuning','Data quality','Neural architecture','Evaluation','Reward modelling'];
const headlines=labels.map(label=>({label,page:1,quote:label}));
const input={sourceId:'pdf-'+'a'.repeat(64),title:'Model training',pages};
test('LLM headline extraction is bounded to 6–24 grounded distinct topics',()=>{
 assert.equal(parseHeadlines(JSON.stringify({headlines,error:null}),pages).headlines.length,6);
 for(const bad of [headlines.slice(0,5),[...headlines,headlines[0]],Array.from({length:25},(_,i)=>({...headlines[0],label:'Topic '+i})),headlines.map((t,i)=>i? t:{...t,page:2}),headlines.map((t,i)=>i?t:{...t,quote:'invented fact'})])assert.throws(()=>parseHeadlines(JSON.stringify({headlines:bad,error:null}),pages));
 assert.deepEqual(parseHeadlines('{"headlines":[],"error":"Not enough concepts"}',pages),{headlines:[],error:'Not enough concepts'});
 const p=prepareHeadlines(input);assert.equal(p.payload.functionName,'gather_headlines');assert.equal(p.payload.tools[0].name,'gather_headlines');
});
test('headline route validates evidence before quota and calls the LLM with all pages',async()=>{
 let calls=0,reserved=0;
 const app=nativeRoutes({key:'test',reserve:async()=>{reserved++;return true;},inferFn:async(_,key,Socket,prepared)=>{calls++;assert.match(prepared.prompt,/Neural architecture/);return {headlines,error:null};}});
 const post=body=>app.request('/headlines',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
 assert.equal((await post({...input,pages:[]})).status,400);assert.equal(reserved,0);
 const response=await post(input);assert.equal(response.status,200);assert.equal((await response.json()).headlines.length,6);assert.equal(calls,1);assert.equal(reserved,1);
});
test('invalid generated output gets one bounded OpenAI repair and no heuristic fallback',async()=>{
 let calls=0;
 const invalid=()=>Object.assign(new Error('invalid'),{code:'invalid_conversation_output'});
 const app=nativeRoutes({key:'test',reserve:async()=>true,inferFn:async(_,key,Socket,p)=>{if(++calls===1)throw invalid();assert.match(p.instructions,/previous output failed validation/);return {headlines,error:null};}});
 const options={method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input)};
 assert.equal((await app.request('/headlines',options)).status,200);assert.equal(calls,2);
 let rejected=0;
 const failing=nativeRoutes({key:'test',reserve:async()=>true,inferFn:async()=>{rejected++;throw invalid();}});
 assert.equal((await failing.request('/headlines',options)).status,503);assert.equal(rejected,2);
});
