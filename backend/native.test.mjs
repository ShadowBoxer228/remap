import {test} from 'node:test';
import assert from 'node:assert/strict';
import {gateway} from './server.mjs';
import {prepareNative,validateNativeCommand} from './native.mjs';
const id='11111111-1111-4111-8111-111111111111';
const token='t'.repeat(40);
const input={sourceId:'pdf-'+'a'.repeat(64),message:'Explain this source',session:{step:1,topics:[],messages:[]},board:{revision:id,title:'Topic',nodes:[{id,label:'Backbone',x:0,y:0,backbone:true}],edges:[]},sourcePages:[{page:2,text:'Attention weights relevant tokens.'}],snapshot:null};
const request=(app,path,body=input,auth=token)=>app.request(path,{method:'POST',headers:{Authorization:`Bearer ${auth}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
test('native shares enrollment auth and validates sources before paid inference',async()=>{
 let calls=0;
 const app=gateway({key:'test',token,reserve:async()=>{calls++;return true;},inferFn:async(_,key,socket,p)=>{assert.match(p.prompt,/Attention weights/);return {message:'Attention relates tokens [p.2] [p.99]',command:null};}});
 assert.equal((await request(app,'/api/native/coach',input,'wrong')).status,401);
 assert.equal((await request(app,'/api/native/coach',{...input,sourcePages:[]})).status,400);
 assert.equal(calls,0);
 const response=await request(app,'/api/native/coach');assert.equal(response.status,200);
 assert.deepEqual((await response.json()).references,[{page:2,reason:'Source excerpt'}]);assert.equal(calls,1);
});
test('native voice has source/map tools and no persistent secret in response',async()=>{
 const app=gateway({key:'private',token,reserve:async()=>true,tokenFn:async(key,fetcher,conversation,session)=>{
  assert.equal(key,'private');assert.equal(conversation,true);assert.match(session.instructions,/Attention weights/);
  assert.deepEqual(session.tools.map(t=>t.name),['apply_map_command','get_current_map','lookup_source']);
  return {value:'ek_test',expires_at:123,model:session.model};
 }});
 const response=await request(app,'/api/native/realtime/token');assert.equal(response.status,200);assert.equal((await response.json()).value,'ek_test');
});
test('native rejects oversized source/image and stale or protected edits',()=>{
 assert.throws(()=>prepareNative({...input,sourcePages:[{page:2,text:'x'.repeat(5001)}]}));
 assert.throws(()=>prepareNative({...input,snapshot:'https://external.invalid/image.jpg'}));
 const command={request:'Delete Backbone',revision:id,operations:[{kind:'delete_node',id}]};
 assert.throws(()=>validateNativeCommand({...input,message:command.request,command}));
 assert.throws(()=>validateNativeCommand({...input,command:{...command,operations:[{kind:'tidy'}]}}));
 assert.equal(validateNativeCommand({...input,command:{request:input.message,revision:id,operations:[{kind:'highlight',ids:[id]}]}}).operations[0].kind,'highlight');
});
