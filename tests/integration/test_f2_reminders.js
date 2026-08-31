/**
 * F2 Reminder Integration + Resilience Suite
 * Baseline: SVIA-DOCSET-V1-RC1
 * Target: real Supabase Local DEV after migration 12.
 * Synthetic data only. No PROD.
 */
const { Client } = require('pg');
const crypto = require('crypto');

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

async function main() {
  console.log('======================================================================');
  console.log('F2 REMINDERS — INTEGRATION + RESILIENCE');
  console.log('Target: 127.0.0.1:54322 / Supabase Local DEV');
  console.log('======================================================================');

  const db = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
  });
  await db.connect();

  const tables = await db.query(`
    SELECT count(*)::int AS c
    FROM information_schema.tables
    WHERE table_schema='public' AND table_type='BASE TABLE';
  `);
  assert(tables.rows[0].c === 25, `Expected 25 product tables, got ${tables.rows[0].c}`);

  const userA = crypto.randomUUID();
  const userB = crypto.randomUUID();
  const chatA = Math.floor(1000000 + Math.random() * 8000000);
  const chatB = Math.floor(1000000 + Math.random() * 8000000);

  await db.query(`
    INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES
      ($1,'authenticated','authenticated',$3,'{"provider":"email","providers":["email"]}','{}',now(),now()),
      ($2,'authenticated','authenticated',$4,'{"provider":"email","providers":["email"]}','{}',now(),now());
  `, [userA, userB, `f2_a_${userA.slice(0,8)}@dev.test`, `f2_b_${userB.slice(0,8)}@dev.test`]);

  await db.query(`
    INSERT INTO public.profiles (id, display_name, timezone, locale)
    VALUES
      ($1,'F2 User A','America/Argentina/Buenos_Aires','es-AR'),
      ($2,'F2 User B','America/Argentina/Buenos_Aires','es-AR');
  `, [userA, userB]);

  await db.query(`
    INSERT INTO public.user_settings (
      user_id, assistant_name, authorized_telegram_chat_id,
      default_reminder_minutes_before, quiet_hours_enabled,
      rest_mode_enabled, critical_can_break_silence
    )
    VALUES
      ($1,'F2A',$3,180,false,false,false),
      ($2,'F2B',$4,180,false,false,false);
  `, [userA, userB, chatA, chatB]);

  async function createTask(title, dueAtSql, timeKnown=true, status='pending') {
    const key = `task:f2:${crypto.randomUUID()}`;
    if (timeKnown) {
      const r = await db.query(`
        INSERT INTO public.tasks (
          user_id,title,due_date,due_time,due_timezone,due_at,time_known,status,idempotency_key
        )
        VALUES (
          $1,$2,
          ((${dueAtSql})::timestamptz AT TIME ZONE 'America/Argentina/Buenos_Aires')::date,
          ((${dueAtSql})::timestamptz AT TIME ZONE 'America/Argentina/Buenos_Aires')::time,
          'America/Argentina/Buenos_Aires',
          (${dueAtSql})::timestamptz,
          true,$3,$4
        )
        RETURNING id,due_at;
      `,[userA,title,status,key]);
      return r.rows[0];
    }
    const r = await db.query(`
      INSERT INTO public.tasks (
        user_id,title,due_date,due_time,due_at,time_known,status,idempotency_key
      )
      VALUES (
        $1,$2,
        (now() AT TIME ZONE 'America/Argentina/Buenos_Aires' + interval '2 days')::date,
        NULL,NULL,false,$3,$4
      )
      RETURNING id,due_at;
    `,[userA,title,status,key]);
    return r.rows[0];
  }

  // REM-001/002 + DB-TEST-014: default persistent reminder ~3h before and idempotent.
  const taskKnown = await createTask('F2 base reminder', "now() + interval '1 day'");
  const p1 = (await db.query(
    `SELECT public.plan_task_reminders($1::uuid,$2::uuid,'[]'::jsonb) AS r;`,
    [userA, taskKnown.id]
  )).rows[0].r;
  assert(p1.ok === true && Number(p1.created_count) === 1, 'REM-001/002 planning failed');

  const base = (await db.query(`
    SELECT * FROM public.reminders
    WHERE user_id=$1 AND task_id=$2 AND reminder_kind='base';
  `,[userA,taskKnown.id])).rows[0];
  assert(base, 'REM-001 reminder not persisted');
  const deltaMinutes = (new Date(taskKnown.due_at) - new Date(base.planned_at)) / 60000;
  assert(Math.abs(deltaMinutes - 180) < 0.2, `REM-002 expected 180 minutes, got ${deltaMinutes}`);

  const replay = (await db.query(
    `SELECT public.plan_task_reminders($1::uuid,$2::uuid,'[]'::jsonb) AS r;`,
    [userA,taskKnown.id]
  )).rows[0].r;
  const baseCount = (await db.query(
    `SELECT count(*)::int AS c FROM public.reminders WHERE task_id=$1 AND reminder_kind='base';`,
    [taskKnown.id]
  )).rows[0].c;
  assert(baseCount === 1 && Number(replay.existing_count) >= 1, 'DB-TEST-014 planning replay duplicated');
  console.log('[PASS] REM-001/002 + DB-TEST-014');

  // Date without time: no invented 00:00 / planned timestamp.
  const taskNoTime = await createTask('F2 date only', null, false);
  const noTime = (await db.query(
    `SELECT public.plan_task_reminders($1::uuid,$2::uuid,'[]'::jsonb) AS r;`,
    [userA,taskNoTime.id]
  )).rows[0].r;
  const noTimeCount = (await db.query(
    `SELECT count(*)::int AS c FROM public.reminders WHERE task_id=$1;`,
    [taskNoTime.id]
  )).rows[0].c;
  assert(noTimeCount === 0, 'Date-only task got an invented reminder clock');
  assert((noTime.skipped || []).includes('default_reminder_not_created_time_unknown'),
    'Date-only no-reminder decision not explicit');
  console.log('[PASS] temporal rule: no invented time');

  // REM-003/004/005 capability: upstream proposal may add reminder but cannot authorize critical bypass.
  const aiAt = new Date(new Date(taskKnown.due_at).getTime() - 10*60*1000).toISOString();
  await db.query(
    `SELECT public.plan_task_reminders($1::uuid,$2::uuid,$3::jsonb);`,
    [userA,taskKnown.id,JSON.stringify([{kind:'ai',planned_at:aiAt,reason:'near_call',can_break_silence:true}])]
  );
  const aiRem = (await db.query(`
    SELECT can_break_silence FROM public.reminders
    WHERE task_id=$1 AND reminder_kind='ai' ORDER BY created_at DESC LIMIT 1;
  `,[taskKnown.id])).rows[0];
  assert(aiRem && aiRem.can_break_silence === false, 'AI proposal escalated critical bypass');
  console.log('[PASS] REM-003/004/005 capability + REM-008 authority boundary');

  // Cross-user task ownership.
  let crossBlocked = false;
  try {
    await db.query(
      `SELECT public.plan_task_reminders($1::uuid,$2::uuid,'[]'::jsonb);`,
      [userB,taskKnown.id]
    );
  } catch (_) { crossBlocked = true; }
  assert(crossBlocked, 'Cross-user reminder planning allowed');
  console.log('[PASS] cross-user planning blocked');

  // Helper to insert due manual reminder.
  async function dueReminder(label, canBreak=false) {
    return (await db.query(`
      INSERT INTO public.reminders (
        user_id,task_id,reminder_kind,planned_at,status,can_break_silence,idempotency_key
      )
      VALUES ($1,$2,'manual',now()-interval '1 minute','pending',$3,$4)
      RETURNING id;
    `,[userA,taskKnown.id,canBreak,`reminder:f2:${label}:${crypto.randomUUID()}`])).rows[0];
  }

  // WF-TEST-013 / DB-TEST-015 / REM-009/011.
  const sendRem = await dueReminder('send-once');
  const claim = (await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '5 minutes') WHERE id=$1;`,
    [sendRem.id]
  )).rows[0];
  assert(claim && claim.lease_token, 'WF-TEST-013 due reminder not claimed');

  const doubleClaim = (await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '5 minutes') WHERE id=$1;`,
    [sendRem.id]
  )).rows;
  assert(doubleClaim.length === 0, 'WF-TEST-013 double claim occurred');

  const attempt = Number(claim.attempt_number);
  const dkey = `delivery:${sendRem.id}:${attempt}`;
  await db.query(`
    SELECT public.record_notification_result(
      $1::uuid,$2::uuid,'telegram',$3::integer,$4::text,'attempting',
      NULL,NULL,NULL,'{}'::jsonb,NULL,$5::uuid
    );
  `,[sendRem.id,userA,attempt,dkey,claim.lease_token]);
  await db.query(`
    SELECT public.record_notification_result(
      $1::uuid,$2::uuid,'telegram',$3::integer,$4::text,'sent',
      'synthetic-message',NULL,NULL,'{"synthetic":true}'::jsonb,NULL,$5::uuid
    );
  `,[sendRem.id,userA,attempt,dkey,claim.lease_token]);

  const replaySent = (await db.query(`
    SELECT public.record_notification_result(
      $1::uuid,$2::uuid,'telegram',$3::integer,$4::text,'sent',
      'synthetic-message',NULL,NULL,'{"synthetic":true}'::jsonb,NULL,NULL
    ) AS r;
  `,[sendRem.id,userA,attempt,dkey])).rows[0].r;
  assert(replaySent.is_duplicate === true, 'DB-TEST-015 final replay not idempotent');

  const delCount = (await db.query(
    `SELECT count(*)::int AS c FROM public.notification_deliveries WHERE reminder_id=$1;`,
    [sendRem.id]
  )).rows[0].c;
  assert(delCount === 1, 'DB-TEST-015 duplicate delivery row');

  const reclaimSent = (await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '5 minutes') WHERE id=$1;`,
    [sendRem.id]
  )).rows;
  assert(reclaimSent.length === 0, 'REM-011 sent reminder reclaimed');
  console.log('[PASS] WF-TEST-013 + DB-TEST-015 + REM-009/011');

  // WF-TEST-014 / DB-TEST-016: crash after claim BEFORE external attempt.
  const crashRem = await dueReminder('crash-before-attempt');
  const crashClaim = (await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '1 millisecond') WHERE id=$1;`,
    [crashRem.id]
  )).rows[0];
  assert(crashClaim, 'Crash recovery setup failed');
  await db.query(`SELECT pg_sleep(0.02);`);
  await db.query(`SELECT public.release_expired_reminder_leases();`);
  const crashState = (await db.query(
    `SELECT status,next_retry_at,lease_token,lease_expires_at,retry_count FROM public.reminders WHERE id=$1;`,
    [crashRem.id]
  )).rows[0];
  assert(crashState.status==='retry' && crashState.next_retry_at && crashState.lease_token===null,
    'DB-TEST-016 pure worker crash not recovered');
  const crashReclaim = (await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '5 minutes') WHERE id=$1;`,
    [crashRem.id]
  )).rows[0];
  assert(crashReclaim, 'WF-TEST-014 recovered reminder not claimable');
  console.log('[PASS] WF-TEST-014 + DB-TEST-016');

  // WF-TEST-015 / DB-TEST-016B: explicit unknown -> quarantine, no blind resend.
  const unknownRem = await dueReminder('unknown');
  const uc = (await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '5 minutes') WHERE id=$1;`,
    [unknownRem.id]
  )).rows[0];
  const ua = Number(uc.attempt_number);
  const uk = `delivery:${unknownRem.id}:${ua}`;
  await db.query(`
    SELECT public.record_notification_result(
      $1::uuid,$2::uuid,'telegram',$3::integer,$4::text,'attempting',
      NULL,NULL,NULL,'{}'::jsonb,NULL,$5::uuid
    );
  `,[unknownRem.id,userA,ua,uk,uc.lease_token]);
  await db.query(`
    SELECT public.record_notification_result(
      $1::uuid,$2::uuid,'telegram',$3::integer,$4::text,'unknown',
      NULL,'NETWORK_RESULT_UNKNOWN','Synthetic lost response',
      '{"synthetic":true}'::jsonb,NULL,$5::uuid
    );
  `,[unknownRem.id,userA,ua,uk,uc.lease_token]);

  const us = (await db.query(
    `SELECT status,next_retry_at,lease_token FROM public.reminders WHERE id=$1;`,
    [unknownRem.id]
  )).rows[0];
  assert(us.status==='retry' && us.next_retry_at===null && us.lease_token===null,
    'Unknown not quarantined');
  const uclaim = (await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '5 minutes') WHERE id=$1;`,
    [unknownRem.id]
  )).rows;
  assert(uclaim.length===0,'WF-TEST-015 UNKNOWN blindly reclaimed');
  console.log('[PASS] WF-TEST-015 + DB-TEST-016B');

  // Resilience: crash AFTER attempt starts => delivery becomes unknown and quarantine.
  const midRem = await dueReminder('crash-after-attempt');
  const mc = (await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '1 millisecond') WHERE id=$1;`,
    [midRem.id]
  )).rows[0];
  const ma = Number(mc.attempt_number);
  const mk = `delivery:${midRem.id}:${ma}`;
  await db.query(`
    SELECT public.record_notification_result(
      $1::uuid,$2::uuid,'telegram',$3::integer,$4::text,'attempting',
      NULL,NULL,NULL,'{}'::jsonb,NULL,$5::uuid
    );
  `,[midRem.id,userA,ma,mk,mc.lease_token]);
  await db.query(`SELECT pg_sleep(0.02);`);
  await db.query(`SELECT public.release_expired_reminder_leases();`);
  const md = (await db.query(
    `SELECT status FROM public.notification_deliveries WHERE reminder_id=$1 AND attempt_number=$2;`,
    [midRem.id,ma]
  )).rows[0];
  const mr = (await db.query(
    `SELECT status,next_retry_at FROM public.reminders WHERE id=$1;`,
    [midRem.id]
  )).rows[0];
  assert(md.status==='unknown' && mr.status==='retry' && mr.next_retry_at===null,
    'Crash after attempt start was not classified UNKNOWN');
  console.log('[PASS] mid-attempt crash -> UNKNOWN quarantine');

  // WF-TEST-016: quiet hours retain a normal reminder.
  await db.query(`
    UPDATE public.user_settings
    SET quiet_hours_enabled=true,
        quiet_start_time=((now() AT TIME ZONE 'America/Argentina/Buenos_Aires')-interval '1 hour')::time,
        quiet_end_time=((now() AT TIME ZONE 'America/Argentina/Buenos_Aires')+interval '1 hour')::time,
        rest_mode_enabled=false,
        critical_can_break_silence=false
    WHERE user_id=$1;
  `,[userA]);

  const qrem=await dueReminder('quiet-normal',false);
  const qc=(await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '5 minutes') WHERE id=$1;`,
    [qrem.id]
  )).rows[0];
  const qp=(await db.query(
    `SELECT public.evaluate_reminder_delivery_policy($1::uuid,$2::uuid) AS p;`,
    [qrem.id,qc.lease_token]
  )).rows[0].p;
  assert(qp.action==='suppress' && String(qp.reason).includes('quiet'),
    `WF-TEST-016 expected quiet suppression, got ${JSON.stringify(qp)}`);
  await db.query(
    `SELECT public.apply_reminder_dispatch_decision($1::uuid,$2::uuid,'suppress',$3::timestamptz,$4::text);`,
    [qrem.id,qc.lease_token,qp.suppressed_until,qp.reason]
  );
  console.log('[PASS] WF-TEST-016 / REM-007');

  // WF-TEST-017: critical bypass requires BOTH reminder flag + user authorization.
  const crem=await dueReminder('critical',true);
  let cc=(await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '5 minutes') WHERE id=$1;`,
    [crem.id]
  )).rows[0];
  let cp=(await db.query(
    `SELECT public.evaluate_reminder_delivery_policy($1::uuid,$2::uuid) AS p;`,
    [crem.id,cc.lease_token]
  )).rows[0].p;
  assert(cp.action==='suppress','Reminder flag alone bypassed silence');
  await db.query(
    `SELECT public.apply_reminder_dispatch_decision($1::uuid,$2::uuid,'suppress',$3::timestamptz,$4::text);`,
    [crem.id,cc.lease_token,cp.suppressed_until,cp.reason]
  );
  await db.query(`UPDATE public.user_settings SET critical_can_break_silence=true WHERE user_id=$1;`, [userA]);
  await db.query(`
    UPDATE public.reminders
      SET suppressed_until=NULL,suppression_reason=NULL,planned_at=now()-interval '1 minute'
      WHERE id=$1;
  `, [crem.id]);
  cc=(await db.query(
    `SELECT * FROM public.claim_due_reminders(100,interval '5 minutes') WHERE id=$1;`,
    [crem.id]
  )).rows[0];
  cp=(await db.query(
    `SELECT public.evaluate_reminder_delivery_policy($1::uuid,$2::uuid) AS p;`,
    [crem.id,cc.lease_token]
  )).rows[0].p;
  assert(cp.action==='send' && cp.critical_authorized===true,
    'Doubly-authorized critical reminder did not pass');
  console.log('[PASS] WF-TEST-017 / REM-008');

  // REM-006 / WF-REM-004: deterministic follow-up + anti-spam.
  const follow = await createTask('F2 waiting confirmation', null, false, 'waiting_confirmation');
  const before=(await db.query(
    `SELECT * FROM public.list_followup_candidates() WHERE task_id=$1;`,
    [follow.id]
  )).rows[0];
  assert(before,'REM-006 waiting_confirmation missing from candidates');
  await db.query(
    `SELECT public.plan_task_reminders($1::uuid,$2::uuid,$3::jsonb);`,
    [userA,follow.id,JSON.stringify([{kind:'followup',planned_at:new Date().toISOString(),reason:'followup_waiting_confirmation'}])]
  );
  const after=(await db.query(
    `SELECT * FROM public.list_followup_candidates() WHERE task_id=$1;`,
    [follow.id]
  )).rows;
  assert(after.length===0,'WF-REM-004 anti-spam failed');
  console.log('[PASS] REM-006 + follow-up anti-spam');

  // Least privilege: authenticated cannot call worker functions.
  await db.query(`SET ROLE authenticated;`);
  await db.query(`SELECT pg_catalog.set_config('request.jwt.claim.sub',$1,false);`,[userA]);
  let denied=false;
  try { await db.query(`SELECT * FROM public.claim_due_reminders();`); }
  catch (_) { denied=true; }
  await db.query(`RESET ROLE;`);
  assert(denied,'Authenticated role can execute worker claim RPC');
  console.log('[PASS] worker RPCs denied to authenticated');

  const snap=(await db.query(`SELECT public.reminder_watchdog_snapshot() AS s;`)).rows[0].s;
  console.log('[INFO] watchdog snapshot:',snap);

  await db.end();
  console.log('======================================================================');
  console.log('F2 REMINDER SUITE: PASS');
  console.log('DB-TEST-014 PASS');
  console.log('DB-TEST-015 PASS');
  console.log('DB-TEST-016 PASS');
  console.log('DB-TEST-016B PASS');
  console.log('WF-TEST-013 PASS');
  console.log('WF-TEST-014 PASS');
  console.log('WF-TEST-015 PASS');
  console.log('WF-TEST-016 PASS');
  console.log('WF-TEST-017 PASS');
  console.log('======================================================================');
}

main().catch((err)=>{
  console.error('F2 REMINDER SUITE: FAIL');
  console.error(err?.stack || err);
  process.exit(1);
});
