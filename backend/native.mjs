import {prepareHeadlines} from './headlines.mjs';
import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { infer, voiceSession, issueVoiceToken, MODEL } from './coach.mjs';
import { safeConversation, parseConversation, CONVERSATION_INSTRUCTIONS, MAP_TOOL, REVIEW_TOOL } from './conversation.mjs';

import {learningInstructions,SOURCE_REPLY_TOOL,CITE_SOURCES_TOOL,parseSourceReply,verifiedReferences,sourceMessage} from './learning-policy.mjs';

export function prepareNative(input) {
  if (!input || typeof input.sourceId !== 'string' || !/^(training-llm|pdf-[a-f0-9]{64})$/.test(input.sourceId)) throw Error('invalid_source');
  const history = (Array.isArray(input.session?.messages) ? input.session.messages : []).slice(-10).map(m=>({role:m.role,text:typeof m.text==='string'?m.text.slice(0,1000):''}));
  const conversation = safeConversation({message:input.message,history,map:input.board,review:input.review});
  if (!Array.isArray(input.sourcePages) || input.sourcePages.length>4) throw Error('invalid_source_pages');
  const pages = input.sourcePages.map(p=>{
    if (!Number.isInteger(p?.page)||p.page<1||p.page>30||typeof p.text!=='string'||p.text.length>5000) throw Error('invalid_page');
    return {page:p.page,text:p.text};
  });
  if (!pages.some(p=>p.text.trim())) throw Error('source_needs_preparation');
  const sourceImages = input.sourceImages ?? [];
  if (!Array.isArray(sourceImages) || sourceImages.length > 1 || sourceImages.some(i => !pages.some(p => p.page === i?.page) || typeof i?.dataURL !== 'string' || i.dataURL.length > 480023 || !/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(i.dataURL))) throw Error('invalid_source_image');
  const topics = (Array.isArray(input.session?.topics)?input.session.topics:[]).slice(0,40).map(t=>({id:String(t?.id??'').slice(0,40),label:String(t?.label??'').slice(0,160),page:Number.isInteger(t?.page)?t.page:null}));
  const knownTopics = new Set(topics.map(t=>t.id));
  const roles = Object.fromEntries(Object.entries(input.session?.roles ?? {}).filter(([id,role])=>knownTopics.has(id)&&typeof role==='string').slice(0,40).map(([id,role])=>[id,role.slice(0,40)]));
  const groups = (Array.isArray(input.session?.groups)?input.session.groups:[]).slice(0,10).map(g=>({label:String(g?.label??'').slice(0,100),topicIds:(Array.isArray(g?.topicIds)?g.topicIds:[]).filter(id=>knownTopics.has(id)).slice(0,40)}));
  const state = {step:[0,1,2].includes(input.session?.step)?input.session.step:0,topics,roles,groups};
  const image = input.snapshot == null ? null : input.snapshot;
  if (image!==null && (typeof image!=='string'||image.length>1200000||!/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(image))) throw Error('invalid_snapshot');
  return {conversation,pages,payload:{model:MODEL,instructions:CONVERSATION_INSTRUCTIONS+'\n'+learningInstructions(),
    prompt:JSON.stringify({...conversation,sourceId:input.sourceId,sourcePages:pages,learningState:state}),max_output_tokens:900,image,sourceImages,tools:[SOURCE_REPLY_TOOL],parseOutput:parseSourceReply}};
}

export function validateNativeCommand(input) {
  const {conversation}=prepareNative(input);
  const command=parseConversation(JSON.stringify({message:'Command validation',command:input.command})).command;
  if (!command || command.request.trim()!==conversation.message.trim() || command.revision.toLowerCase()!==conversation.map.revision.toLowerCase() || conversation.map.truncated) throw Error('stale_command');
  if (!command.operations.every(op=>op.kind==='highlight') && !/\b(add|create|connect|link|rename|delete|remove|move|tidy|undo|group|mark|highlight|change|draw|set|arrange|rearrange)\b|добав|созда|соедин|свяж|переимен|удал|перемест|отмен|сгрупп|выдел|нарис|ekle|sil|bağla|değiştir|taşı|geri al/i.test(command.request)) throw Error('explicit_request_required');
  const nodes=new Map(conversation.map.nodes.map(n=>[n.id.toLowerCase(),n]));
  const edges=new Map(conversation.map.edges.map(e=>[e.id.toLowerCase(),{from:e.from.toLowerCase(),to:e.to.toLowerCase()}]));
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  for (const op of command.operations) {
    for (const field of ['x','y']) if(op[field]!=null && (!Number.isFinite(op[field])||Math.abs(op[field])>100000)) throw Error('invalid_coordinate');
    if(op.label!=null && (typeof op.label!=='string'||op.label.length>200)) throw Error('invalid_label');
    if(op.reason!=null && (typeof op.reason!=='string'||op.reason.length>1200)) throw Error('invalid_reason');
    if(['rename_node','delete_node','set_backbone','move_node'].includes(op.kind) && !nodes.has(String(op.id).toLowerCase())) throw Error('unknown_node');
    if(['delete_edge','set_reason','set_direction'].includes(op.kind) && !edges.has(String(op.id).toLowerCase())) throw Error('unknown_edge');
    if(op.kind==='connect' && (!nodes.has(String(op.from).toLowerCase())||!nodes.has(String(op.to).toLowerCase())||op.from===op.to)) throw Error('unknown_endpoint');
    if(['group_nodes','highlight'].includes(op.kind) && (!Array.isArray(op.ids)||op.ids.length>20||op.ids.some(id=>!nodes.has(String(id).toLowerCase())&&!edges.has(String(id).toLowerCase())))) throw Error('unknown_selection');
    if(nodes.get(String(op.id).toLowerCase())?.backbone && ['rename_node','delete_node'].includes(op.kind)) throw Error('protected_backbone');
    if(nodes.get(String(op.id).toLowerCase())?.backbone && op.kind==='set_backbone' && op.backbone===false) throw Error('protected_backbone');
    if(op.kind==='undo' && (command.operations.length!==1||!conversation.map.canUndo)) throw Error('invalid_undo');
    // Match the native atomic candidate: later operations may target objects created above.
    if(op.kind==='add_node') {
      if(typeof op.label!=='string'||!op.label.trim())throw Error('invalid_label');
      if(op.id!=null) {if(!uuid.test(op.id)||nodes.has(op.id.toLowerCase()))throw Error('duplicate_node');nodes.set(op.id.toLowerCase(),{backbone:!!op.backbone});}
    }
    if(op.kind==='delete_node') {const id=op.id.toLowerCase();nodes.delete(id);for(const [edgeID,e] of edges)if(e.from===id||e.to===id)edges.delete(edgeID);}
    if(op.kind==='connect'&&op.id!=null) {
      const from=op.from.toLowerCase(),to=op.to.toLowerCase();
      const existing=[...edges.values()].some(e=>(e.from===from&&e.to===to)||(e.from===to&&e.to===from));
      if(!existing){if(!uuid.test(op.id)||edges.has(op.id.toLowerCase()))throw Error('duplicate_edge');edges.set(op.id.toLowerCase(),{from,to});}
    }
    if(op.kind==='delete_edge')edges.delete(op.id.toLowerCase());
    if(op.kind==='set_backbone')nodes.get(op.id.toLowerCase()).backbone=!!op.backbone;
  }
  return command;
}

