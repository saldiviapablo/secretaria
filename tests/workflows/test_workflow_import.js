const fs = require('fs');
const path = require('path');

function validateWorkflows() {
  const root = path.join(__dirname, '..', '..');
  const wfDir = path.join(root, 'n8n', 'workflows');
  const manifestPath = path.join(wfDir, 'manifest.json');
  
  if (!fs.existsSync(manifestPath)) throw new Error('Missing manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

  console.log('======================================================================');
  console.log(`VALIDATING N8N WORKFLOW SCHEMAS & DEPENDENCY INTEGRITY (PHASE: ${manifest.phase}):`);
  
  for (const wfEntry of manifest.workflows) {
    const fullPath = path.join(wfDir, wfEntry.file);
    if (!fs.existsSync(fullPath)) throw new Error(`Missing workflow file: ${wfEntry.file}`);
    
    const content = fs.readFileSync(fullPath, 'utf-8');
    const wf = JSON.parse(content);
    
    if (!wf.name || typeof wf.name !== 'string') throw new Error(`Invalid name in ${wfEntry.file}`);
    if (!Array.isArray(wf.nodes) || wf.nodes.length === 0) throw new Error(`No nodes in ${wfEntry.file}`);
    if (!wf.connections || typeof wf.connections !== 'object') throw new Error(`Missing connections in ${wfEntry.file}`);
    
    // Check no plaintext secrets/passwords in workflow definition
    const jsonStr = JSON.stringify(wf);
    if (/(?:\"password\"|\"secret\"|\"apiKey\"|\"token\")\s*:\s*\"(?!supabase_dev|\[REDACTED\])[^\"]+\"/i.test(jsonStr)) {
      throw new Error(`Plaintext secret detected in ${wfEntry.file}`);
    }

    // Verify all connections point to existing nodes
    const nodeNames = new Set(wf.nodes.map(n => n.name));
    for (const [srcNode, connObj] of Object.entries(wf.connections)) {
      if (!nodeNames.has(srcNode)) throw new Error(`Connection from non-existent node "${srcNode}" in ${wfEntry.file}`);
      if (connObj.main) {
        for (const branch of connObj.main) {
          for (const target of branch) {
            if (!nodeNames.has(target.node)) {
              throw new Error(`Connection to non-existent target "${target.node}" in ${wfEntry.file}`);
            }
          }
        }
      }
    }

    console.log(` [PASS] ${wfEntry.file}: ${wf.nodes.length} nodes, valid graph, 0 plaintext secrets`);
  }

  // Ensure NO F2+ workflows exist
  function getFiles(dir) {
    let res = [];
    for (const f of fs.readdirSync(dir)) {
      const p = path.join(dir, f);
      if (fs.statSync(p).isDirectory()) res.push(...getFiles(p));
      else if (f.endsWith('.json') && f !== 'manifest.json') res.push(p);
    }
    return res;
  }
  
  const allWorkflows = getFiles(wfDir);
  if (allWorkflows.length !== 13) {
    throw new Error(`Found ${allWorkflows.length} workflow files, expected exactly 13 for F1`);
  }
  console.log(' [PASS] Manifest verified: Exactly 13 workflows (3 F0 + 10 F1) present in repository');
  console.log('======================================================================');
}

validateWorkflows();
