-- Run in the Supabase SQL editor AFTER both migrations. Everything is rolled back at the end.
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

-- ---- fixtures (as table owner) ----
do $$
declare yr uuid; c1 uuid; c2 uuid; phys uuid; chem uuid;
        adm uuid := gen_random_uuid(); tp uuid := gen_random_uuid(); tc uuid := gen_random_uuid();
        s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); s3 uuid := gen_random_uuid(); off uuid := gen_random_uuid();
begin
  select id into yr from academic_years where is_current;
  select id into c1 from classes where academic_year_id = yr and year_level = 1 and section = '';
  select id into c2 from classes where academic_year_id = yr and year_level = 2 and section = '';
  select id into phys from subjects where name = 'Physics'; select id into chem from subjects where name = 'Chemistry';
  insert into users (id, role, login_id, year_level, full_name) values
    (adm,'admin','ADM1',null,'Admin One'), (tp,'teacher','T-PHY',null,'Physics Teacher'), (tc,'teacher','T-CHE',null,'Chem Teacher'),
    (s1,'student','1',1,'Student One'), (s2,'student','2',1,'Student Two'), (s3,'student','1',2,'Other Year Student'),
    (off,'office','OFF1',null,'Office One');
  insert into administrators values (adm); insert into teachers values (tp),(tc); insert into office_staff values (off);
  insert into students values (s1,c1,1),(s2,c1,2),(s3,c2,1);
  insert into teacher_assignments (teacher_id, subject_id, class_id) values (tp,phys,c1),(tc,chem,c1);
  insert into _t values ('c1',c1),('phys',phys),('chem',chem),('adm',adm),('tp',tp),('tc',tc),('s1',s1),('s2',s2),('s3',s3),('off',off),('c2',c2);
end $$;

create function pg_temp.v(k text) returns uuid language sql as $$ select v from _t where k = $1 $$;

-- ---- 1. teacher submits attendance for own subject ----
select pg_temp.as_user(pg_temp.v('tp'));
do $$ declare sid uuid; begin
  sid := public.submit_attendance(pg_temp.v('c1'), pg_temp.v('phys'), public.school_today(), 1::smallint,
    jsonb_build_array(jsonb_build_object('student_id', pg_temp.v('s1'), 'status','P'),
                      jsonb_build_object('student_id', pg_temp.v('s2'), 'status','A')));
  insert into _t values ('ses', sid);
  raise notice 'PASS teacher submitted attendance';
end $$;
select pg_temp.expect_fail($$select public.submit_attendance(pg_temp.v('c1'), pg_temp.v('phys'), public.school_today(), 1::smallint,
  jsonb_build_array(jsonb_build_object('student_id', pg_temp.v('s1'),'status','P'), jsonb_build_object('student_id', pg_temp.v('s2'),'status','P')))$$,
  'duplicate session blocked');
select pg_temp.expect_fail($$select public.submit_attendance(pg_temp.v('c1'), pg_temp.v('chem'), public.school_today(), 1::smallint,
  jsonb_build_array(jsonb_build_object('student_id', pg_temp.v('s1'),'status','P'), jsonb_build_object('student_id', pg_temp.v('s2'),'status','P')))$$,
  'physics teacher cannot mark chemistry');
select pg_temp.expect_fail($$select public.submit_attendance(pg_temp.v('c1'), pg_temp.v('phys'), public.school_today() + 1, 1::smallint, '[]'::jsonb)$$, 'future date blocked');
select pg_temp.expect_fail($$select public.submit_attendance(pg_temp.v('c1'), pg_temp.v('phys'), public.school_today() - 1, 1::smallint,
  jsonb_build_array(jsonb_build_object('student_id', pg_temp.v('s1'),'status','P')))$$, 'incomplete roster blocked');