export function nativeRoutes({key,reserve,inferFn=infer,tokenFn=issueVoiceToken}) {
  const app=new Hono();
  app.use('*',bodyLimit({maxSize:1500000,onError:c=>c.json({error:'The map request is too large. Try a smaller view.'},413)}));
  app.post('/headlines',async c=>{
    let prepared;
    try {prepared=prepareHeadlines(await c.req.json());}catch{return c.json({error:'This PDF needs readable text for OpenAI to gather its topics.'},400);}
    try {
      if(!await reserve('text'))return c.json({error:'The coach is busy. Retry PDF preparation in a minute.'},429);
      let result;
      try { result=await inferFn({operation:'conversation'},key,undefined,prepared.payload); }
      catch(error) {
        // One bounded repair for malformed/unverifiable model output, never a local-topic fallback.
        if(!['invalid_conversation_output','invalid_verdict_call'].includes(error?.code))throw error;
        result=await inferFn({operation:'conversation'},key,undefined,{...prepared.payload,
          instructions:prepared.payload.instructions+' Your previous output failed validation. Return 8–12 distinct topics if supported, with very short exact copied quote anchors from the supplied page text. Check page numbers and avoid reformatting hyphens or punctuation.'});
      }
      if(result.error)return c.json({error:result.error},422);
      return c.json({headlines:result.headlines});
    }catch(error){console.warn('native_headlines_failed',/^[a-zA-Z0-9_]{1,80}$/.test(error?.code??'')?error.code:'provider_or_output_error');return c.json({error:'OpenAI could not prepare the PDF topics. Your PDF is saved; retry preparation.'},503);}
  });
  app.post('/coach',async c=>{
    let input,prepared;
    try {input=await c.req.json();prepared=prepareNative(input);} catch{return c.json({error:'Prepare this PDF in Collect before asking the coach.'},400);}
    try {
      if(!await reserve('text'))return c.json({error:'The coach is busy. Try again in a minute.'},429);
      const reply=await inferFn({operation:'conversation'},key,undefined,prepared.payload);
      if(reply.command) { try { validateNativeCommand({...input,command:reply.command}); } catch {reply.command=null;} }
      const references=verifiedReferences(reply.citations,prepared.pages);
      return c.json({message:sourceMessage(reply.message,references),references,command:reply.command??null,review_answer:reply.review_answer??null});
    } catch{return c.json({error:'The cloud coach is temporarily unavailable. Your work is saved; retry shortly.'},503);}
  });
  app.post('/realtime/token',async c=>{
    let prepared,input;
    try {input=await c.req.json();prepared=prepareNative(input);} catch{return c.json({error:'Prepare this PDF in Collect before starting voice.'},400);}
    try {
      if(!await reserve('voice'))return c.json({error:'The coach is busy. Try again in a minute.'},429);
      const session=voiceSession(true);
      session.instructions=CONVERSATION_INSTRUCTIONS+'\n'+learningInstructions({voice:true,citationTool:input.contractVersion===5})+'\nINITIAL SOURCE AND MAP DATA:\n'+prepared.payload.prompt;
      session.tools=[MAP_TOOL,{type:'function',name:'get_current_map',description:'Read the latest learner map and drawing.',parameters:{type:'object',properties:{},additionalProperties:false}},
        {type:'function',name:'lookup_source',description:'Retrieve excerpts from the PDF attached to this session.',parameters:{type:'object',properties:{query:{type:'string'},pages:{type:'array',items:{type:'integer'},maxItems:4}},required:['query','pages'],additionalProperties:false}}];
      if(input.contractVersion===5)session.tools.push(CITE_SOURCES_TOOL,REVIEW_TOOL);
      return c.json(await tokenFn(key,fetch,true,session));
    }catch{return c.json({error:'Voice could not connect. Retry shortly.'},503);}
  });
  app.post('/command',async c=>{try{validateNativeCommand(await c.req.json());return c.json({ok:true});}catch{return c.json({error:'This command is stale or not allowed. Your map was not changed.'},400);}});
  app.post('/realtime/stop',c=>c.json({ok:true}));
  return app;
}
