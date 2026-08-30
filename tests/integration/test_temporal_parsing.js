/**
 * Temporal Mapping & Post-AI Deterministic Validation Test Suite
 * Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md & 06_AI_MODELS_AND_PROMPTS.md)
 * 
 * Verifies:
 * - Pure valid time "15:00:00" passes validation and persists correctly.
 * - Full ISO datetime string in time_candidate ("2026-08-31T15:00:00-03:00") is REJECTED by deterministic validator (0 tasks persisted).
 * - Invalid time string ("25:99:99") is REJECTED (0 tasks persisted).
 * - Fake time ("00:00:00" with time_known=false) is REJECTED (0 tasks persisted).
 * - Task without time (time_known=false, time_candidate=null) persists with due_time=NULL, due_at=NULL (WF-TEST-004 DATE-* Rule).
 * - DB strictness: apply_interpretation_bundle throws exception on invalid time format (no silent NULL fallback).
 */

const { Client } = require('pg');
const crypto = require('crypto');

// Deterministic Post-AI Temporal Validator Function (mirrors n8n WF-TASK-001)
function validateTaskTemporalCandidate(t) {
  const timeKnown = Boolean(t.time_known);
  let dueDate = null;
  let dueTime = null;

  // Validate Date: YYYY-MM-DD
  if (t.resolved_date_candidate) {
    const dateStr = String(t.resolved_date_candidate).trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr) || isNaN(Date.parse(dateStr))) {
      return { ok: false, error: `Invalid resolved_date_candidate format: ${dateStr}. Expected YYYY-MM-DD.` };
    }
    dueDate = dateStr;
  }

  // Validate Time
  if (timeKnown) {
    if (!t.time_candidate) {
      return { ok: false, error: 'time_known is true but time_candidate is null or empty' };
    }
    const timeStr = String(t.time_candidate).trim();
    if (timeStr.includes('T') || timeStr.includes('/') || timeStr.length > 8) {
      return { ok: false, error: `Invalid time_candidate format: ${timeStr}. Expected HH:MM:SS, got datetime/offset.` };
    }
    const timeMatch = timeStr.match(/^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$/);
    if (!timeMatch) {
      return { ok: false, error: `Invalid time_candidate format: ${timeStr}. Expected HH:MM:SS.` };
    }
    dueTime = timeMatch[3] ? `${timeMatch[1]}:${timeMatch[2]}:${timeMatch[3]}` : `${timeMatch[1]}:${timeMatch[2]}:00`;
  } else {
    if (t.time_candidate !== null && t.time_candidate !== undefined && String(t.time_candidate).trim() !== '') {
      return { ok: false, error: `time_known is false but time_candidate was provided: ${t.time_candidate}` };
    }
    dueTime = null;
  }

  return {
    ok: true,
    due_date: dueDate,
    due_time: dueTime,
    time_known: timeKnown
  };
}