select pg_temp.expect_fail($$insert into attendance_records values (pg_temp.v('ses'), pg_temp.v('s1'), 'P')$$, 'no direct writes to attendance');
select pg_temp.expect_fail($$update attendance_records set status = 'P'$$, 'no direct updates to attendance');

-- ---- 2. corrections need a reason and leave an audit row ----
select pg_temp.expect_fail($$select public.correct_attendance(pg_temp.v('ses'), pg_temp.v('s2'), 'P', '')$$, 'correction without reason blocked');
do $$ begin
  perform public.correct_attendance(pg_temp.v('ses'), pg_temp.v('s2'), 'P', 'Marked absent by mistake');
  raise notice 'PASS correction applied';
end $$;
do $$ begin
  if (select count(*) from attendance_audit where session_id = pg_temp.v('ses') and old_status = 'A' and new_status = 'P') <> 1 then
    raise exception 'FAIL audit row missing'; end if;
  raise notice 'PASS correction audit row written';
end $$;
select pg_temp.expect_fail($$delete from attendance_audit$$, 'audit history cannot be deleted');

-- ---- 3. students see only themselves ----
select pg_temp.as_user(pg_temp.v('s1'));
do $$ declare j jsonb; begin
  j := public.attendance_summary();
  if (j->'overall'->>'conducted')::int <> 1 or (j->'overall'->>'percentage')::numeric <> 100 then raise exception 'FAIL own summary wrong: %', j; end if;
  raise notice 'PASS student sees own summary';
  if (select count(*) from attendance_records) <> 1 then raise exception 'FAIL student sees others'' records'; end if;
  raise notice 'PASS student cannot read other students'' records';
  if (select count(*) from users) <> 1 then raise exception 'FAIL student can list users'; end if;
  raise notice 'PASS student cannot list other users';
end $$;
select pg_temp.expect_fail($$select public.attendance_summary(pg_temp.v('s2'))$$, 'student cannot view classmate summary');
select pg_temp.expect_fail($$select * from credentials$$, 'credentials unreachable');
select pg_temp.expect_fail($$select * from registration_secrets$$, 'registration PINs unreachable');
select pg_temp.expect_fail($$select * from public.class_attendance_report(pg_temp.v('c1'))$$, 'student cannot read class report');

-- ---- 4. class teacher access ----
select pg_temp.as_postgres();
update classes set class_teacher_id = pg_temp.v('tc') where id = pg_temp.v('c1');
select pg_temp.as_user(pg_temp.v('tc'));
do $$ declare n int; begin
  select count(*) into n from public.class_attendance_report(pg_temp.v('c1'));
  if n <> 2 then raise exception 'FAIL class teacher sees % students, expected 2', n; end if;
  raise notice 'PASS class teacher sees whole class';
  perform public.attendance_summary(pg_temp.v('s1'));
  raise notice 'PASS class teacher sees a student summary';
end $$;
select pg_temp.expect_fail($$select * from public.class_attendance_report(pg_temp.v('c2'))$$, 'class teacher cannot see another class');
select pg_temp.as_user(pg_temp.v('tp'));
select pg_temp.expect_fail($$select * from public.class_attendance_report(pg_temp.v('c1'))$$, 'subject teacher (not class teacher) blocked from class report');
do $$ declare n int; begin
  update classes set class_teacher_id = pg_temp.v('tp'); get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL teacher changed % classes', n; end if;
  raise notice 'PASS teacher cannot assign class teacher (0 rows changed)';
end $$;

-- ---- 5. office / other roles ----
select pg_temp.as_user(pg_temp.v('off'));
select pg_temp.expect_fail($$select * from public.attendance_roster(pg_temp.v('c1'), pg_temp.v('phys'), public.school_today(), 1::smallint)$$, 'office cannot open attendance roster');
do $$ begin
  if (select count(*) from registrations) <> 0 then raise exception 'FAIL office can read registrations'; end if;
  raise notice 'PASS office cannot read registrations';
end $$;

rollback;
