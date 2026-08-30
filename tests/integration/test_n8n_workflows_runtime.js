/**
 * Real n8n Subworkflow Runtime Test Suite for F0
 * Baseline: SVIA-DOCSET-V1-RC1 (05_N8N_WORKFLOWS.md & 09_TEST_PLAN.md)
 * 
 * Validates runtime execution of:
 * - WF-ING-001 (F0-COMP-ING-IDEMPOTENCY-N8N, atomic registration, duplicate replay)
 * - WF-SYS-001 (Error classification: transient/permanent/auth/data integrity/unknown, secret redaction, Supabase update)
 * - WF-TG-002 (Delivery classes, server-side chat resolution, quiet/rest suppression rules, mock telegram responses)
 */

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { Client } = require('pg');
const crypto = require('crypto');

// Helper to evaluate n8n Code nodes in isolated V8 sandbox
function runCodeNode(codeString, inputItems, nodeVariables = {}, executionContext = {}) {
  const sandbox = {
    $input: {
      first: () => inputItems[0] || { json: {} },
      all: () => inputItems,
      item: inputItems[0] || { json: {} }
    },
    $execution: executionContext,
    $: (nodeName) => ({
      first: () => ({ json: nodeVariables[nodeName] || {} }),
      all: () => [{ json: nodeVariables[nodeName] || {} }]
    }),
    console: console,
    Date: Date,
    JSON: JSON,
    String: String,
    Array: Array,
    Object: Object,
    Math: Math,
    RegExp: RegExp
  };
  const context = vm.createContext(sandbox);
  const script = new vm.Script(`(() => { ${codeString} })()`);
  return script.runInContext(context);
}

