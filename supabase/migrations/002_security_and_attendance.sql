-- =====================================================================
-- Migration 002: row-level security, attendance functions, approvals
-- =====================================================================

-- ---------- Lock everything, then open only what is needed ------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Reference data is readable by everyone (needed on the registration form).
grant select on subjects, classes, academic_years to anon, authenticated;
create policy ref_subjects_read on subjects       for select to anon, authenticated using (true);
create policy ref_classes_read  on classes        for select to anon, authenticated using (true);
create policy ref_years_read    on academic_years for select to anon, authenticated using (true);

-- Administrator-only management of reference data.
grant insert, update, delete on subjects, classes, academic_years, teacher_assignments to authenticated;
create policy subjects_admin_write on subjects       for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy classes_admin_write  on classes        for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy years_admin_write    on academic_years for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Accounts: a person sees only their own row; admins see all.
-- Credentials, registration_secrets get NO grants and NO policies: unreachable from the app.
grant select on users, students, teachers, office_staff, administrators, teacher_assignments to authenticated;
create policy users_self_or_admin on users for select to authenticated using (id = auth.uid() or public.is_admin());
create policy students_self_or_admin on students for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy teachers_self_or_admin on teachers for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy office_self_or_admin on office_staff for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy admins_self_or_admin on administrators for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy assignments_read on teacher_assignments for select to authenticated using (teacher_id = auth.uid() or public.is_admin());
create policy assignments_admin_write on teacher_assignments for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Registrations: administrators only (writes happen in Edge Functions with the service key).
grant select on registrations to authenticated;
create policy registrations_admin_read on registrations for select to authenticated using (public.is_admin());

-- Attendance: read-only for clients. ALL writes go through the functions below.
grant select on attendance_sessions, attendance_records, attendance_audit to authenticated;
create policy att_sessions_read on attendance_sessions for select to authenticated using (
  public.is_admin() or public.teaches(class_id, subject_id) or public.is_class_teacher(class_id) or class_id = public.my_class_id());
create policy att_records_read on attendance_records for select to authenticated using (
  student_id = auth.uid() or public.is_admin() or exists (
    select 1 from attendance_sessions s where s.id = session_id
      and (public.teaches(s.class_id, s.subject_id) or public.is_class_teacher(s.class_id))));
create policy att_audit_read on attendance_audit for select to authenticated using (
  public.is_admin() or changed_by = auth.uid() or exists (
    select 1 from attendance_sessions s where s.id = session_id and public.is_class_teacher(s.class_id)));

-- Content tables (Stage 2 UI): students see only their own class.
grant select, insert, update, delete on notes, videos, live_classes to authenticated;
create policy notes_read on notes for select to authenticated using (public.is_admin() or teacher_id = auth.uid() or class_id = public.my_class_id());
create policy notes_write on notes for all to authenticated using (public.is_admin() or (teacher_id = auth.uid() and public.teaches(class_id, subject_id)))
  with check (public.is_admin() or (teacher_id = auth.uid() and public.teaches(class_id, subject_id)));
create policy videos_read on videos for select to authenticated using (public.is_admin() or teacher_id = auth.uid() or class_id = public.my_class_id());
create policy videos_write on videos for all to authenticated using (public.is_admin() or (teacher_id = auth.uid() and public.teaches(class_id, subject_id)))
  with check (public.is_admin() or (teacher_id = auth.uid() and public.teaches(class_id, subject_id)));
create policy live_read on live_classes for select to authenticated using (public.is_admin() or teacher_id = auth.uid() or class_id = public.my_class_id());
create policy live_write on live_classes for all to authenticated using (public.is_admin() or (teacher_id = auth.uid() and public.teaches(class_id, subject_id)))
  with check (public.is_admin() or (teacher_id = auth.uid() and public.teaches(class_id, subject_id)));

-- Marks, rankings (Stage 2 UI).
grant select on examinations, rankings to authenticated;
grant select, insert, update on marks to authenticated;
create policy exams_read on examinations for select to authenticated using (public.auth_role() is not null);
create policy rankings_read on rankings for select to authenticated using (student_id = auth.uid() or public.is_admin());
create policy marks_read on marks for select to authenticated using (
  public.is_admin() or (student_id = auth.uid() and status = 'published') or public.teaches_student(student_id, subject_id));
create policy marks_teacher_insert on marks for insert to authenticated
  with check (entered_by = auth.uid() and status = 'draft' and public.teaches_student(student_id, subject_id));
