const fs = require('fs');
const path = require('path');

function validateWorkflows() {
  const root = path.join(__dirname, '..', '..');
  const wfDir = path.join(root, 'n8n', 'workflows');
  
  const expectedFiles = [
    'system/WF-SYS-001_ERROR_HANDLER.json',
    'ingestion/WF-ING-001_REGISTER_INGESTION.json',
    'telegram/WF-TG-002_TELEGRAM_SEND_MESSAGE.json'
  ];

  console.log('======================================================================');
  console.log('VALIDATING N8N WORKFLOW SCHEMAS & DEPENDENCY INTEGRITY:');
  
  for (const rel of expectedFiles) {
    const fullPath = path.join(wfDir, rel);
    if (!fs.existsSync(fullPath)) throw new Error(`Missing workflow file: ${rel}`);
    
    const content = fs.readFileSync(fullPath, 'utf-8');
    const wf = JSON.parse(content);
    
    if (!wf.name || typeof wf.name !== 'string') throw new Error(`Invalid name in ${rel}`);
    if (!Array.isArray(wf.nodes) || wf.nodes.length === 0) throw new Error(`No nodes in ${rel}`);
    if (!wf.connections || typeof wf.connections !== 'object') throw new Error(`Missing connections in ${rel}`);
    
    // Check no plaintext secrets/passwords in workflow definition
    const jsonStr = JSON.stringify(wf);
    if (/(?:\"password\"|\"secret\"|\"apiKey\"|\"token\")\s*:\s*\"[^\"]+\"/i.test(jsonStr)) {
      throw new Error(`Plaintext secret detected in ${rel}`);
    }

    // Verify all connections point to existing nodes
    const nodeNames = new Set(wf.nodes.map(n => n.name));
    for (const [srcNode, connObj] of Object.entries(wf.connections)) {
      if (!nodeNames.has(srcNode)) throw new Error(`Connection from non-existent node "${srcNode}" in ${rel}`);
      if (connObj.main) {
        for (const branch of connObj.main) {
          for (const target of branch) {
            if (!nodeNames.has(target.node)) {
              throw new Error(`Connection to non-existent target "${target.node}" in ${rel}`);
            }
          }
        }
      }
    }

    console.log(` [PASS] ${rel}: ${wf.nodes.length} nodes, valid graph, 0 plaintext secrets`);
  }

  // Ensure NO F1+ workflows exist
  function getFiles(dir) {
    let res = [];
    for (const f of fs.readdirSync(dir)) {
      const p = path.join(dir, f);
      if (fs.statSync(p).isDirectory()) res.push(...getFiles(p));
      else if (f.endsWith('.json')) res.push(p);
    }
    return res;
  }
  
  const allWorkflows = getFiles(wfDir);
  if (allWorkflows.length !== 3) {
    throw new Error(`Found ${allWorkflows.length} workflow files, expected exactly 3 for F0`);
  }
  console.log(' [PASS] Manifest verified: Exactly 3 N8N-0 workflows present in repository');
  console.log('======================================================================');
}

validateWorkflows();