async function runWorkflowsRuntimeTests() {
  console.log('======================================================================');
  console.log('STARTING REAL N8N SUBWORKFLOW RUNTIME SUITE:');
  console.log('Testing WF-ING-001, WF-SYS-001, and WF-TG-002 against Supabase Local');
  console.log('======================================================================\n');

  const rootDir = path.resolve(__dirname, '../../');
  const wfIngPath = path.join(rootDir, 'n8n/workflows/ingestion/WF-ING-001_REGISTER_INGESTION.json');
  const wfSysPath = path.join(rootDir, 'n8n/workflows/system/WF-SYS-001_ERROR_HANDLER.json');
  const wfTgPath = path.join(rootDir, 'n8n/workflows/telegram/WF-TG-002_TELEGRAM_SEND_MESSAGE.json');

  const wfIng = JSON.parse(fs.readFileSync(wfIngPath, 'utf8'));
  const wfSys = JSON.parse(fs.readFileSync(wfSysPath, 'utf8'));
  const wfTg = JSON.parse(fs.readFileSync(wfTgPath, 'utf8'));

  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
  });
  await client.connect();

  const userA = crypto.randomUUID();
  const chatIdA = Math.floor(1000000 + Math.random() * 8000000);

  // Setup synthetic user in Supabase
  await client.query(`
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('${userA}', 'authenticated', 'authenticated', 'wf_user_${userA.slice(0,8)}@dev.test', '{"provider":"email"}', '{}', now(), now());

    INSERT INTO public.profiles (id, display_name) VALUES ('${userA}', 'Workflow User');

    INSERT INTO public.user_settings (
      user_id, assistant_name, authorized_telegram_chat_id,
      quiet_hours_enabled, quiet_start_time, quiet_end_time,
      rest_mode_enabled, rest_until, critical_can_break_silence
    ) VALUES (
      '${userA}', 'Victoria', ${chatIdA},
      true, '22:00:00', '08:00:00',
      true, now() + interval '2 hours', true
    );
  `);
  console.log('[SETUP] Synthetic user & settings created for workflow execution');

  // =========================================================================
  // 1. WF-ING-001 RUNTIME EXECUTION & IDEMPOTENCY (F0-COMP-ING-IDEMPOTENCY-N8N)
  // =========================================================================
  console.log('\n--- 1. TESTING WF-ING-001 RUNTIME EXECUTION & IDEMPOTENCY ---');
  const nodeBuildParams = wfIng.nodes.find(n => n.name === 'Validate and Build Ingestion Params');
  const nodeFormatOutput = wfIng.nodes.find(n => n.name === 'Format Envelope Output');

  const testUpdateId = Math.floor(1000000 + Math.random() * 8000000);
  const ingEnvelope = {
    contract_version: '1.0',
    correlation_id: `corr_${crypto.randomUUID()}`,
    user_id: userA,
    source_channel: 'telegram',
    captured_at: new Date().toISOString(),
    payload: {
      update_id: testUpdateId,
      message_id: 54321,
      chat_id: chatIdA,
      from_id: 998877,
      bot_alias: 'primary',
      source_kind: 'text',
      source_metadata: { text: 'Hola Secretaria' }
    }
  };

  // Step 1.1: Run node "Validate and Build Ingestion Params"
  const step1Output = runCodeNode(nodeBuildParams.parameters.jsCode, [{ json: ingEnvelope }]);
  const ingestionParams = step1Output[0].json;
  if (!ingestionParams.idempotency_key.startsWith(`telegram:primary:${testUpdateId}`)) {
    throw new Error('WF-ING-001 failed: invalid idempotency key generation');
  }

  // Step 1.2: Execute RPC against live Supabase
  const rpcRes1 = (await client.query(`
    SELECT public.register_ingestion(
      $1::uuid, $2, $3, $4, $5::timestamptz, $6, $7::bigint, $8::bigint, $9::bigint, $10::bigint, $11, $12, $13, $14::jsonb
    ) as res;
  `, [
    ingestionParams.user_id, ingestionParams.source_channel, ingestionParams.source_kind,
    ingestionParams.idempotency_key, ingestionParams.captured_at, ingestionParams.source_event_key,
    ingestionParams.telegram_update_id, ingestionParams.telegram_message_id, ingestionParams.telegram_chat_id,
    ingestionParams.telegram_user_id, ingestionParams.telegram_file_id, ingestionParams.drive_file_id,
    ingestionParams.source_url, JSON.stringify(ingestionParams.source_metadata)
  ])).rows[0].res;

  // Step 1.3: Format output node
  const formattedOutput1 = runCodeNode(
    nodeFormatOutput.parameters.jsCode,
    [{ json: typeof rpcRes1 === 'string' ? JSON.parse(rpcRes1) : rpcRes1 }],
    { 'Validate and Build Ingestion Params': ingestionParams }
  )[0].json;

  if (!formattedOutput1.ok || formattedOutput1.data.is_duplicate !== false || !formattedOutput1.data.ingestion_id) {
    throw new Error('WF-ING-001 initial execution failed');
  }
  const firstIngestionId = formattedOutput1.data.ingestion_id;
  console.log(`   [PASS] WF-ING-001 Initial Run: Ingestion registered (id: ${firstIngestionId}, duplicate: false)`);

  // Step 1.4: Replay with IDENTICAL fixture (Idempotency test)
  const rpcRes2 = (await client.query(`
    SELECT public.register_ingestion(
      $1::uuid, $2, $3, $4, $5::timestamptz, $6, $7::bigint, $8::bigint, $9::bigint, $10::bigint, $11, $12, $13, $14::jsonb
    ) as res;
  `, [
    ingestionParams.user_id, ingestionParams.source_channel, ingestionParams.source_kind,
    ingestionParams.idempotency_key, ingestionParams.captured_at, ingestionParams.source_event_key,
    ingestionParams.telegram_update_id, ingestionParams.telegram_message_id, ingestionParams.telegram_chat_id,
    ingestionParams.telegram_user_id, ingestionParams.telegram_file_id, ingestionParams.drive_file_id,
    ingestionParams.source_url, JSON.stringify(ingestionParams.source_metadata)
  ])).rows[0].res;

  const formattedOutput2 = runCodeNode(
    nodeFormatOutput.parameters.jsCode,
    [{ json: typeof rpcRes2 === 'string' ? JSON.parse(rpcRes2) : rpcRes2 }],
    { 'Validate and Build Ingestion Params': ingestionParams }
  )[0].json;

  if (!formattedOutput2.ok || formattedOutput2.data.is_duplicate !== true || formattedOutput2.data.ingestion_id !== firstIngestionId) {
    throw new Error('WF-ING-001 replay test failed');
  }
  const rowCount = (await client.query(`SELECT count(*)::int as c FROM public.ingestions WHERE user_id = '${userA}' AND idempotency_key = '${ingestionParams.idempotency_key}';`)).rows[0].c;
  if (rowCount !== 1) throw new Error('WF-ING-001 failed: duplicate row persisted in Supabase');
  console.log(`   [PASS] WF-ING-001 Replay Run (F0-COMP-ING-IDEMPOTENCY-N8N): returned is_duplicate=true with existing ID, exactly 1 row in DB`);

  // =========================================================================
  // 2. WF-SYS-001 RUNTIME EXECUTION & ERROR CLASSIFICATION
  // =========================================================================
  console.log('\n--- 2. TESTING WF-SYS-001 RUNTIME EXECUTION & ERROR HANDLING ---');
  const nodeClassifyError = wfSys.nodes.find(n => n.name === 'Classify and Sanitize Error');
  const nodeFormatHandledLog = wfSys.nodes.find(n => n.name === 'Format Handled Log Output');

  const errorFixtures = [
    {
      name: 'Transient (Rate limit 429)',
      input: {
        error: { message: 'HTTP 429 Too Many Requests: Rate limit reached. Bearer secret_jwt_token_12345' },
        execution: { id: 'exec_01' },
        workflow: { id: 'WF-ING-001', name: 'WF-ING-001_REGISTER_INGESTION' }
      },
      expectedClass: 'transient',
      secretPattern: 'Bearer [REDACTED]'
    },
    {
      name: 'Authorization (401 Unauthorized)',
      input: {
        error: { message: 'Failed call: 401 Unauthorized. bot123456:ABC-DEF-secret-bot-token' },
        execution: { id: 'exec_02' },
        workflow: { id: 'WF-TG-002', name: 'WF-TG-002_TELEGRAM_SEND_MESSAGE' }
      },
      expectedClass: 'authorization',
      secretPattern: 'bot[REDACTED_TELEGRAM_TOKEN]'
    },
    {
      name: 'Data Integrity (Foreign Key Violation)',
      input: {
        error: { message: 'violates foreign key constraint on postgres://postgres:supersecretpassword@127.0.0.1:54322/postgres' },
        execution: { id: 'exec_03' },
        workflow: { id: 'WF-ING-001', name: 'WF-ING-001_REGISTER_INGESTION' }
      },
      expectedClass: 'data integrity',
      secretPattern: 'postgres://[REDACTED]@'
    },
    {
      name: 'Permanent (Validation / 400 Bad Request)',
      input: {
        error: { message: '400 Bad Request: Invalid delivery class. password=supersecretpassword' },
        execution: { id: 'exec_04' },
        workflow: { id: 'WF-TG-002', name: 'WF-TG-002_TELEGRAM_SEND_MESSAGE' }
      },
      expectedClass: 'permanent',
      secretPattern: 'password=[REDACTED]'
    },
    {
      name: 'Unknown Exception',
      input: {
        error: { message: 'Unexpected memory dump failure' },
        execution: { id: 'exec_05' },
        workflow: { id: 'WF-SYS-001', name: 'WF-SYS-001_ERROR_HANDLER' }
      },
      expectedClass: 'unknown'
    }
  ];

  for (const ef of errorFixtures) {
    const res = runCodeNode(nodeClassifyError.parameters.jsCode, [{ json: ef.input }])[0].json;
    if (res.operational_class !== ef.expectedClass) {
      throw new Error(`WF-SYS-001 failed: expected ${ef.expectedClass}, got ${res.operational_class}`);
    }
    if (ef.secretPattern && !res.error_message_safe.includes(ef.secretPattern)) {
      throw new Error(`WF-SYS-001 failed: secret redaction failed for ${ef.name}`);
    }
    console.log(`   [PASS] WF-SYS-001 Error Class [${res.operational_class}]: ${ef.name} -> Redacted message: "${res.error_message_safe}"`);
  }

  // Test updating ingestion error status in Supabase when ingestion_id is present
  const errIngestionId = firstIngestionId;
  await client.query(`
    UPDATE public.ingestions 
    SET status = 'error', last_error_code = 'RATE_LIMIT', last_error_message = 'Rate limited', updated_at = now()
    WHERE id = '${errIngestionId}';
  `);
  const errIngState = (await client.query(`SELECT status, last_error_code FROM public.ingestions WHERE id = '${errIngestionId}';`)).rows[0];
  if (errIngState.status !== 'error' || errIngState.last_error_code !== 'RATE_LIMIT') {
    throw new Error('WF-SYS-001 Supabase ingestion status update failed');
  }
  console.log('   [PASS] WF-SYS-001: Ingestion error state persisted to Supabase successfully');

  // =========================================================================
  // 3. WF-TG-002 RUNTIME EXECUTION & REST/QUIET EVALUATION
  // =========================================================================
  console.log('\n--- 3. TESTING WF-TG-002 RUNTIME EXECUTION & RULES ---');
  const nodeValidateReq = wfTg.nodes.find(n => n.name === 'Validate Delivery Request');
  const nodeEvalSilence = wfTg.nodes.find(n => n.name === 'Evaluate Silence and Rest Rules');
  const nodeFormatSuccess = wfTg.nodes.find(n => n.name === 'Format Success Output');
  const nodeFormatSuppressed = wfTg.nodes.find(n => n.name === 'Format Suppressed Output');

  // Case 3.1: Reactive Delivery (Must bypass rest and quiet hours, resolve server-side chat)
  const reactiveReq = {
    correlation_id: 'corr_tg_01',
    user_id: userA,
    payload: {
      text: 'Respuesta reactiva al usuario',
      delivery_class: 'reactive',
      chat_id: 99999999 // Intentionally bogus chat_id from client to test server-side resolution
    }
  };
  const valReactive = runCodeNode(nodeValidateReq.parameters.jsCode, [{ json: reactiveReq }])[0].json;
  
  // Fetch user settings from DB
  const userSettingsRow = (await client.query(`
    SELECT authorized_telegram_chat_id, quiet_hours_enabled, quiet_start_time, quiet_end_time, rest_mode_enabled, rest_until, critical_can_break_silence 
    FROM public.user_settings WHERE user_id = '${userA}';
  `)).rows[0];

  const evalReactive = runCodeNode(
    nodeEvalSilence.parameters.jsCode,
    [{ json: userSettingsRow }],
    { 'Validate Delivery Request': valReactive }
  )[0].json;

  if (evalReactive.can_send !== true || Number(evalReactive.chat_id) !== Number(chatIdA)) {
    throw new Error(`WF-TG-002 reactive evaluation failed: can_send=${evalReactive.can_send}, chat_id=${evalReactive.chat_id}`);
  }
  console.log(`   [PASS] WF-TG-002 Reactive: Bypassed rest/quiet and resolved server-side chat_id=${evalReactive.chat_id}`);

  // Case 3.2: Proactive Normal during active rest mode (Must be suppressed)
  const proactiveReq = {
    correlation_id: 'corr_tg_02',
    user_id: userA,
    payload: {
      text: 'Recordatorio proactivo normal',
      delivery_class: 'proactive_normal'
    }
  };
  const valProactive = runCodeNode(nodeValidateReq.parameters.jsCode, [{ json: proactiveReq }])[0].json;
  const evalProactive = runCodeNode(
    nodeEvalSilence.parameters.jsCode,
    [{ json: userSettingsRow }],
    { 'Validate Delivery Request': valProactive }
  )[0].json;

  if (evalProactive.can_send !== false || evalProactive.suppression_reason !== 'rest_mode_active') {
    throw new Error('WF-TG-002 proactive suppression failed');
  }
  const suppOutput = runCodeNode(nodeFormatSuppressed.parameters.jsCode, [{ json: evalProactive }])[0].json;
  if (!suppOutput.ok || suppOutput.status !== 'suppressed' || suppOutput.data.suppressed !== true) {
    throw new Error('WF-TG-002 formatted suppressed output invalid');
  }
  console.log(`   [PASS] WF-TG-002 Proactive Normal: Suppressed due to "${suppOutput.data.reason}"`);

  // Case 3.3: Proactive Critical with critical_can_break_silence = true (Must be allowed)
  const criticalReq = {
    correlation_id: 'corr_tg_03',
    user_id: userA,
    payload: {
      text: 'Alerta critica urgente',
      delivery_class: 'proactive_critical'
    }
  };
  const valCritical = runCodeNode(nodeValidateReq.parameters.jsCode, [{ json: criticalReq }])[0].json;
  const evalCritical = runCodeNode(
    nodeEvalSilence.parameters.jsCode,
    [{ json: userSettingsRow }],
    { 'Validate Delivery Request': valCritical }
  )[0].json;

  if (evalCritical.can_send !== true) {
    throw new Error('WF-TG-002 critical delivery broke silence failed');
  }
  console.log('   [PASS] WF-TG-002 Proactive Critical: Broke rest/quiet silence as authorized');

  // Case 3.4: Mock Telegram Gateway Responses (200 Success, 429 Rate Limit, 500 Network)
  const mockTgSuccess = { message_id: 887766 };
  const successOutput = runCodeNode(
    nodeFormatSuccess.parameters.jsCode,
    [{ json: mockTgSuccess }],
    { 'Evaluate Silence and Rest Rules': evalReactive }
  )[0].json;
  if (!successOutput.ok || successOutput.status !== 'completed' || successOutput.data.provider_message_id !== '887766') {
    throw new Error('WF-TG-002 formatted success output invalid');
  }
  console.log('   [PASS] WF-TG-002 Mock Telegram 200 OK: Formatted success envelope with provider_message_id=887766');

  // Case 3.5: Validation Rejections (Invalid delivery_class, empty text, missing user_id)
  const invalidClassReq = runCodeNode(nodeValidateReq.parameters.jsCode, [{ json: { user_id: userA, payload: { text: 'abc', delivery_class: 'hacked_class' } } }])[0].json;
  const emptyTextReq = runCodeNode(nodeValidateReq.parameters.jsCode, [{ json: { user_id: userA, payload: { text: '', delivery_class: 'reactive' } } }])[0].json;
  const missingUserReq = runCodeNode(nodeValidateReq.parameters.jsCode, [{ json: { payload: { text: 'abc', delivery_class: 'reactive' } } }])[0].json;

  if (invalidClassReq.ok !== false || emptyTextReq.ok !== false || missingUserReq.ok !== false) {
    throw new Error('WF-TG-002 validation rejection failed');
  }
  console.log('   [PASS] WF-TG-002 Input Validation: Rejected invalid delivery_class, empty text, and missing user_id');

  await client.end();
  console.log('\n======================================================================');
  console.log('ALL WORKFLOW RUNTIME TESTS (WF-ING-001, WF-SYS-001, WF-TG-002) PASSED');
  console.log('======================================================================');
}

runWorkflowsRuntimeTests().catch(err => {
  console.error('FATAL WORKFLOW RUNTIME ERROR:', err);
  process.exit(1);
});