create policy marks_teacher_update on marks for update to authenticated
  using (status = 'draft' and public.teaches_student(student_id, subject_id))
  with check (status = 'draft' and public.teaches_student(student_id, subject_id));

-- Fees (Stage 2 UI): payments can be added but never edited or deleted.
grant select on fees, payments to authenticated;
grant insert on payments to authenticated;
create policy fees_read on fees for select to authenticated using (student_id = auth.uid() or public.auth_role() in ('office','admin'));
create policy payments_read on payments for select to authenticated using (student_id = auth.uid() or public.auth_role() in ('office','admin'));
create policy payments_office_insert on payments for insert to authenticated
  with check (public.auth_role() = 'office' and received_by = auth.uid() and not is_void);

-- Notifications, announcements, audit.
grant select on notifications, announcements, audit_logs, app_settings to authenticated;
grant update (is_read) on notifications to authenticated;
create policy notif_own on notifications for select to authenticated using (user_id = auth.uid());
create policy notif_mark_read on notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy ann_read on announcements for select to authenticated using (
  public.is_admin() or ((target_role is null or target_role = public.auth_role())
                        and (class_id is null or class_id = public.my_class_id())));
grant insert, update, delete on announcements to authenticated;
create policy ann_admin_write on announcements for all to authenticated using (public.is_admin()) with check (public.is_admin() and created_by = auth.uid());
create policy audit_admin_read on audit_logs for select to authenticated using (public.is_admin());
create policy settings_read on app_settings for select to authenticated using (true);

-- ---------- Private storage for ID card photos --------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('id-cards', 'id-cards', false, 5242880, array['image/jpeg','image/png'])
on conflict (id) do update set public = false;
-- Uploads/deletes use the service key inside Edge Functions. Only admins may read.
create policy id_cards_admin_read on storage.objects for select to authenticated
  using (bucket_id = 'id-cards' and public.is_admin());

-- =====================================================================
-- ATTENDANCE FUNCTIONS
-- =====================================================================
create function public.submit_attendance(
  p_class_id uuid, p_subject_id uuid, p_date date, p_period smallint, p_records jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_session uuid; v_roster int; v_given int;
begin
  if public.auth_role() is distinct from 'teacher' or not public.teaches(p_class_id, p_subject_id) then
    raise exception 'You are not assigned to this subject and class.' using errcode = '42501';
  end if;
  if p_date is null or p_date > public.school_today() then
    raise exception 'Attendance cannot be marked for a future date.' using errcode = '22023';
  end if;
  if p_period is null or p_period < 1 or p_period > 12 then
    raise exception 'Period must be between 1 and 12.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_records) is distinct from 'array' then
    raise exception 'Attendance list is missing.' using errcode = '22023';
  end if;

  select count(*) into v_roster from students s join users u on u.id = s.user_id
   where s.class_id = p_class_id and u.status = 'active';
  v_given := jsonb_array_length(p_records);
  if v_roster = 0 then
    raise exception 'This class has no approved students yet.' using errcode = '22023';
  end if;
  if v_given <> v_roster then
    raise exception 'Mark every student as P or A before submitting.' using errcode = '22023';
  end if;
  if (select count(distinct r->>'student_id') from jsonb_array_elements(p_records) r) <> v_given then
    raise exception 'A student appears twice in the attendance list.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_records) r
    where coalesce(r->>'status', '') not in ('P','A')
       or not exists (select 1 from students s join users u on u.id = s.user_id
                      where s.user_id = (r->>'student_id')::uuid and s.class_id = p_class_id and u.status = 'active')
  ) then
    raise exception 'Attendance contains an unknown student or an invalid mark.' using errcode = '22023';
  end if;

  begin
    insert into attendance_sessions (class_id, subject_id, teacher_id, session_date, period)
    values (p_class_id, p_subject_id, auth.uid(), p_date, p_period) returning id into v_session;
  exception when unique_violation then
    raise exception 'Attendance for this class, subject, date and period is already submitted. Use Correct attendance to change it.'
      using errcode = 'P0001';
  end;

  insert into attendance_records (session_id, student_id, status)
  select v_session, (r->>'student_id')::uuid, (r->>'status')::att_status from jsonb_array_elements(p_records) r;

  perform public.write_audit(auth.uid(), 'attendance.submit', 'attendance_session', v_session::text,
    jsonb_build_object('class_id', p_class_id, 'subject_id', p_subject_id, 'date', p_date, 'period', p_period, 'students', v_given));
  return v_session;
