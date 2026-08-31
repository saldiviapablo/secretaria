const fs = require('fs');
const path = require('path');

function validateWorkflows() {
  const root = path.join(__dirname, '..', '..');
  const wfDir = path.join(root, 'n8n', 'workflows');
  const manifestPath = path.join(wfDir, 'manifest.json');
  if (!fs.existsSync(manifestPath)) throw new Error('Missing n8n/workflows/manifest.json');

  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (manifest.phase !== 'F2') throw new Error(`Expected phase F2, got ${manifest.phase}`);
  if (manifest.total_workflows_implemented !== 17) {
    throw new Error(`Expected 17 workflows through F2, got ${manifest.total_workflows_implemented}`);
  }

  const ids = new Set();
  for (const entry of manifest.workflows) {
    if (ids.has(entry.workflow_id)) throw new Error(`Duplicate workflow id ${entry.workflow_id}`);
    ids.add(entry.workflow_id);

    if (!['F0','F1','F2'].includes(entry.phase)) {
      throw new Error(`Out-of-scope phase in manifest: ${entry.workflow_id} -> ${entry.phase}`);
    }
    const full = path.join(wfDir, entry.file);
    if (!fs.existsSync(full)) throw new Error(`Missing workflow file ${entry.file}`);
    const wf = JSON.parse(fs.readFileSync(full, 'utf8'));
    if (!wf.name || !Array.isArray(wf.nodes) || !wf.connections) {
      throw new Error(`Invalid workflow structure in ${entry.file}`);
    }
    if (wf.id && wf.id !== entry.workflow_id) {
      throw new Error(`ID mismatch ${entry.file}: ${wf.id} != ${entry.workflow_id}`);
    }

    const nodeNames = new Set(wf.nodes.map(n => n.name));
    for (const [source, conn] of Object.entries(wf.connections)) {
      if (!nodeNames.has(source)) throw new Error(`Connection source ${source} missing in ${entry.file}`);
      for (const branch of (conn.main || [])) {
        for (const target of (branch || [])) {
          if (!nodeNames.has(target.node)) {
            throw new Error(`Connection target ${target.node} missing in ${entry.file}`);
          }
        }
      }
    }
  }


  function walk(dir) {
    let out = [];
    for (const name of fs.readdirSync(dir)) {
      const full = path.join(dir, name);
      if (fs.statSync(full).isDirectory()) out = out.concat(walk(full));
      else if (name.endsWith('.json') && name !== 'manifest.json') out.push(full);
    }
    return out;
  }
  const actualWorkflowFiles = walk(wfDir);
  if (actualWorkflowFiles.length !== 17) {
    throw new Error(`Expected exactly 17 workflow JSON files through F2, found ${actualWorkflowFiles.length}`);
  }

  const f2Ids = manifest.workflows.filter(w => w.phase === 'F2').map(w => w.workflow_id);
  const expected = ['WF-REM-001','WF-REM-002','WF-REM-003','WF-REM-004'];
  if (JSON.stringify(f2Ids) !== JSON.stringify(expected)) {
    throw new Error(`F2 must contain exactly ${expected.join(', ')}; got ${f2Ids.join(', ')}`);
  }

  const schedules = {
    'WF-REM-002': 1,
    'WF-REM-003': 5,
    'WF-REM-004': 30
  };
  for (const [id, minutes] of Object.entries(schedules)) {
    const entry = manifest.workflows.find(w => w.workflow_id === id);
    const wf = JSON.parse(fs.readFileSync(path.join(wfDir, entry.file), 'utf8'));
    const trigger = wf.nodes.find(n => n.type === 'n8n-nodes-base.scheduleTrigger');
    if (!trigger) throw new Error(`${id} missing Schedule Trigger`);
    const actual = trigger.parameters?.rule?.interval?.[0]?.minutesInterval;
    if (actual !== minutes) throw new Error(`${id} schedule expected ${minutes} min, got ${actual}`);
    if (wf.settings?.errorWorkflow !== 'WF-SYS-001') {
      throw new Error(`${id} must use WF-SYS-001 as error workflow`);
    }
  }

  const f2Json = manifest.workflows
    .filter(w => w.phase === 'F2')
    .map(w => fs.readFileSync(path.join(wfDir, w.file), 'utf8'))
    .join('\n');

  if (/WF-REM-00[56]|WF-ING-003|WF-AI-001|WF-MCP-001|WF-REP-001/.test(f2Json)) {
    throw new Error('F3+ workflow dependency detected inside F2 payload');
  }
  if (/getWorkflowStaticData|dataTable|wait.*(?:hour|day)/i.test(f2Json)) {
    throw new Error('Forbidden durable-state pattern detected in F2 workflows');
  }

  console.log('F2 WORKFLOW VALIDATION: PASS');
  console.log(' - manifest phase F2');
  console.log(' - exactly 17 workflows through F2');
  console.log(' - exactly WF-REM-001..004 added for F2');
  console.log(' - schedules 1m / 5m / 30m');
  console.log(' - central error workflow on F2 schedulers');
  console.log(' - no F3+ dependency detected');
}
validateWorkflows();
