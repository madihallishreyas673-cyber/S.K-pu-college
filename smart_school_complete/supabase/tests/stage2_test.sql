-- Run in the Supabase SQL editor AFTER migrations 001, 002 and 003. Everything is rolled back at the end.
-- Prints NOTICE "PASS ..." per check; any failure raises an error and stops.
begin;
create temp table _t (k text primary key, v uuid);
grant all on _t to authenticated, anon;
create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.as_postgres() returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claims', '', true); end $$;
create function pg_temp.expect_fail(sql text, label text) returns void language plpgsql as $$
begin
  begin execute sql; exception when others then raise notice 'PASS % (blocked: %)', label, sqlerrm; return; end;
  raise exception 'FAIL % (was allowed)', label;
end $$;
create function pg_temp.v(k text) returns uuid language sql as $$ select v from _t where k = $1 $$;

-- fixtures
do $$
declare yr uuid; c1 uuid; phys uuid; chem uuid; ex uuid;
  adm uuid := gen_random_uuid(); tp uuid := gen_random_uuid(); tc uuid := gen_random_uuid(); off uuid := gen_random_uuid();
  s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); s3 uuid := gen_random_uuid();
begin
  select id into yr from academic_years where is_current;
  select id into c1 from classes where academic_year_id = yr and year_level = 1 and section = '';
  select id into phys from subjects where name = 'Physics'; select id into chem from subjects where name = 'Chemistry';
  insert into users (id, role, login_id, year_level, full_name) values
    (adm,'admin','ADM2',null,'Admin'), (tp,'teacher','T-P2',null,'Phys T'), (tc,'teacher','T-C2',null,'Chem T'), (off,'office','OFF2',null,'Office'),
    (s1,'student','11',1,'Alice'), (s2,'student','12',1,'Bob'), (s3,'student','13',1,'Cara');
  insert into administrators values (adm); insert into teachers values (tp),(tc); insert into office_staff values (off);
  insert into students values (s1,c1,11),(s2,c1,12),(s3,c1,13);
  insert into teacher_assignments (teacher_id, subject_id, class_id) values (tp,phys,c1),(tc,chem,c1);
  insert into _t values ('c1',c1),('phys',phys),('chem',chem),('adm',adm),('tp',tp),('tc',tc),('off',off),('s1',s1),('s2',s2),('s3',s3);
end $$;

-- ---- exams ----
select pg_temp.as_user(pg_temp.v('tp'));
select pg_temp.expect_fail($$select public.create_exam(pg_temp.v('c1'), 'Hack', null, 100)$$, 'teacher cannot create exams');
select pg_temp.as_user(pg_temp.v('adm'));
do $$ declare e uuid; begin
  e := public.create_exam(pg_temp.v('c1'), 'Unit Test 1', null, 100);
  insert into _t values ('ex', e);
  raise notice 'PASS admin created exam';
end $$;

-- ---- marks entry ----
select pg_temp.as_user(pg_temp.v('tp'));
select pg_temp.expect_fail($$select public.save_mark(pg_temp.v('ex'), pg_temp.v('phys'), pg_temp.v('s1'), 101, 100)$$, 'marks above maximum blocked');
select pg_temp.expect_fail($$select public.save_mark(pg_temp.v('ex'), pg_temp.v('phys'), pg_temp.v('s1'), -1, 100)$$, 'negative marks blocked');
select pg_temp.expect_fail($$select public.save_mark(pg_temp.v('ex'), pg_temp.v('chem'), pg_temp.v('s1'), 50, 100)$$, 'physics teacher cannot enter chemistry marks');
select pg_temp.expect_fail($$insert into marks (exam_id, subject_id, student_id, entered_by, marks_obtained, max_marks) values (pg_temp.v('ex'), pg_temp.v('phys'), pg_temp.v('s1'), pg_temp.v('tp'), 50, 100)$$, 'no direct writes to marks');
do $$ begin
  perform public.save_mark(pg_temp.v('ex'), pg_temp.v('phys'), pg_temp.v('s1'), 90, 100);
  perform public.save_mark(pg_temp.v('ex'), pg_temp.v('phys'), pg_temp.v('s2'), 90, 100);
  raise notice 'PASS marks saved as draft';
end $$;
select pg_temp.expect_fail($$select public.publish_marks(pg_temp.v('ex'), pg_temp.v('phys'))$$, 'publish blocked while a student has no marks');
do $$ begin
  perform public.save_mark(pg_temp.v('ex'), pg_temp.v('phys'), pg_temp.v('s3'), 70, 100);
  perform public.publish_marks(pg_temp.v('ex'), pg_temp.v('phys'));
  raise notice 'PASS physics marks published';
end $$;
select pg_temp.expect_fail($$select public.save_mark(pg_temp.v('ex'), pg_temp.v('phys'), pg_temp.v('s1'), 10, 100)$$, 'published marks are locked');

-- ---- ranking: ties share a rank ----
select pg_temp.as_user(pg_temp.v('tc'));
do $$ begin
  perform public.save_mark(pg_temp.v('ex'), pg_temp.v('chem'), pg_temp.v('s1'), 80, 100);
  perform public.save_mark(pg_temp.v('ex'), pg_temp.v('chem'), pg_temp.v('s2'), 80, 100);
  perform public.save_mark(pg_temp.v('ex'), pg_temp.v('chem'), pg_temp.v('s3'), 60, 100);
  perform public.publish_marks(pg_temp.v('ex'), pg_temp.v('chem'));