end $$;

create function public.attendance_roster(p_class_id uuid, p_subject_id uuid, p_date date, p_period smallint)
returns table (student_id uuid, roll_no int, full_name text, existing_status att_status, session_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not (public.teaches(p_class_id, p_subject_id) or public.is_admin()) then
    raise exception 'You are not assigned to this subject and class.' using errcode = '42501';
  end if;
  return query
    select s.user_id, s.roll_no, u.full_name, r.status, ses.id
    from students s
    join users u on u.id = s.user_id
    left join attendance_sessions ses on ses.class_id = p_class_id and ses.subject_id = p_subject_id
                                     and ses.session_date = p_date and ses.period = p_period
    left join attendance_records r on r.session_id = ses.id and r.student_id = s.user_id
    where s.class_id = p_class_id and u.status = 'active'
    order by s.roll_no;
end $$;

create function public.correct_attendance(p_session_id uuid, p_student_id uuid, p_new_status att_status, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_ses attendance_sessions; v_old att_status; v_window int;
begin
  select * into v_ses from attendance_sessions where id = p_session_id;
  if not found then raise exception 'Attendance session not found.' using errcode = 'P0002'; end if;

  v_window := coalesce((select (value #>> '{}')::int from app_settings where key = 'correction_window_days'), 7);
  if public.is_admin() then
    null;
  elsif public.auth_role() = 'teacher' and public.teaches(v_ses.class_id, v_ses.subject_id) then
    if v_ses.session_date < public.school_today() - v_window then
      raise exception 'Corrections are locked after % days. Ask the administrator.', v_window using errcode = '42501';
    end if;
  else
    raise exception 'You are not allowed to correct this attendance.' using errcode = '42501';
  end if;

  if char_length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Enter a reason for the correction.' using errcode = '22023';
  end if;
  if not exists (select 1 from students where user_id = p_student_id and class_id = v_ses.class_id) then
    raise exception 'That student is not in this class.' using errcode = '22023';
  end if;

  select status into v_old from attendance_records where session_id = p_session_id and student_id = p_student_id for update;
  if found and v_old = p_new_status then
    raise exception 'Attendance already shows that status.' using errcode = '22023';
  end if;

  insert into attendance_records (session_id, student_id, status) values (p_session_id, p_student_id, p_new_status)
  on conflict (session_id, student_id) do update set status = excluded.status, updated_at = now();

  insert into attendance_audit (session_id, student_id, old_status, new_status, reason, changed_by)
  values (p_session_id, p_student_id, v_old, p_new_status, btrim(p_reason), auth.uid());
  perform public.write_audit(auth.uid(), 'attendance.correct', 'attendance_session', p_session_id::text,
    jsonb_build_object('student_id', p_student_id, 'from', v_old, 'to', p_new_status));
end $$;

-- Who may look at a given student's attendance: the student, an admin, or the class teacher.
create function public._att_target(p_student uuid) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_target uuid := coalesce(p_student, auth.uid()); v_class uuid;
begin
  if v_target is null then raise exception 'Not signed in.' using errcode = '42501'; end if;
  if v_target = auth.uid() and public.auth_role() = 'student' then return v_target; end if;
  if public.is_admin() then return v_target; end if;
  select class_id into v_class from students where user_id = v_target;
  if v_class is not null and public.is_class_teacher(v_class) then return v_target; end if;
  raise exception 'You are not allowed to view this attendance.' using errcode = '42501';
end $$;

-- Overall % = total present / total conducted across ALL subjects (never an average of averages).
create function public.attendance_summary(p_student uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_t uuid := public._att_target(p_student);
  v_thr numeric := public.low_threshold();
  v_overall jsonb; v_subjects jsonb; v_pct numeric; v_cnt bigint;
begin
  select jsonb_build_object(
           'conducted', count(*),
           'present',   count(*) filter (where r.status = 'P'),
           'absent',    count(*) filter (where r.status = 'A'),
           'percentage', case when count(*) = 0 then 0
                              else round(100.0 * count(*) filter (where r.status = 'P') / count(*), 2) end),
         count(*)
    into v_overall, v_cnt
    from attendance_records r where r.student_id = v_t;
  v_pct := (v_overall->>'percentage')::numeric;

  select coalesce(jsonb_agg(jsonb_build_object(
           'subject_id', t.subject_id, 'subject_name', t.name, 'conducted', t.conducted,
           'present', t.present, 'absent', t.conducted - t.present, 'percentage', t.pct) order by t.name), '[]'::jsonb)
    into v_subjects
    from (select s.id as subject_id, s.name, count(*) as conducted,
                 count(*) filter (where r.status = 'P') as present,
                 round(100.0 * count(*) filter (where r.status = 'P') / count(*), 2) as pct
          from attendance_records r
          join attendance_sessions ses on ses.id = r.session_id
          join subjects s on s.id = ses.subject_id
          where r.student_id = v_t group by s.id, s.name) t;

  return jsonb_build_object('overall', v_overall, 'subjects', v_subjects,
                            'threshold', v_thr, 'is_low', (v_cnt > 0 and v_pct < v_thr));
end $$;

create function public.attendance_daily(p_student uuid default null, p_from date default null, p_to date default null)
returns table (session_date date, period smallint, subject_name text, status att_status, teacher_name text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_t uuid := public._att_target(p_student);
begin
  return query
    select ses.session_date, ses.period, sub.name, r.status, tu.full_name
    from attendance_records r
    join attendance_sessions ses on ses.id = r.session_id
    join subjects sub on sub.id = ses.subject_id
    join users tu on tu.id = ses.teacher_id
    where r.student_id = v_t
      and (p_from is null or ses.session_date >= p_from)
      and (p_to is null or ses.session_date <= p_to)
    order by ses.session_date desc, ses.period, sub.name;
end $$;

create function public.attendance_monthly(p_student uuid default null)
returns table (month date, conducted bigint, present bigint, absent bigint, percentage numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_t uuid := public._att_target(p_student);
begin
  return query
    select date_trunc('month', ses.session_date)::date, count(*),
           count(*) filter (where r.status = 'P'), count(*) filter (where r.status = 'A'),
           round(100.0 * count(*) filter (where r.status = 'P') / count(*), 2)
    from attendance_records r join attendance_sessions ses on ses.id = r.session_id
    where r.student_id = v_t
    group by date_trunc('month', ses.session_date)
    order by 1 desc;
end $$;

create function public.class_attendance_report(p_class_id uuid, p_from date default null, p_to date default null)
returns table (student_id uuid, roll_no int, full_name text, conducted bigint, present bigint,
               absent bigint, percentage numeric, is_low boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_thr numeric := public.low_threshold();
begin
  if not (public.is_admin() or public.is_class_teacher(p_class_id)) then
    raise exception 'Only the class teacher or administrator can view class attendance.' using errcode = '42501';
  end if;
  return query
    select q.user_id, q.roll_no, q.full_name, q.conducted, q.present, q.absent, q.pct,
           (q.conducted > 0 and q.pct < v_thr)
    from (
      select s.user_id, s.roll_no, u.full_name,
             count(r.student_id) as conducted,
             count(r.student_id) filter (where r.status = 'P') as present,
             count(r.student_id) filter (where r.status = 'A') as absent,
             case when count(r.student_id) = 0 then 0::numeric
                  else round(100.0 * count(r.student_id) filter (where r.status = 'P') / count(r.student_id), 2) end as pct
      from students s
      join users u on u.id = s.user_id
      left join attendance_sessions ses on ses.class_id = p_class_id
           and (p_from is null or ses.session_date >= p_from) and (p_to is null or ses.session_date <= p_to)
      left join attendance_records r on r.session_id = ses.id and r.student_id = s.user_id
      where s.class_id = p_class_id and u.status = 'active'
      group by s.user_id, s.roll_no, u.full_name) q
    order by q.roll_no;
end $$;

create function public.class_subject_attendance(p_class_id uuid, p_from date default null, p_to date default null)
returns table (subject_id uuid, subject_name text, sessions bigint, percentage numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not (public.is_admin() or public.is_class_teacher(p_class_id)) then
    raise exception 'Only the class teacher or administrator can view class attendance.' using errcode = '42501';
  end if;
  return query
    select sub.id, sub.name, count(distinct ses.id),
           case when count(r.student_id) = 0 then 0::numeric
                else round(100.0 * count(r.student_id) filter (where r.status = 'P') / count(r.student_id), 2) end
    from attendance_sessions ses
    join subjects sub on sub.id = ses.subject_id
    left join attendance_records r on r.session_id = ses.id
    where ses.class_id = p_class_id
      and (p_from is null or ses.session_date >= p_from) and (p_to is null or ses.session_date <= p_to)
    group by sub.id, sub.name order by sub.name;
end $$;

-- =====================================================================
-- REGISTRATION REVIEW (called only by the `admin` Edge Function, service key)
-- =====================================================================
create function public.approve_registration(p_reg uuid, p_admin uuid, p_class uuid, p_assignments jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare
  r registrations; v_sec registration_secrets; v_class classes; v_user uuid := gen_random_uuid();
begin
  select * into r from registrations where id = p_reg for update;
  if not found then raise exception 'Registration not found.'; end if;
  if r.status <> 'pending' then raise exception 'This registration was already reviewed.'; end if;
  select * into v_sec from registration_secrets where registration_id = p_reg;
  if not found then raise exception 'Registration is missing its PIN. Ask the user to register again.'; end if;
  if exists (select 1 from users where role = r.role and lower(login_id) = lower(r.login_id)
             and coalesce(year_level, 0) = coalesce(r.year_level, 0)) then
    raise exception 'An account with this ID already exists.';
  end if;

  insert into users (id, role, login_id, year_level, full_name) values (v_user, r.role, r.login_id, r.year_level, r.full_name);
  insert into credentials (user_id, pin_hash, pin_salt, iterations) values (v_user, v_sec.pin_hash, v_sec.pin_salt, v_sec.iterations);

  if r.role = 'student' then
    select * into v_class from classes where id = p_class;
    if not found or v_class.year_level <> r.year_level then
      raise exception 'Choose a class that matches the student''s year.';
    end if;
    insert into students (user_id, class_id, roll_no) values (v_user, p_class, r.login_id::int);
  elsif r.role = 'teacher' then
    if p_assignments is null or jsonb_typeof(p_assignments) <> 'array' or jsonb_array_length(p_assignments) = 0 then
      raise exception 'Assign at least one subject and class to the teacher.';
    end if;
    insert into teachers (user_id) values (v_user);
    insert into teacher_assignments (teacher_id, subject_id, class_id)
      select v_user, (a->>'subject_id')::uuid, (a->>'class_id')::uuid from jsonb_array_elements(p_assignments) a
      on conflict do nothing;
  elsif r.role = 'office' then
    insert into office_staff (user_id) values (v_user);
  end if;

  update registrations set status = 'approved', reviewed_by = p_admin, reviewed_at = now(), user_id = v_user where id = p_reg;
  delete from registration_secrets where registration_id = p_reg;
  insert into notifications (user_id, kind, title, body)
    values (v_user, 'account', 'Account approved', 'Your registration was approved. You can now sign in.');
  perform public.write_audit(p_admin, 'registration.approve', 'registration', p_reg::text,
    jsonb_build_object('user_id', v_user, 'role', r.role));
  return r.id_photo_path;
end $$;

create function public.reject_registration(p_reg uuid, p_admin uuid, p_reason text)
returns text language plpgsql security definer set search_path = public as $$
declare r registrations;
begin
  select * into r from registrations where id = p_reg for update;
  if not found then raise exception 'Registration not found.'; end if;
  if r.status <> 'pending' then raise exception 'This registration was already reviewed.'; end if;
  update registrations set status = 'rejected', reject_reason = left(coalesce(nullif(btrim(p_reason), ''), 'Not verified'), 300),
         reviewed_by = p_admin, reviewed_at = now() where id = p_reg;
  delete from registration_secrets where registration_id = p_reg;
  perform public.write_audit(p_admin, 'registration.reject', 'registration', p_reg::text, jsonb_build_object('role', r.role));
  return r.id_photo_path;
end $$;

-- ---------- Function grants ---------------------------------------------
-- Needed inside RLS policies:
grant execute on function public.auth_role(), public.is_admin(), public.my_class_id(),
  public.teaches(uuid, uuid), public.is_class_teacher(uuid), public.teaches_student(uuid, uuid) to authenticated;
-- App-facing RPCs:
grant execute on function
  public.submit_attendance(uuid, uuid, date, smallint, jsonb),
  public.attendance_roster(uuid, uuid, date, smallint),
  public.correct_attendance(uuid, uuid, att_status, text),
  public.attendance_summary(uuid),
  public.attendance_daily(uuid, date, date),
  public.attendance_monthly(uuid),
  public.class_attendance_report(uuid, date, date),
  public.class_subject_attendance(uuid, date, date),
  public.school_today()
to authenticated;
-- approve_registration / reject_registration / write_audit / low_threshold: service key only.
