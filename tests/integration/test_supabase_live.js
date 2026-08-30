const { Client } = require('pg');

async function runLiveSupabaseTests() {
  console.log('======================================================================');
  console.log('STARTING REAL SUPABASE LOCAL RUNTIME TESTS:');
  console.log('Target: postgresql://postgres:postgres@127.0.0.1:54322/postgres');
  console.log('======================================================================');

  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
  });

  await client.connect();

  console.log('\n1. VERIFYING SUPABASE AUTH & EXTENSIONS:');
  // Check auth.users exists as part of Supabase stack
  const authUsersRes = await client.query(`
    SELECT table_name FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users';
  `);
  if (authUsersRes.rows.length !== 1) throw new Error('Supabase auth.users table missing');
  console.log('   [PASS] Supabase auth.users table verified in schema auth');

  // Check extensions
  const extRes = await client.query(`
    SELECT extname FROM pg_extension WHERE extname IN ('pgcrypto', 'vector', 'pg_trgm', 'unaccent');
  `);
  const foundExts = extRes.rows.map(r => r.extname);
  console.log('   [PASS] Required extensions installed in Supabase:', foundExts.join(', '));
  if (foundExts.length < 4) throw new Error('Missing required extensions in Supabase');

  console.log('\n2. VERIFYING 25 V1 TABLES IN PUBLIC SCHEMA:');
  const tablesRes = await client.query(`
    SELECT table_name FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    ORDER BY table_name;
  `);
  console.log(`   Found ${tablesRes.rows.length} tables in public schema:`);
  tablesRes.rows.forEach(r => console.log(`    - ${r.table_name}`));
  if (tablesRes.rows.length !== 25) throw new Error(`Expected 25 tables, found ${tablesRes.rows.length}`);

  console.log('\n3. RUNNING REAL DB BEHAVIOR & INTEGRITY TESTS:');
  const crypto = require('crypto');
  const userA = crypto.randomUUID();
  const userB = crypto.randomUUID();
  const chatIdA = Math.floor(1000000 + Math.random() * 8000000);
  const chatIdB = Math.floor(1000000 + Math.random() * 8000000);

  // Provision synthetic users in Supabase auth.users & profiles
  await client.query(`
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES 
      ('${userA}', 'authenticated', 'authenticated', 'userA_${userA.slice(0,8)}@dev.test', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
      ('${userB}', 'authenticated', 'authenticated', 'userB_${userB.slice(0,8)}@dev.test', '{"provider":"email","providers":["email"]}', '{}', now(), now())
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (id, display_name) VALUES ('${userA}', 'User A'), ('${userB}', 'User B')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.user_settings (user_id, assistant_name, authorized_telegram_chat_id)
    VALUES ('${userA}', 'Victoria', ${chatIdA}), ('${userB}', 'Clara', ${chatIdB})
    ON CONFLICT (user_id) DO NOTHING;
  `);
  console.log('   [PASS] Synthetic User A & User B created in Supabase auth & profiles');

  // DB-TEST-001: Dos Juan Pérez
  await client.query(`
    INSERT INTO public.entities (user_id, entity_type, canonical_name, normalized_name)
    VALUES 
      ('${userA}', 'person', 'Juan Pérez A', 'juan perez a'),
      ('${userA}', 'person', 'Juan Pérez B', 'juan perez b');
  `);
  const juanRes = await client.query(`SELECT id, canonical_name FROM public.entities WHERE user_id = '${userA}' AND normalized_name LIKE 'juan perez%';`);
  if (juanRes.rows.length !== 2) throw new Error('DB-TEST-001 failed: expected 2 Juan entities');
  console.log('   [PASS] DB-TEST-001: Dos Juan Pérez coexisting in Supabase database');

  // DB-TEST-002: Alias duplicado
  const e1 = juanRes.rows[0].id;
  const e2 = juanRes.rows[1].id;
  await client.query(`
    INSERT INTO public.entity_aliases (user_id, entity_id, alias, normalized_alias)
    VALUES 
      ('${userA}', '${e1}', 'Juan', 'juan'),
      ('${userA}', '${e2}', 'Juan', 'juan');
  `);
  console.log('   [PASS] DB-TEST-002: Duplicate alias "juan" allowed on distinct entities in Supabase');

  // DB-TEST-003: Asset deduplicación por SHA-256
  const sha = crypto.randomBytes(32).toString('hex');
  await client.query(`
    INSERT INTO public.assets (user_id, sha256, original_filename, media_kind)
    VALUES ('${userA}', '${sha}', 'test.pdf', 'document');
  `);
  let dupAssetFailed = false;
  try {
    await client.query(`
      INSERT INTO public.assets (user_id, sha256, original_filename, media_kind)
      VALUES ('${userA}', '${sha}', 'test_dup.pdf', 'document');
    `);
  } catch (err) {
    dupAssetFailed = true;
  }
  if (!dupAssetFailed) throw new Error('DB-TEST-003 failed: duplicate sha256 should violate unique index');
  console.log('   [PASS] DB-TEST-003: Asset deduplication by unique (user_id, sha256) enforced');

  // DB-TEST-004: Múltiples ubicaciones de asset
  const assetRow = (await client.query(`SELECT id FROM public.assets WHERE user_id = '${userA}' LIMIT 1;`)).rows[0];
  await client.query(`
    INSERT INTO public.asset_locations (user_id, asset_id, location_type, external_id, drive_file_id)
    VALUES ('${userA}', '${assetRow.id}', 'drive', 'drive_123', 'drive_123');
    INSERT INTO public.asset_locations (user_id, asset_id, location_type, external_id, telegram_file_id)
    VALUES ('${userA}', '${assetRow.id}', 'telegram', 'tg_456', 'tg_456');
  `);
  const locs = await client.query(`SELECT location_type FROM public.asset_locations WHERE asset_id = '${assetRow.id}';`);
  if (locs.rows.length !== 2) throw new Error('DB-TEST-004 failed: expected 2 locations');
  console.log('   [PASS] DB-TEST-004: Multiple locations (drive + telegram) for same asset in Supabase');

  // DB-TEST-005 & DB-TEST-006: Transcripciones múltiples y selección de preferida
  await client.query(`
    INSERT INTO public.source_texts (user_id, asset_id, source_type, source_key, version_no, text_content, provider, model, is_preferred)
    VALUES 
      ('${userA}', '${assetRow.id}', 'transcript', 'audio_src_1', 1, 'Transcripción preliminar motor A', 'test-provider-a', 'test-model-a', false),
      ('${userA}', '${assetRow.id}', 'transcript', 'audio_src_1', 2, 'Transcripción corregida motor B', 'test-provider-b', 'test-model-b', true);
  `);
  const srcTexts = await client.query(`SELECT id, version_no, is_preferred, text_content FROM public.source_texts WHERE user_id = '${userA}' AND source_key = 'audio_src_1' ORDER BY version_no;`);
  if (srcTexts.rows.length !== 2) throw new Error('DB-TEST-005/006 failed');
  if (!srcTexts.rows[1].is_preferred || srcTexts.rows[0].is_preferred) throw new Error('DB-TEST-006 failed: is_preferred mismatch');
  console.log('   [PASS] DB-TEST-005 & DB-TEST-006: Multiple transcript versions coexist with one preferred (persistence fixture)');

  // DB-TEST-007 & DB-TEST-008: Fecha sin hora y rechazo de hora falsa
  await client.query(`
    INSERT INTO public.tasks (user_id, title, due_date, time_known, due_time, due_at)
    VALUES ('${userA}', 'Comprar insumos', '2026-09-01', false, NULL, NULL);
  `);
  let falseTimeFailed = false;
  try {
    await client.query(`
      INSERT INTO public.tasks (user_id, title, due_date, time_known, due_time)
      VALUES ('${userA}', 'Tarea inválida', '2026-09-01', false, '00:00:00');
    `);
  } catch (err) {
    falseTimeFailed = true;
  }
  if (!falseTimeFailed) throw new Error('DB-TEST-008 failed: false 00:00 with time_known=false must be rejected');
  console.log('   [PASS] DB-TEST-007 & DB-TEST-008: Date without time valid; false 00:00 rejected');

  // DB-TEST-009: transition_task_status
  const taskRow = (await client.query(`SELECT id FROM public.tasks WHERE user_id = '${userA}' LIMIT 1;`)).rows[0];
  await client.query(`SELECT public.transition_task_status('${taskRow.id}'::uuid, 'completed', 'user', 'Finalizado con éxito');`);
  const updatedTask = (await client.query(`SELECT status, completed_at, completion_note FROM public.tasks WHERE id = '${taskRow.id}';`)).rows[0];
  if (updatedTask.status !== 'completed' || !updatedTask.completed_at) throw new Error('DB-TEST-009 failed');
  console.log('   [PASS] DB-TEST-009: transition_task_status completed task and populated completed_at');

  // DB-TEST-010: correct_fact
  const memItemId = crypto.randomUUID();
  const factId = crypto.randomUUID();
  await client.query(`
    INSERT INTO public.memory_items (id, user_id, memory_type, title)
    VALUES ('${memItemId}', '${userA}', 'note', 'Nota sobre empleo');
    INSERT INTO public.facts (id, user_id, subject_entity_id, predicate, object_text, polarity, status, source_memory_id)
    VALUES ('${factId}', '${userA}', '${e1}', 'works_at', 'Empresa Vieja', 'positive', 'current', '${memItemId}');
  `);
  await client.query(`
    SELECT public.correct_fact(
      '${factId}'::uuid,
      'Empresa Nueva',
      NULL,
      '${memItemId}'::uuid
    ) as result;
  `);
  const oldFact = (await client.query(`SELECT status FROM public.facts WHERE id = '${factId}';`)).rows[0];
  const newFact = (await client.query(`SELECT object_text, status, supersedes_fact_id FROM public.facts WHERE supersedes_fact_id = '${factId}';`)).rows[0];
  if (oldFact.status !== 'superseded' || newFact.status !== 'current' || newFact.object_text !== 'Empresa Nueva') {
    throw new Error('DB-TEST-010 failed');
  }
  console.log('   [PASS] DB-TEST-010: correct_fact marked old fact superseded and inserted new current fact');

  // DB-TEST-011: assistant_name_history
  await client.query(`SELECT public.set_assistant_name('${userA}'::uuid, 'Victoria 2.0', 'user');`);
  const nameHist = await client.query(`SELECT assistant_name, valid_from, valid_to FROM public.assistant_name_history WHERE user_id = '${userA}' ORDER BY valid_from;`);
  if (nameHist.rows.length < 1) throw new Error('DB-TEST-011 failed: history empty');
  const currentNames = await client.query(`SELECT id FROM public.assistant_name_history WHERE user_id = '${userA}' AND valid_to IS NULL;`);
  if (currentNames.rows.length !== 1) throw new Error('DB-TEST-011 failed: must have exactly 1 active name');
  console.log('   [PASS] DB-TEST-011: assistant_name_history enforces exactly one active name');

  // DB-TEST-012: DELETE prevention on historical tables
  let deleteBlocked = false;
  try {
    await client.query(`DELETE FROM public.assistant_name_history WHERE user_id = '${userA}';`);
  } catch (err) {
    deleteBlocked = true;
  }
  if (!deleteBlocked) throw new Error('DB-TEST-012 failed: DELETE on historical table must be blocked');
  console.log('   [PASS] DB-TEST-012: BEFORE DELETE trigger blocked deletion on historical table in Supabase');

  // DB-TEST-016: claim_due_reminders
  await client.query(`
    INSERT INTO public.reminders (user_id, task_id, reminder_kind, planned_at, status, idempotency_key)
    VALUES ('${userA}', '${taskRow.id}', 'base', now() - interval '1 minute', 'pending', 'rem_test_${userA.slice(0,8)}');
  `);
  const claimed = await client.query(`SELECT * FROM public.claim_due_reminders(10, interval '5 minutes');`);
  if (claimed.rows.length < 1 || claimed.rows[0].status === 'pending') throw new Error('DB-TEST-016 failed');
  console.log('   [PASS] DB-TEST-016: claim_due_reminders claimed due reminder with lease in Supabase');

  // DB-TEST-017 & SEC-TEST-019 & SEC-TEST-020: Multi-tenant RLS Isolation in Supabase
  console.log('\n4. TESTING RLS MULTI-TENANT ISOLATION IN LIVE SUPABASE:');
  await client.query(`SET ROLE authenticated;`);

  // Context: User A
  await client.query(`SET request.jwt.claim.sub = '${userA}';`);
  const userA_tasks = await client.query(`SELECT id, title FROM public.tasks;`);
  if (userA_tasks.rows.length !== 1) throw new Error('User A should see own task');
  
  // Context: User B
  await client.query(`SET request.jwt.claim.sub = '${userB}';`);
  const userB_tasks = await client.query(`SELECT id, title FROM public.tasks;`);
  if (userB_tasks.rows.length !== 0) throw new Error('User B should see 0 tasks (isolated from User A)');
  
  // User B tries to update User A task
  await client.query(`UPDATE public.tasks SET title = 'Hacked' WHERE id = '${taskRow.id}';`);
  await client.query(`SET request.jwt.claim.sub = '${userA}';`);
  const verifyTask = (await client.query(`SELECT title FROM public.tasks WHERE id = '${taskRow.id}';`)).rows[0];
  if (verifyTask.title === 'Hacked') throw new Error('RLS isolation failed: User B updated User A task');

  // Test anon role blocked
  await client.query(`SET ROLE anon;`);
  let anonAccessBlocked = false;
  try {
    await client.query(`SELECT * FROM public.tasks;`);
  } catch (err) {
    anonAccessBlocked = true;
  }
  await client.query(`RESET ROLE;`);
  if (!anonAccessBlocked) throw new Error('Anon role should be blocked from public.tasks');
  console.log('   [PASS] DB-TEST-017 & SEC-TEST-019 & SEC-TEST-020: User A/B RLS Isolation and Anon blocking verified in Supabase');

  // DB-TEST-017B: FK cross-user constraint failure
  let crossUserFKFailed = false;
  try {
    await client.query(`
      INSERT INTO public.reminders (user_id, task_id, reminder_kind, planned_at, status, idempotency_key)
      VALUES ('${userB}', '${taskRow.id}', 'base', now(), 'pending', 'rem_cross_${userB.slice(0,8)}');
    `);
  } catch (err) {
    crossUserFKFailed = true;
  }
  if (!crossUserFKFailed) throw new Error('DB-TEST-017B failed: cross-user FK must fail');
  console.log('   [PASS] DB-TEST-017B: Cross-user composite foreign key violation blocked at DB level in Supabase');

  // DB-TEST-020: Embeddings múltiples en mismo chunk (neutral fixtures)
  const chunkId = crypto.randomUUID();
  await client.query(`
    INSERT INTO public.memory_chunks (id, user_id, memory_id, source_text_id, chunk_index, chunking_version, text_content)
    VALUES ('${chunkId}', '${userA}', '${memItemId}', '${srcTexts.rows[0].id}', 0, 'v1', 'Contenido para embeddings multiples');
    
    INSERT INTO public.embeddings (user_id, chunk_id, provider, model, dimensions, embedding)
    VALUES 
      ('${userA}', '${chunkId}', 'test-provider-a', 'test-model-a', 1536, '[0.1,0.2]'),
      ('${userA}', '${chunkId}', 'test-provider-b', 'test-model-b', 768, '[0.3,0.4]');
  `);
  const embCount = await client.query(`SELECT provider, model, dimensions FROM public.embeddings WHERE chunk_id = '${chunkId}';`);
  if (embCount.rows.length !== 2) throw new Error('DB-TEST-020 failed: chunk should have 2 distinct embeddings');
  console.log('   [PASS] DB-TEST-020: Multiple embeddings from distinct models coexist on same chunk in Supabase (persistence fixture)');

  // DB-TEST-021: Traceability in reports
  const repId = crypto.randomUUID();
  await client.query(`
    INSERT INTO public.reports (id, user_id, requested_channel, query_text, status, result_memory_id)
    VALUES ('${repId}', '${userA}', 'telegram', 'Resumen semanal', 'completed', '${memItemId}');
  `);
  const repTrace = await client.query(`
    SELECT r.id as report_id, m.id as memory_id, m.title
    FROM public.reports r
    JOIN public.memory_items m ON r.result_memory_id = m.id
    WHERE r.id = '${repId}';
  `);
  if (repTrace.rows.length !== 1) throw new Error('DB-TEST-021 failed');
  console.log('   [PASS] DB-TEST-021: Report traceability to result memory demonstrated in Supabase');

  // DB-TEST-022: Asset integrity status transition
  await client.query(`
    UPDATE public.assets SET integrity_status = 'verified' WHERE id = '${assetRow.id}';
    UPDATE public.assets SET integrity_status = 'mismatch' WHERE id = '${assetRow.id}';
  `);
  const finalAsset = (await client.query(`SELECT integrity_status FROM public.assets WHERE id = '${assetRow.id}';`)).rows[0];
  if (finalAsset.integrity_status !== 'mismatch') throw new Error('DB-TEST-022 failed');
  console.log('   [PASS] DB-TEST-022: Asset integrity transition to mismatch verified in Supabase');

  // F0-COMP-ING-IDEMPOTENCY: Idempotencia y Concurrencia sobre register_ingestion
  console.log('\n5. TESTING F0-COMP-ING-IDEMPOTENCY IN REAL SUPABASE:');
  const ikey = `telegram:primary:${Date.now()}`;
  const r1 = (await client.query(`
    SELECT public.register_ingestion(
      '${userA}'::uuid, 'telegram', 'text', '${ikey}', now(), 'evt_1', 999888777, 1234, 1001, 555, NULL, NULL, NULL, '{}'::jsonb
    ) as res;
  `)).rows[0].res;
  
  const r2 = (await client.query(`
    SELECT public.register_ingestion(
      '${userA}'::uuid, 'telegram', 'text', '${ikey}', now(), 'evt_1', 999888777, 1234, 1001, 555, NULL, NULL, NULL, '{}'::jsonb
    ) as res;
  `)).rows[0].res;

  const parsedR1 = typeof r1 === 'string' ? JSON.parse(r1) : r1;
  const parsedR2 = typeof r2 === 'string' ? JSON.parse(r2) : r2;

  if (parsedR1.is_duplicate !== false || parsedR2.is_duplicate !== true || parsedR1.ingestion_id !== parsedR2.ingestion_id) {
    throw new Error('F0-COMP-ING-IDEMPOTENCY failed');
  }
  
  const totalIngestions = (await client.query(`SELECT count(*)::int as count FROM public.ingestions WHERE user_id = '${userA}' AND idempotency_key = '${ikey}';`)).rows[0].count;
  if (totalIngestions !== 1) throw new Error('Expected exactly 1 persistent ingestion row');
  console.log('   [PASS] F0-COMP-ING-IDEMPOTENCY: Same key produced single persisted row, replay returned duplicate without error');

  await client.end();
  console.log('\n======================================================================');
  console.log('ALL REAL SUPABASE RUNTIME TESTS COMPLETED SUCCESSFULLY (100% PASS)');
  console.log('======================================================================');
}

runLiveSupabaseTests().catch(err => {
  console.error('FATAL REAL SUPABASE RUNTIME ERROR:', err);
  process.exit(1);
});
