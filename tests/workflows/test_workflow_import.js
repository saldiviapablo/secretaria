const fs = require('fs');
const path = require('path');

function validateWorkflows() {
  const root = path.join(__dirname, '..', '..');
  const wfDir = path.join(root, 'n8n', 'workflows');
  const manifestPath = path.join(wfDir, 'manifest.json');
  if (!fs.existsSync(manifestPath)) throw new Error('Missing n8n/workflows/manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (manifest.phase !== 'F3') throw new Error(`Expected phase F3, got ${manifest.phase}`);
  if (manifest.total_workflows_implemented !== 23) throw new Error(`Expected 23 workflows through F3, got ${manifest.total_workflows_implemented}`);

  const ids = new Set();
  for (const entry of manifest.workflows) {
    if (ids.has(entry.workflow_id)) throw new Error(`Duplicate workflow id ${entry.workflow_id}`);
    ids.add(entry.workflow_id);
    if (!['F0','F1','F2','F3'].includes(entry.phase)) throw new Error(`Out-of-scope phase: ${entry.workflow_id} -> ${entry.phase}`);
    const full = path.join(wfDir, entry.file);
    if (!fs.existsSync(full)) throw new Error(`Missing workflow file ${entry.file}`);
    const wf = JSON.parse(fs.readFileSync(full,'utf8'));
    if (!wf.name || !Array.isArray(wf.nodes) || !wf.connections) throw new Error(`Invalid workflow structure ${entry.file}`);
    if (wf.id && wf.id !== entry.workflow_id) throw new Error(`ID mismatch ${entry.file}`);
    const names = new Set(wf.nodes.map(n=>n.name));
    for (const [source, conn] of Object.entries(wf.connections)) {
      if (!names.has(source)) throw new Error(`Missing connection source ${source}`);
      for (const branch of (conn.main || [])) for (const target of (branch || [])) if (!names.has(target.node)) throw new Error(`Missing target ${target.node}`);
    }
  }

  function walk(dir) {
    let out=[];
    for (const name of fs.readdirSync(dir)) {
      const full=path.join(dir,name);
      if (fs.statSync(full).isDirectory()) out=out.concat(walk(full));
      else if(name.endsWith('.json') && name !== 'manifest.json') out.push(full);
    }
    return out;
  }
  const actual=walk(wfDir);
  if(actual.length!==23) throw new Error(`Expected exactly 23 workflow JSON files through F3, found ${actual.length}`);

  const expectedF3=['WF-ING-003','WF-ING-004','WF-ING-005','WF-AI-001','WF-ING-006','WF-AI-003'];
  const f3=manifest.workflows.filter(w=>w.phase==='F3').map(w=>w.workflow_id);
  if(JSON.stringify(f3)!==JSON.stringify(expectedF3)) throw new Error(`F3 must contain exactly ${expectedF3.join(', ')}`);

  const f2Schedules={'WF-REM-002':1,'WF-REM-003':5,'WF-REM-004':30};
  for(const [id,minutes] of Object.entries(f2Schedules)){
    const e=manifest.workflows.find(w=>w.workflow_id===id);
    const wf=JSON.parse(fs.readFileSync(path.join(wfDir,e.file),'utf8'));
    const t=wf.nodes.find(n=>n.type==='n8n-nodes-base.scheduleTrigger');
    if(!t || t.parameters?.rule?.interval?.[0]?.minutesInterval!==minutes) throw new Error(`${id} schedule regression`);
  }
  const recon=JSON.parse(fs.readFileSync(path.join(wfDir,'ingestion','WF-ING-005_DRIVE_RECONCILIATION.json'),'utf8'));
  const rt=recon.nodes.find(n=>n.type==='n8n-nodes-base.scheduleTrigger');
  if(!rt || rt.parameters?.rule?.interval?.[0]?.minutesInterval!==15) throw new Error('WF-ING-005 must run every 15 minutes');
  for(const id of ['WF-ING-004','WF-ING-005']){
    const e=manifest.workflows.find(w=>w.workflow_id===id);
    const x=JSON.parse(fs.readFileSync(path.join(wfDir,e.file),'utf8'));
    if(x.settings?.errorWorkflow!=='WF-SYS-001') throw new Error(`${id} must use WF-SYS-001`);
  }

  const f3Json=manifest.workflows.filter(w=>w.phase==='F3').map(w=>fs.readFileSync(path.join(wfDir,w.file),'utf8')).join('\n');
  if(/WF-MEM-002|WF-AI-004|WF-MEM-003|WF-MEM-004|WF-MEM-005|WF-REM-005|WF-MCP-001|WF-REP-001/.test(f3Json)) throw new Error('F4+ dependency detected in F3 payload');
  if(/n8n-nodes-base\.executeCommand|getWorkflowStaticData|dataTable/i.test(f3Json)) throw new Error('Forbidden node/state pattern detected');
  if(!/awaiting_external_file/.test(f3Json)) throw new Error('Large-file Drive fallback missing');
  if(!/SHA-256|SHA256/.test(f3Json)) throw new Error('SHA-256 integrity path missing');

  const models=JSON.parse(fs.readFileSync(path.join(root,'config','ai_models.json'),'utf8'));
  if(models.routing.transcription_primary!==null) throw new Error('transcription_primary must remain null before benchmark');
  const cand=models.routing.transcription_candidates.map(x=>`${x.provider}:${x.model}`);
  if(JSON.stringify(cand)!==JSON.stringify(['openai:gpt-transcribe','gemini:gemini-3.5-transcribe'])) throw new Error('Transcription candidates violate AI-DEC-007');

  console.log('F3 WORKFLOW VALIDATION: PASS');
  console.log(' - manifest phase F3 / exactly 23 workflows');
  console.log(' - exact six F3 workflow IDs');
  console.log(' - F2 scheduler regression preserved');
  console.log(' - Drive reconciliation = 15 minutes');
  console.log(' - no F4+ dependency / no Execute Command');
  console.log(' - transcription_primary remains null pending benchmark');
}
validateWorkflows();