async function runTemporalValidationSuite() {
  console.log('======================================================================');
  console.log('STARTING TEMPORAL VALIDATION & PERSISTENCE TEST SUITE:');
  console.log('======================================================================\n');

  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
  });
  await client.connect();

  const userA = crypto.randomUUID();
  await client.query(`
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('${userA}', 'authenticated', 'authenticated', 'temp_val_${userA.slice(0,8)}@dev.test', '{"provider":"email"}', '{}', now(), now());
    INSERT INTO public.profiles (id, display_name) VALUES ('${userA}', 'Temporal Validation Tester');
    INSERT INTO public.user_settings (user_id, assistant_name) VALUES ('${userA}', 'Aura');
  `);

  // 1. Case 1: Pure valid time string ("15:00:00") -> PASS & Persists
  console.log('1. Testing pure valid time string ("15:00:00")...');
  const t1Candidate = {
    title: 'Llamar a Juan (Caso 1 Valido)',
    operation: 'create',
    resolved_date_candidate: '2026-08-31',
    time_known: true,
    time_candidate: '15:00:00',
    priority: 'normal'
  };
  const val1 = validateTaskTemporalCandidate(t1Candidate);
  if (!val1.ok) throw new Error(`Case 1 validation failed: ${val1.error}`);

  const ing1 = (await client.query(`
    SELECT public.register_ingestion('${userA}'::uuid, 'telegram', 'text', 'temp:val:1', now(), NULL, 101, 201, 301, 401, NULL, NULL, NULL, '{}'::jsonb) as res;
  `)).rows[0].res.ingestion_id;
  const st1 = (await client.query(`
    SELECT public.get_or_create_source_text('${userA}'::uuid, '${ing1}'::uuid, 'Mañana a las 15 llamar a Juan', 'tg_101', 'telegram_text', true, NULL) as res;
  `)).rows[0].res.source_text_id;

  const b1 = (await client.query(`
    SELECT public.apply_interpretation_bundle('${userA}'::uuid, '${ing1}'::uuid, '${st1}'::uuid, $1::jsonb, 'raw') as res;
  `, [JSON.stringify({ tasks: [{ ...t1Candidate, time_candidate: val1.due_time, resolved_date_candidate: val1.due_date }] })])).rows[0].res;

  const row1 = (await client.query(`SELECT * FROM public.tasks WHERE id = '${b1.task_ids[0]}';`)).rows[0];
  if (row1.due_time !== '15:00:00' || row1.time_known !== true || row1.due_at === null) {
    throw new Error('Case 1 task persistence check failed');
  }
  console.log(`   [PASS] Case 1: Tarea persistida correctamente con due_date=${row1.due_date.toISOString().split('T')[0]}, due_time=${row1.due_time}, time_known=${row1.time_known}, due_at=${row1.due_at}`);

  // 2. Case 2: Malformed ISO datetime in time_candidate ("2026-08-31T15:00:00-03:00") -> REJECTED, 0 tasks persisted
  console.log('\n2. Testing malformed ISO datetime in time_candidate ("2026-08-31T15:00:00-03:00")...');
  const t2Malformed = {
    title: 'Llamar a Juan (Caso 2 Malformado)',
    operation: 'create',
    resolved_date_candidate: '2026-08-31',
    time_known: true,
    time_candidate: '2026-08-31T15:00:00-03:00',
    priority: 'normal'
  };
  const val2 = validateTaskTemporalCandidate(t2Malformed);
  if (val2.ok) throw new Error('Case 2 should have been rejected by validator');
  console.log(`   [PASS] Case 2: Validador post-IA rechazó correctamente el formato inválido: "${val2.error}" -> 0 tareas persistidas`);

  // 3. Case 3: Invalid time string ("25:99:99") -> REJECTED, 0 tasks persisted
  console.log('\n3. Testing invalid time string ("25:99:99")...');
  const t3Invalid = {
    title: 'Llamar a Juan (Caso 3 Invalido)',
    operation: 'create',
    resolved_date_candidate: '2026-08-31',
    time_known: true,
    time_candidate: '25:99:99',
    priority: 'normal'
  };
  const val3 = validateTaskTemporalCandidate(t3Invalid);
  if (val3.ok) throw new Error('Case 3 should have been rejected by validator');
  console.log(`   [PASS] Case 3: Validador post-IA rechazó correctamente el valor inválido: "${val3.error}" -> 0 tareas persistidas`);

  // 4. Case 4: Fake time ("00:00:00" with time_known=false) -> REJECTED, 0 tasks persisted
  console.log('\n4. Testing fake time ("00:00:00" with time_known=false)...');
  const t4Fake = {
    title: 'Comprar pan (Caso 4 Fake Time)',
    operation: 'create',
    resolved_date_candidate: '2026-09-02',
    time_known: false,
    time_candidate: '00:00:00',
    priority: 'normal'
  };
  const val4 = validateTaskTemporalCandidate(t4Fake);
  if (val4.ok) throw new Error('Case 4 fake time should have been rejected by validator');
  console.log(`   [PASS] Case 4: Validador post-IA rechazó hora falsa con time_known=false: "${val4.error}" -> 0 tareas persistidas`);

  // 5. Case 5: Task without time (WF-TEST-004 canonical DATE-* Rule) -> PASS & Persists with due_time=NULL, due_at=NULL
  console.log('\n5. Testing task without time (WF-TEST-004 canonical DATE-* Rule)...');
  const t5NoTime = {
    title: 'Presentar el informe (Caso 5)',
    operation: 'create',
    resolved_date_candidate: '2026-09-02',
    time_known: false,
    time_candidate: null,
    priority: 'normal'
  };
  const val5 = validateTaskTemporalCandidate(t5NoTime);
  if (!val5.ok) throw new Error(`Case 5 validation failed: ${val5.error}`);

  const ing5 = (await client.query(`
    SELECT public.register_ingestion('${userA}'::uuid, 'telegram', 'text', 'temp:val:5', now(), NULL, 105, 205, 305, 405, NULL, NULL, NULL, '{}'::jsonb) as res;
  `)).rows[0].res.ingestion_id;
  const st5 = (await client.query(`
    SELECT public.get_or_create_source_text('${userA}'::uuid, '${ing5}'::uuid, 'El miércoles presentar el informe', 'tg_105', 'telegram_text', true, NULL) as res;
  `)).rows[0].res.source_text_id;

  const b5 = (await client.query(`
    SELECT public.apply_interpretation_bundle('${userA}'::uuid, '${ing5}'::uuid, '${st5}'::uuid, $1::jsonb, 'raw') as res;
  `, [JSON.stringify({ tasks: [t5NoTime] })])).rows[0].res;

  const row5 = (await client.query(`SELECT * FROM public.tasks WHERE id = '${b5.task_ids[0]}';`)).rows[0];
  if (row5.due_time !== null || row5.time_known !== false || row5.due_at !== null) {
    throw new Error('Case 5 task without time failed: due_time or due_at is not NULL');
  }
  console.log(`   [PASS] Case 5: Tarea sin hora persistida con due_date=${row5.due_date.toISOString().split('T')[0]}, due_time=${row5.due_time}, time_known=${row5.time_known}, due_at=${row5.due_at} (estrictamente NULL)`);

  // 6. Case 6: DB strictness test (apply_interpretation_bundle directly called with invalid time format throws exception)
  console.log('\n6. Testing DB strictness (apply_interpretation_bundle with invalid time format throws exception)...');
  let dbThrew = false;
  try {
    await client.query(`
      SELECT public.apply_interpretation_bundle('${userA}'::uuid, '${ing1}'::uuid, '${st1}'::uuid, $1::jsonb, 'raw') as res;
    `, [JSON.stringify({
      tasks: [{
        title: 'Tarea DB Invalida',
        operation: 'create',
        resolved_date_candidate: '2026-08-31',
        time_known: true,
        time_candidate: '2026-08-31T15:00:00-03:00',
        priority: 'normal'
      }]
    })]);
  } catch (err) {
    dbThrew = true;
    console.log(`   [PASS] Case 6: DB rechazó estrictamente el datetime ISO con excepción: "${err.message}" (sin fallback silencioso a NULL)`);
  }
  if (!dbThrew) throw new Error('DB should have thrown exception on invalid time format');

  await client.end();
  console.log('\n======================================================================');
  console.log('ALL TEMPORAL VALIDATION & PERSISTENCE TESTS PASSED (100% SUCCESS)');
  console.log('======================================================================');
}

runTemporalValidationSuite().catch(err => {
  console.error('FATAL TEMPORAL VALIDATION TEST ERROR:', err);
  process.exit(1);
});
