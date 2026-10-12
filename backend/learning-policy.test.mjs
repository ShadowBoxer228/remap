import {test} from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {learningInstructions,SOCRATIC_POLICY,parseSourceReply,verifiedReferences,sourceMessage,CITE_SOURCES_TOOL} from './learning-policy.mjs';
import {prepareNative,nativeRoutes} from './native.mjs';
import {infer} from './coach.mjs';
const id='11111111-1111-4111-8111-111111111111';
const pages=[{page:7,text:'The model predicts\n the NEXT token using the previous tokens.'}];
const input={contractVersion:5,sourceId:'training-llm',message:'What is next-token prediction?',session:{step:0,messages:[]},board:{revision:id,title:'LLM',nodes:[],edges:[]},sourcePages:pages};
test('typed and voice receive the identical first-ask/repeated-ask policy',()=>{
 for(const voice of [false,true])assert.ok(learningInstructions({voice,citationTool:true}).startsWith(SOCRATIC_POLICY));
 assert.match(learningInstructions({voice:true,citationTool:true}),/cite_sources/);
 assert.doesNotMatch(learningInstructions({voice:true}),/call cite_sources/);
 assert.match(SOCRATIC_POLICY,/FIRST conceptual/);assert.match(SOCRATIC_POLICY,/SAME topic/);
});
test('citations require actual page and exact quote, with only whitespace/case normalization',()=>{
 const citations=[{page:7,quote:'predicts the next token'},{page:8,quote:'predicts the next token'},{page:7,quote:'invented'}];
 assert.deepEqual(verifiedReferences(citations,pages),[{page:7,reason:'predicts the next token',quote:'predicts the next token'}]);
 for(const citation of [{page:99,quote:'The model'},{page:7,quote:'invented answer'},{page:7,quote:'x'.repeat(241)},{page:7,quote:' '}]) assert.deepEqual(verifiedReferences([citation],pages),[]);
 assert.equal(sourceMessage('Read [p.7] and [p.99].',[{page:7}]),'Read [p.7] and .');
 assert.throws(()=>parseSourceReply(JSON.stringify({message:'Answer',command:null})));
});
test('native model receives source schema and parses citations through real inference adapter',async()=>{
 const prepared=prepareNative(input).payload;
 class Socket extends EventEmitter {
  constructor(){super();queueMicrotask(()=>this.emit('open'));}
  send(value){const e=JSON.parse(value);
   if(e.type==='session.update'){assert.ok(e.session.tools[0].parameters.required.includes('citations'));assert.match(e.session.instructions,/FIRST conceptual/);queueMicrotask(()=>this.emit('message',JSON.stringify({type:'session.updated'})));}
   if(e.type==='response.create')queueMicrotask(()=>this.emit('message',JSON.stringify({type:'response.done',response:{status:'completed',output:[{type:'function_call',name:'respond_to_student',arguments:JSON.stringify({message:'Read the heading on [p.7]. What comes next?',command:null,review_answer:null,citations:[{page:7,quote:'NEXT token'}]})}]}})));
  }
  close(){}
 }
 const reply=await infer({operation:'conversation'},'test',Socket,prepared);
 assert.equal(reply.citations[0].page,7);assert.equal(reply.command,null);
});
test('voice citation capability is additive and absent from build4 sessions',async()=>{
 for(const version of [undefined,5]){
  let tools;
  const app=nativeRoutes({key:'test',reserve:async()=>true,tokenFn:async(_,__,___,session)=>{tools=session.tools;return {value:'ek_test'};}});
  const response=await app.request('/realtime/token',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...input,contractVersion:version})});
  assert.equal(response.status,200);assert.equal(tools.some(t=>t.name===CITE_SOURCES_TOOL.name),version===5);
 }
});
