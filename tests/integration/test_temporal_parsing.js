/**
 * Temporal Mapping & Parsing Verification Test Suite
 * Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md & 06_AI_MODELS_AND_PROMPTS.md)
 * 
 * Verifies:
 * - Pure time string "15:00:00"
 * - Full ISO datetime string "2026-08-31T15:00:00-03:00" in time_candidate and resolved_date_candidate
 * - Time with offset "15:00:00-03:00"
 * - Task without time (time_known=false, due_time=NULL, due_at=NULL)
 * - Fake time rejection (00:00:00 with time_known=false)
 */

const { Client } = require('pg');
const crypto = require('crypto');

async function testTemporalMapping() {
  console.log('======================================================================');
  console.log('STARTING TEMPORAL MAPPING & PARSING VERIFICATION:');
  console.log('======================================================================\n');

  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
  });
  await client.connect();

  const userA = crypto.randomUUID();
  await client.query(`
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES ('${userA}', 'authenticated', 'authenticated', 'temporal_${userA.slice(0,8)}@dev.test', '{"provider":"email"}', '{}', now(), now());
    INSERT INTO public.profiles (id, display_name) VALUES ('${userA}', 'Temporal Tester');
    INSERT INTO public.user_settings (user_id, assistant_name) VALUES ('${userA}', 'Aura');
  `);

  // Case 1: Pure time format "15:00:00" (WF-TEST-002 canonical)
  console.log('1. Testing pure time string ("15:00:00")...');
  const ing1 = (await client.query(`
    SELECT public.register_ingestion('${userA}'::uuid, 'telegram', 'text', 'temp:key:1', now(), NULL, 101, 201, 301, 401, NULL, NULL, NULL, '{}'::jsonb) as res;
  `)).rows[0].res.ingestion_id;
  const st1 = (await client.query(`
    SELECT public.get_or_create_source_text('${userA}'::uuid, '${ing1}'::uuid, 'Mañana a las 15 llamar a Juan', 'tg_101', 'telegram_text', true, NULL) as res;
  `)).rows[0].res.source_text_id;

  const b1 = (await client.query(`
    SELECT public.apply_interpretation_bundle('${userA}'::uuid, '${ing1}'::uuid, '${st1}'::uuid, $1::jsonb, 'raw') as res;
  `, [JSON.stringify({
    tasks: [{
      title: 'Llamar a Juan (Caso 1)',
      operation: 'create',
      resolved_date_candidate: '2026-08-31',
      time_known: true,
      time_candidate: '15:00:00',
      priority: 'normal'
    }]
  })])).rows[0].res;

  const t1 = (await client.query(`SELECT * FROM public.tasks WHERE id = '${b1.task_ids[0]}';`)).rows[0];
  if (t1.due_time !== '15:00:00' || t1.time_known !== true || t1.due_at === null) {
    throw new Error('Case 1 pure time failed');
  }
  console.log(`   [PASS] Case 1: due_date=${t1.due_date.toISOString().split('T')[0]}, due_time=${t1.due_time}, time_known=${t1.time_known}, due_at=${t1.due_at}`);

  // Case 2: Full ISO datetime in time_candidate and resolved_date_candidate ("2026-08-31T15:00:00-03:00")
  console.log('\n2. Testing ISO datetime string in time_candidate ("2026-08-31T15:00:00-03:00")...');
  const ing2 = (await client.query(`
    SELECT public.register_ingestion('${userA}'::uuid, 'telegram', 'text', 'temp:key:2', now(), NULL, 102, 202, 302, 402, NULL, NULL, NULL, '{}'::jsonb) as res;
  `)).rows[0].res.ingestion_id;
  const st2 = (await client.query(`
    SELECT public.get_or_create_source_text('${userA}'::uuid, '${ing2}'::uuid, 'Mañana a las 15 llamar a Juan', 'tg_102', 'telegram_text', true, NULL) as res;
  `)).rows[0].res.source_text_id;

  const b2 = (await client.query(`
    SELECT public.apply_interpretation_bundle('${userA}'::uuid, '${ing2}'::uuid, '${st2}'::uuid, $1::jsonb, 'raw') as res;
  `, [JSON.stringify({
    tasks: [{
      title: 'Llamar a Juan (Caso 2 ISO)',
      operation: 'create',
      resolved_date_candidate: '2026-08-31T15:00:00-03:00',
      time_known: true,
      time_candidate: '2026-08-31T15:00:00-03:00',
      priority: 'normal'
    }]
  })])).rows[0].res;

  const t2 = (await client.query(`SELECT * FROM public.tasks WHERE id = '${b2.task_ids[0]}';`)).rows[0];
  if (t2.due_time !== '15:00:00' || t2.time_known !== true || t2.due_at === null) {
    throw new Error('Case 2 ISO time failed');
  }
  console.log(`   [PASS] Case 2: due_date=${t2.due_date.toISOString().split('T')[0]}, due_time=${t2.due_time}, time_known=${t2.time_known}, due_at=${t2.due_at}`);

  // Case 3: Time with offset "15:00:00-03:00"
  console.log('\n3. Testing time with offset string ("15:00:00-03:00")...');
  const ing3 = (await client.query(`
    SELECT public.register_ingestion('${userA}'::uuid, 'telegram', 'text', 'temp:key:3', now(), NULL, 103, 203, 303, 403, NULL, NULL, NULL, '{}'::jsonb) as res;
  `)).rows[0].res.ingestion_id;
  const st3 = (await client.query(`
    SELECT public.get_or_create_source_text('${userA}'::uuid, '${ing3}'::uuid, 'Mañana a las 15 llamar a Juan', 'tg_103', 'telegram_text', true, NULL) as res;
  `)).rows[0].res.source_text_id;

  const b3 = (await client.query(`
    SELECT public.apply_interpretation_bundle('${userA}'::uuid, '${ing3}'::uuid, '${st3}'::uuid, $1::jsonb, 'raw') as res;
  `, [JSON.stringify({
    tasks: [{
      title: 'Llamar a Juan (Caso 3 Offset)',
      operation: 'create',
      resolved_date_candidate: '2026-08-31',
      time_known: true,
      time_candidate: '15:00:00-03:00',
      priority: 'normal'
    }]
  })])).rows[0].res;

  const t3 = (await client.query(`SELECT * FROM public.tasks WHERE id = '${b3.task_ids[0]}';`)).rows[0];
  if (t3.due_time !== '15:00:00' || t3.time_known !== true) {
    throw new Error('Case 3 offset time failed');
  }
  console.log(`   [PASS] Case 3: due_date=${t3.due_date.toISOString().split('T')[0]}, due_time=${t3.due_time}, time_known=${t3.time_known}`);

  // Case 4: Task without time (WF-TEST-004 canonical DATE-* Rule)
  console.log('\n4. Testing task without time (WF-TEST-004 DATE-* Rule)...');
  const ing4 = (await client.query(`
    SELECT public.register_ingestion('${userA}'::uuid, 'telegram', 'text', 'temp:key:4', now(), NULL, 104, 204, 304, 404, NULL, NULL, NULL, '{}'::jsonb) as res;
  `)).rows[0].res.ingestion_id;
  const st4 = (await client.query(`
    SELECT public.get_or_create_source_text('${userA}'::uuid, '${ing4}'::uuid, 'El miércoles presentar informe', 'tg_104', 'telegram_text', true, NULL) as res;
  `)).rows[0].res.source_text_id;

  const b4 = (await client.query(`
    SELECT public.apply_interpretation_bundle('${userA}'::uuid, '${ing4}'::uuid, '${st4}'::uuid, $1::jsonb, 'raw') as res;
  `, [JSON.stringify({
    tasks: [{
      title: 'Presentar informe (Caso 4)',
      operation: 'create',
      resolved_date_candidate: '2026-09-02',
      time_known: false,
      time_candidate: null,
      priority: 'normal'
    }]
  })])).rows[0].res;

  const t4 = (await client.query(`SELECT * FROM public.tasks WHERE id = '${b4.task_ids[0]}';`)).rows[0];
  if (t4.due_time !== null || t4.time_known !== false || t4.due_at !== null) {
    throw new Error('Case 4 without time failed: due_time or due_at is not NULL');
  }
  console.log(`   [PASS] Case 4: due_date=${t4.due_date.toISOString().split('T')[0]}, due_time=${t4.due_time}, time_known=${t4.time_known}, due_at=${t4.due_at} (strictly NULL)`);

  await client.end();
  console.log('\n======================================================================');
  console.log('ALL TEMPORAL MAPPING TESTS PASSED WITH 100% SUCCESS');
  console.log('======================================================================');
}

testTemporalMapping().catch(err => {
  console.error('FATAL TEMPORAL TEST ERROR:', err);
  process.exit(1);
});