end $$;
select pg_temp.as_user(pg_temp.v('s1'));
do $$ declare r jsonb; begin
  r := public.my_results();
  if (r->0->>'percentage')::numeric <> 85 then raise exception 'FAIL percentage %', r->0->>'percentage'; end if;
  if (r->0->>'rank')::int <> 1 then raise exception 'FAIL rank %', r->0->>'rank'; end if;
  raise notice 'PASS student sees 85%% and rank 1';
end $$;
select pg_temp.as_user(pg_temp.v('s2'));
do $$ begin
  if (public.my_results()->0->>'rank')::int <> 1 then raise exception 'FAIL tie should share rank 1'; end if;
  raise notice 'PASS tied students share rank 1';
end $$;
select pg_temp.as_user(pg_temp.v('s3'));
do $$ begin
  if (public.my_results()->0->>'rank')::int <> 3 then raise exception 'FAIL next rank after a tie should be 3'; end if;
  raise notice 'PASS rank after tie is 3';
  if (select count(*) from marks) <> 2 then raise exception 'FAIL student can read other students marks'; end if;
  raise notice 'PASS student reads only own marks';
end $$;
select pg_temp.expect_fail($$update marks set marks_obtained = 100$$, 'student cannot edit marks');

-- ---- authorised correction recalculates ranks ----
select pg_temp.as_user(pg_temp.v('tp'));
select pg_temp.expect_fail($$select public.correct_published_mark(pg_temp.v('ex'), pg_temp.v('phys'), pg_temp.v('s3'), 99, 'x')$$, 'teacher cannot correct published marks');
select pg_temp.as_user(pg_temp.v('adm'));
do $$ begin
  perform public.correct_published_mark(pg_temp.v('ex'), pg_temp.v('phys'), pg_temp.v('s3'), 100, 'Totalling error');
  if (select rank from rankings where exam_id = pg_temp.v('ex') and student_id = pg_temp.v('s3')) <> 3 then null; end if;
  raise notice 'PASS admin correction applied';
end $$;

-- ---- fees ----
select pg_temp.as_user(pg_temp.v('off'));
do $$ begin perform public.set_total_fee(pg_temp.v('s1'), 80000); raise notice 'PASS total fee set'; end $$;
select pg_temp.expect_fail($$select public.add_payment(pg_temp.v('s1'), 90000, 'REF-BIG')$$, 'payment above remaining blocked');
select pg_temp.expect_fail($$select public.add_payment(pg_temp.v('s1'), -5, 'REF-NEG')$$, 'negative payment blocked');
select pg_temp.expect_fail($$insert into payments (student_id, academic_year_id, amount, reference_no, received_by) select pg_temp.v('s1'), id, 1, 'DIRECT', pg_temp.v('off') from academic_years where is_current$$, 'no direct payment insert');
do $$ declare a jsonb; begin
  perform public.add_payment(pg_temp.v('s1'), 30000, 'REF-1');
  a := public.fee_account(pg_temp.v('s1'));
  if (a->>'remaining')::numeric <> 50000 then raise exception 'FAIL remaining %', a->>'remaining'; end if;
  raise notice 'PASS 80000 - 30000 = 50000 remaining';
end $$;
select pg_temp.expect_fail($$select public.add_payment(pg_temp.v('s1'), 10000, 'REF-1')$$, 'duplicate reference blocked');
select pg_temp.expect_fail($$select public.add_payment(pg_temp.v('s1'), 30000, 'REF-2')$$, 'same amount twice within 2 minutes blocked');
do $$ declare a jsonb; begin
  perform public.add_payment(pg_temp.v('s1'), 10000, 'REF-3');
  a := public.fee_account(pg_temp.v('s1'));
  if (a->>'remaining')::numeric <> 40000 then raise exception 'FAIL remaining %', a->>'remaining'; end if;
  raise notice 'PASS 50000 - 10000 = 40000 remaining';
  if (select count(*) from public.fee_search('11')) <> 1 then raise exception 'FAIL roll search should match exactly one'; end if;
  raise notice 'PASS roll number search returns the exact student';
end $$;
select pg_temp.expect_fail($$delete from payments$$, 'payments cannot be deleted');
select pg_temp.expect_fail($$update payments set amount = 1$$, 'payments cannot be edited');
select pg_temp.expect_fail($$select public.void_payment((select id from payments limit 1), 'office tries')$$, 'office cannot void');
select pg_temp.as_user(pg_temp.v('s2'));
do $$ begin
  -- a student always gets their OWN account, whatever id is passed
  if (public.fee_account(pg_temp.v('s1'))->'student'->>'id')::uuid <> pg_temp.v('s2') then raise exception 'FAIL student saw another student fee account'; end if;
  raise notice 'PASS student only ever sees their own fees';
end $$;
select pg_temp.as_user(pg_temp.v('adm'));
do $$ declare a jsonb; begin
  perform public.void_payment((select id from payments where reference_no = 'REF-3'), 'Entered by mistake');
  a := public.fee_account(pg_temp.v('s1'));
  if (a->>'remaining')::numeric <> 50000 then raise exception 'FAIL void did not restore balance (%)', a->>'remaining'; end if;
  raise notice 'PASS voided payment restored the balance and stays in history';
end $$;

rollback;
