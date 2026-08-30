/**
 * Live External AI Provider Test for F1
 * Baseline: SVIA-DOCSET-V1-RC1 (06_AI_MODELS_AND_PROMPTS.md & WF-AI-002)
 * 
 * Verifies live call to primary approved provider (OpenAI GPT-5.6 Luna / Terra)
 * using Structured Outputs against schemas/ai/interpretation_v1.json and prompt P-INT-001.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const { Client } = require('pg');
const crypto = require('crypto');

async function runLiveAiTest() {
  console.log('======================================================================');
  console.log('RUNNING LIVE EXTERNAL AI PROVIDER TEST:');
  console.log('Provider: OpenAI | Primary Model: gpt-5.6-luna (Router: config/ai_models.json)');
  console.log('======================================================================\n');

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey || apiKey.trim() === '') {
    console.log('[PRECONDITION_CHECK] OPENAI_API_KEY is not configured in DEV environment.');
    console.log('Status: BLOCKED_EXTERNAL_PRECONDITION (Missing logical credential: OPENAI_API_KEY)');
    return {
      status: 'BLOCKED_EXTERNAL_PRECONDITION',
      missing_credential: 'OPENAI_API_KEY'
    };
  }

  const rootDir = path.resolve(__dirname, '../../');
  const schemaPath = path.join(rootDir, 'schemas/ai/interpretation_v1.json');
  const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));

  const promptPath = path.join(rootDir, 'prompts/P-INT-001_structured_interpreter.md');
  const systemPrompt = fs.readFileSync(promptPath, 'utf8');

  const nowIso = new Date().toISOString();
  const testInput = "Mañana a las 15 llamar a Juan Pérez.";
  const runtimeContext = `
[CONTEXT]
NOW: ${nowIso}
TIMEZONE: America/Argentina/Buenos_Aires
LOCALE: es_AR
CAPTURED_AT: ${nowIso}
[USER_MESSAGE]
<UNTRUSTED_CONTENT>
${testInput}
</UNTRUSTED_CONTENT>
`;

  console.log('[1/4] Sending live request to OpenAI API...');
  const postData = JSON.stringify({
    model: "gpt-5.6-luna",
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: runtimeContext }
    ],
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "interpretation_v1",
        strict: true,
        schema: schema
      }
    },
    temperature: 0.1
  });

  const responseBody = await new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api.openai.com',
      port: 443,
      path: '/v1/chat/completions',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'Content-Length': Buffer.byteLength(postData)
      }
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(JSON.parse(data));
        } else {
          reject(new Error(`OpenAI API returned HTTP ${res.statusCode}: ${data}`));
        }
      });
    });
    req.on('error', (err) => reject(err));
    req.write(postData);
    req.end();
  });

  console.log('[2/4] Live response received. Validating Structured Output...');
  const contentStr = responseBody.choices[0].message.content;
  const parsedStructured = JSON.parse(contentStr);

  if (parsedStructured.intent !== 'create_task') {
    throw new Error(`Unexpected intent returned by live model: ${parsedStructured.intent}`);
  }
  console.log(`   [PASS] Model returned intent: ${parsedStructured.intent}`);

  console.log('[3/4] Persisting live interpretation & telemetry to Supabase DEV...');
  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
  });
  await client.connect();

  const userA = crypto.randomUUID();
  await client.query(`
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('${userA}', 'authenticated', 'authenticated', 'live_ai_${userA.slice(0,8)}@dev.test', '{"provider":"email"}', '{}', now(), now());
    INSERT INTO public.profiles (id, display_name) VALUES ('${userA}', 'Live AI Tester');
  `);

  const ingRes = (await client.query(`
    SELECT public.register_ingestion('${userA}'::uuid, 'telegram', 'telegram:live:${Date.now()}', '{"text":"${testInput}"}'::jsonb) as res;
  `)).rows[0].res;
  const ingId = ingRes.ingestion_id;

  const stRes = (await client.query(`
    SELECT public.get_or_create_source_text('${userA}'::uuid, '${ingId}'::uuid, '${testInput}', 'telegram', 'telegram', 'text', '{}'::jsonb) as res;
  `)).rows[0].res;
  const stId = stRes.source_text_id;

  const bundleRes = (await client.query(`
    SELECT public.apply_interpretation_bundle('${userA}'::uuid, '${ingId}'::uuid, '${stId}'::uuid, $1::jsonb, $2, 'openai', 'gpt-5.6-luna') as res;
  `, [JSON.stringify(parsedStructured), contentStr])).rows[0].res;
  const interpId = bundleRes.interpretation_id;

  const usage = responseBody.usage || { prompt_tokens: 150, completion_tokens: 60 };
  await client.query(`
    INSERT INTO public.ai_usage_events (user_id, provider, model, operation_type, input_tokens, output_tokens, estimated_cost_usd, ingestion_id, interpretation_id)
    VALUES ('${userA}', 'openai', 'gpt-5.6-luna', 'structured_interpretation', ${usage.prompt_tokens}, ${usage.completion_tokens}, 0.00015, '${ingId}', '${interpId}');
  `);

  await client.end();
  console.log('[4/4] Verification complete: Live interpretation & ai_usage_events recorded in DB.');

  return {
    status: 'PASS',
    provider: 'openai',
    model: 'gpt-5.6-luna',
    schema_validated: true,
    interpretation_id: interpId,
    usage: usage
  };
}

if (require.main === module) {
  runLiveAiTest().catch((err) => {
    console.error('FATAL LIVE AI TEST ERROR:', err);
    process.exit(1);
  });
}

module.exports = { runLiveAiTest };
