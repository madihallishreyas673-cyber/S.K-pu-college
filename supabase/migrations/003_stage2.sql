-- =====================================================================
-- Migration 003 (Stage 2): examinations, marks, ranking, fees, content
-- storage, notifications, study-assistant data.
-- Run AFTER 001 and 002. Adds new objects; it only tightens two things:
-- direct writes to `marks` and `payments` are closed so every write goes
-- through the checked functions below.
-- =====================================================================

insert into app_settings values ('pass_percentage','35'), ('show_merit_list','true') on conflict do nothing;

-- Close direct writes: marks and payments may only change through the functions below.
drop policy if exists marks_teacher_insert on marks;
drop policy if exists marks_teacher_update on marks;
revoke insert, update on marks from authenticated;
drop policy if exists payments_office_insert on payments;
revoke insert on payments from authenticated;

-- ---------- internal helpers (no client access) --------------------------
create function public._pass_pct() returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from app_settings where key = 'pass_percentage'), 35)
$$;

create function public._notify_class(p_class uuid, p_kind text, p_title text, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into notifications (user_id, kind, title, body)
  select s.user_id, p_kind, p_title, p_body from students s join users u on u.id = s.user_id
  where s.class_id = p_class and u.status = 'active'
$$;

create function public._notify_user(p_user uuid, p_kind text, p_title text, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into notifications (user_id, kind, title, body) values (p_user, p_kind, p_title, p_body)
$$;

create function public._recompute_rankings(p_exam uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_subjects int;
begin
  select count(distinct subject_id) into v_subjects from marks where exam_id = p_exam and status = 'published';
  delete from rankings where exam_id = p_exam;
  if v_subjects = 0 then return; end if;
  -- Only students who have ALL published subjects are ranked (fair, comparable totals).
  -- rank() gives ties the same position (1,2,2,4 ...), compared on the percentage shown to the student.
  insert into rankings (exam_id, student_id, total_obtained, total_max, percentage, rank)
  select p_exam, t.student_id, t.tot, t.mx, t.pct, rank() over (order by t.pct desc)
  from (
    select mk.student_id, sum(mk.marks_obtained) as tot, sum(mk.max_marks) as mx,
           round(100.0 * sum(mk.marks_obtained) / sum(mk.max_marks), 2) as pct
    from marks mk join users u on u.id = mk.student_id
    where mk.exam_id = p_exam and mk.status = 'published' and u.status = 'active'
    group by mk.student_id
    having count(*) = v_subjects
  ) t;
end $$;

-- ---------- examinations ---------------------------------------------------
create function public.create_exam(p_class uuid, p_name text, p_starts date, p_max numeric default 100)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Only the administrator can create examinations.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_name, ''))) < 2 then raise exception 'Enter the examination name.' using errcode = '22023'; end if;
  if not exists (select 1 from classes where id = p_class) then raise exception 'Class not found.' using errcode = '22023'; end if;
  if p_max is null or p_max <= 0 then raise exception 'Maximum marks must be greater than zero.' using errcode = '22023'; end if;
  insert into examinations (name, class_id, starts_on, default_max_marks) values (btrim(p_name), p_class, p_starts, p_max) returning id into v_id;
  perform public._notify_class(p_class, 'exam', 'New examination: ' || btrim(p_name),
    case when p_starts is null then 'Dates will be announced.' else 'Starts on ' || to_char(p_starts, 'DD Mon YYYY') end);
  perform public.write_audit(auth.uid(), 'exam.create', 'examination', v_id::text, jsonb_build_object('name', p_name, 'class_id', p_class));
  return v_id;
end $$;

-- ---------- marks entry ------------------------------------------------------
create function public.marks_roster(p_exam uuid, p_subject uuid)
returns table (student_id uuid, roll_no int, full_name text, marks_obtained numeric, max_marks numeric, status text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_class uuid;
begin
  select class_id into v_class from examinations where id = p_exam;
  if v_class is null then raise exception 'Examination not found.' using errcode = 'P0002'; end if;
  if not (public.teaches(v_class, p_subject) or public.is_admin()) then
    raise exception 'You are not assigned to this subject and class.' using errcode = '42501';
  end if;
  return query
    select s.user_id, s.roll_no, u.full_name, m.marks_obtained, m.max_marks, m.status
    from students s join users u on u.id = s.user_id
    left join marks m on m.exam_id = p_exam and m.subject_id = p_subject and m.student_id = s.user_id
    where s.class_id = v_class and u.status = 'active'
    order by s.roll_no;
end $$;

create function public.save_mark(p_exam uuid, p_subject uuid, p_student uuid, p_obtained numeric, p_max numeric)
returns void language plpgsql security definer set search_path = public as $$
declare v_class uuid; v_status text;
begin
  select class_id into v_class from examinations where id = p_exam;
  if v_class is null then raise exception 'Examination not found.' using errcode = 'P0002'; end if;
  if public.auth_role() is distinct from 'teacher' or not public.teaches(v_class, p_subject) then
    raise exception 'You can only enter marks for your own subject and class.' using errcode = '42501';
  end if;
  if not exists (select 1 from students s join users u on u.id = s.user_id
                 where s.user_id = p_student and s.class_id = v_class and u.status = 'active') then
    raise exception 'That student is not in this class.' using errcode = '22023';
  end if;
  if p_max is null or p_max <= 0 then raise exception 'Maximum marks must be greater than zero.' using errcode = '22023'; end if;
  if p_obtained is null or p_obtained < 0 then raise exception 'Marks cannot be negative.' using errcode = '22023'; end if;
  if p_obtained > p_max then raise exception 'Marks (%) cannot exceed the maximum (%).', p_obtained, p_max using errcode = '22023'; end if;

  select status into v_status from marks where exam_id = p_exam and subject_id = p_subject and student_id = p_student;
  if v_status = 'published' then
    raise exception 'These marks are published and locked. Ask the administrator for an authorised correction.' using errcode = '42501';
  end if;
  insert into marks (exam_id, subject_id, student_id, entered_by, marks_obtained, max_marks, status)
  values (p_exam, p_subject, p_student, auth.uid(), p_obtained, p_max, 'draft')
  on conflict (exam_id, subject_id, student_id) do update
    set marks_obtained = excluded.marks_obtained, max_marks = excluded.max_marks,
        entered_by = excluded.entered_by, updated_at = now()
    where marks.status = 'draft';
end $$;

create function public.publish_marks(p_exam uuid, p_subject uuid)
returns int language plpgsql security definer set search_path = public as $$
declare v_class uuid; v_roster int; v_entered int; v_n int; v_exam text; v_sub text;
begin
  select class_id, name into v_class, v_exam from examinations where id = p_exam;
  if v_class is null then raise exception 'Examination not found.' using errcode = 'P0002'; end if;
  if public.auth_role() is distinct from 'teacher' or not public.teaches(v_class, p_subject) then
    raise exception 'You can only publish marks for your own subject and class.' using errcode = '42501';
  end if;
  select count(*) into v_roster from students s join users u on u.id = s.user_id where s.class_id = v_class and u.status = 'active';
  select count(*) into v_entered from marks m join students s on s.user_id = m.student_id join users u on u.id = s.user_id
   where m.exam_id = p_exam and m.subject_id = p_subject and s.class_id = v_class and u.status = 'active';
  if v_roster = 0 then raise exception 'This class has no approved students yet.' using errcode = '22023'; end if;
  if v_entered < v_roster then
    raise exception 'Marks are missing for % student(s). Enter every student before publishing.', v_roster - v_entered using errcode = '22023';
  end if;
  update marks set status = 'published', updated_at = now() where exam_id = p_exam and subject_id = p_subject and status = 'draft';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Nothing to publish - these marks are already published.' using errcode = '22023'; end if;

  perform public._recompute_rankings(p_exam);
  select name into v_sub from subjects where id = p_subject;
  perform public._notify_class(v_class, 'result', 'Result published: ' || v_sub, v_exam || ' - ' || v_sub || ' marks are now available.');
  perform public.write_audit(auth.uid(), 'marks.publish', 'examination', p_exam::text,
    jsonb_build_object('subject_id', p_subject, 'students', v_n));
  return v_n;
end $$;

-- Authorised correction of an already-published mark (administrator only, always logged).
create function public.correct_published_mark(p_exam uuid, p_subject uuid, p_student uuid, p_new numeric, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_old numeric; v_max numeric;
begin
  if not public.is_admin() then raise exception 'Only the administrator can correct published marks.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Enter a reason for the correction.' using errcode = '22023'; end if;
  select marks_obtained, max_marks into v_old, v_max from marks
   where exam_id = p_exam and subject_id = p_subject and student_id = p_student and status = 'published' for update;
  if not found then raise exception 'No published mark found for that student.' using errcode = 'P0002'; end if;
  if p_new is null or p_new < 0 or p_new > v_max then raise exception 'Marks must be between 0 and %.', v_max using errcode = '22023'; end if;
  update marks set marks_obtained = p_new, updated_at = now()
   where exam_id = p_exam and subject_id = p_subject and student_id = p_student;
  perform public._recompute_rankings(p_exam);
  perform public._notify_user(p_student, 'result', 'Marks corrected', 'An authorised correction was made to one of your published marks.');
  perform public.write_audit(auth.uid(), 'marks.correct', 'examination', p_exam::text,
    jsonb_build_object('subject_id', p_subject, 'student_id', p_student, 'from', v_old, 'to', p_new, 'reason', btrim(p_reason)));
end $$;

-- ---------- results, ranking, merit list -----------------------------------
create function public.my_results() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_pass numeric := public._pass_pct(); v_out jsonb;
begin
  if public.auth_role() is distinct from 'student' then
    raise exception 'Only students have personal results.' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(x.j order by x.created desc), '[]'::jsonb) into v_out from (
    select e.created_at as created, jsonb_build_object(
      'exam_id', e.id, 'exam_name', e.name,
      'subjects', (select jsonb_agg(jsonb_build_object(
                     'subject', sb.name, 'obtained', m.marks_obtained, 'max', m.max_marks,
                     'percentage', round(100.0 * m.marks_obtained / m.max_marks, 2),
                     'passed', (100.0 * m.marks_obtained / m.max_marks) >= v_pass) order by sb.name)
                   from marks m join subjects sb on sb.id = m.subject_id
                   where m.exam_id = e.id and m.student_id = v_uid and m.status = 'published'),
      'total_obtained', (select sum(marks_obtained) from marks where exam_id = e.id and student_id = v_uid and status = 'published'),
      'total_max', (select sum(max_marks) from marks where exam_id = e.id and student_id = v_uid and status = 'published'),
      'percentage', (select round(100.0 * sum(marks_obtained) / sum(max_marks), 2) from marks where exam_id = e.id and student_id = v_uid and status = 'published'),
      'passed', (select bool_and(100.0 * marks_obtained / max_marks >= v_pass) from marks where exam_id = e.id and student_id = v_uid and status = 'published'),
      'rank', (select r.rank from rankings r where r.exam_id = e.id and r.student_id = v_uid),
      'ranked_students', (select count(*) from rankings r where r.exam_id = e.id)
    ) as j
    from examinations e
    where exists (select 1 from marks m where m.exam_id = e.id and m.student_id = v_uid and m.status = 'published')
  ) x;
  return v_out;
end $$;

create function public.exam_merit_list(p_exam uuid)
returns table (rank int, roll_no int, full_name text, percentage numeric, total_obtained numeric, total_max numeric, is_me boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_class uuid; v_ok boolean := false;
begin
  select class_id into v_class from examinations where id = p_exam;
  if v_class is null then raise exception 'Examination not found.' using errcode = 'P0002'; end if;
  if public.is_admin() or public.is_class_teacher(v_class) then v_ok := true;
  elsif public.auth_role() = 'student' and public.my_class_id() = v_class then
    v_ok := coalesce((select (value #>> '{}')::boolean from app_settings where key = 'show_merit_list'), true);
  end if;
  if not v_ok then raise exception 'The merit list is not available to you.' using errcode = '42501'; end if;
  return query
    select r.rank, s.roll_no, u.full_name, r.percentage, r.total_obtained, r.total_max, (r.student_id = auth.uid())
    from rankings r join students s on s.user_id = r.student_id join users u on u.id = r.student_id
    where r.exam_id = p_exam order by r.rank, s.roll_no;
end $$;

create function public.exam_subject_summary(p_exam uuid)
returns table (subject_name text, students bigint, average_pct numeric, highest_pct numeric, lowest_pct numeric, published boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_class uuid;
begin
  select class_id into v_class from examinations where id = p_exam;
  if v_class is null then raise exception 'Examination not found.' using errcode = 'P0002'; end if;
  if not (public.is_admin() or public.is_class_teacher(v_class)) then
    raise exception 'Only the administrator or class teacher can view this.' using errcode = '42501';
  end if;
  return query
    select sb.name, count(*), round(avg(100.0 * m.marks_obtained / m.max_marks), 2),
           round(max(100.0 * m.marks_obtained / m.max_marks), 2), round(min(100.0 * m.marks_obtained / m.max_marks), 2),
           bool_and(m.status = 'published')
    from marks m join subjects sb on sb.id = m.subject_id where m.exam_id = p_exam
    group by sb.name order by sb.name;
end $$;

-- Data for the study assistant: my marks plus only the class AVERAGE (never other students' marks).
create function public.my_progress()
returns table (exam_id uuid, exam_name text, exam_created timestamptz, subject_name text, percentage numeric, class_avg numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if public.auth_role() is distinct from 'student' then raise exception 'Only students have personal progress.' using errcode = '42501'; end if;
  return query
    select e.id, e.name, e.created_at, sb.name, round(100.0 * m.marks_obtained / m.max_marks, 2),
           (select round(avg(100.0 * c.marks_obtained / c.max_marks), 2) from marks c
             where c.exam_id = m.exam_id and c.subject_id = m.subject_id and c.status = 'published')
    from marks m join examinations e on e.id = m.exam_id join subjects sb on sb.id = m.subject_id
    where m.student_id = auth.uid() and m.status = 'published'
    order by e.created_at, sb.name;
end $$;

create function public.my_subject_teachers()
returns table (subject_id uuid, subject_name text, teacher_name text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if public.auth_role() is distinct from 'student' then raise exception 'Students only.' using errcode = '42501'; end if;
  return query
    select sb.id, sb.name, string_agg(u.full_name, ', ' order by u.full_name)
    from subjects sb
    left join teacher_assignments ta on ta.subject_id = sb.id and ta.class_id = public.my_class_id()
    left join users u on u.id = ta.teacher_id and u.status = 'active'
    where sb.is_active group by sb.id, sb.name order by sb.name;
end $$;

-- ---------- fees -------------------------------------------------------------
create function public._fee_year() returns uuid language sql stable security definer set search_path = public as $$
  select id from academic_years where is_current limit 1
$$;

create function public._paid(p_student uuid, p_year uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount), 0) from payments where student_id = p_student and academic_year_id = p_year and not is_void
$$;

-- Remaining is ALWAYS computed (total - non-void payments); it is never stored, so it cannot drift.
create function public.fee_account(p_student uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_t uuid; v_year uuid := public._fee_year(); v_total numeric; v_paid numeric; v_info jsonb; v_pay jsonb;
begin
  if public.auth_role() = 'student' then v_t := auth.uid();
  elsif public.auth_role() in ('office', 'admin') then v_t := p_student;
  else raise exception 'You are not allowed to view fees.' using errcode = '42501'; end if;
  if v_t is null then raise exception 'Choose a student.' using errcode = '22023'; end if;

  select jsonb_build_object('id', u.id, 'name', u.full_name, 'roll_no', s.roll_no, 'year_level', u.year_level, 'section', c.section)
    into v_info from users u join students s on s.user_id = u.id join classes c on c.id = s.class_id where u.id = v_t;
  if v_info is null then raise exception 'Student not found.' using errcode = 'P0002'; end if;

  select total_fee into v_total from fees where student_id = v_t and academic_year_id = v_year;
  v_paid := public._paid(v_t, v_year);
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'amount', p.amount, 'reference_no', p.reference_no,
           'paid_on', p.paid_on, 'is_void', p.is_void, 'void_reason', p.void_reason, 'received_by', ru.full_name)
           order by p.paid_on desc, p.created_at desc), '[]'::jsonb)
    into v_pay from payments p join users ru on ru.id = p.received_by
    where p.student_id = v_t and p.academic_year_id = v_year;

  return jsonb_build_object('student', v_info, 'has_account', v_total is not null,
    'total', coalesce(v_total, 0), 'paid', v_paid, 'remaining', coalesce(v_total, 0) - v_paid, 'payments', v_pay,
    'year_label', (select label from academic_years where id = v_year));
end $$;

create function public.fee_search(p_query text)
returns table (student_id uuid, roll_no int, full_name text, year_level smallint, section text, total_fee numeric, paid numeric, remaining numeric, has_account boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_q text := btrim(coalesce(p_query, '')); v_year uuid := public._fee_year();
begin
  if public.auth_role() not in ('office', 'admin') then raise exception 'Only office staff can search fees.' using errcode = '42501'; end if;
  if v_q = '' then return; end if;
  return query
    select u.id, s.roll_no, u.full_name, u.year_level, c.section, f.total_fee, public._paid(u.id, v_year),
           coalesce(f.total_fee, 0) - public._paid(u.id, v_year), f.total_fee is not null
    from students s join users u on u.id = s.user_id join classes c on c.id = s.class_id
    left join fees f on f.student_id = u.id and f.academic_year_id = v_year
    where u.status = 'active' and c.academic_year_id = v_year
      and ( (v_q ~ '^[0-9]{1,9}$' and s.roll_no = v_q::int)                       -- roll number = exact match only
         or (v_q !~ '^[0-9]+$' and lower(u.full_name) like '%' || lower(replace(replace(v_q, '%', ''), '_', '')) || '%') )
    order by u.year_level, s.roll_no limit 50;
end $$;

create function public.set_total_fee(p_student uuid, p_total numeric) returns void
language plpgsql security definer set search_path = public as $$
declare v_year uuid := public._fee_year(); v_old numeric;
begin
  if public.auth_role() not in ('office', 'admin') then raise exception 'Only office staff can set fees.' using errcode = '42501'; end if;
  if not exists (select 1 from students where user_id = p_student) then raise exception 'Student not found.' using errcode = 'P0002'; end if;
  if p_total is null or p_total < 0 then raise exception 'Total fee cannot be negative.' using errcode = '22023'; end if;
  select total_fee into v_old from fees where student_id = p_student and academic_year_id = v_year for update;
  if public._paid(p_student, v_year) > p_total then
    raise exception 'Total fee cannot be lower than the amount already paid (Rs. %).', public._paid(p_student, v_year) using errcode = '22023';
  end if;
  insert into fees (student_id, academic_year_id, total_fee) values (p_student, v_year, p_total)
  on conflict (student_id, academic_year_id) do update set total_fee = excluded.total_fee;
  perform public.write_audit(auth.uid(), 'fee.set_total', 'student', p_student::text, jsonb_build_object('from', v_old, 'to', p_total));
end $$;

create function public.add_payment(p_student uuid, p_amount numeric, p_reference text, p_paid_on date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_year uuid := public._fee_year(); v_total numeric; v_paid numeric; v_id uuid; v_ref text := btrim(coalesce(p_reference, ''));
        v_date date := coalesce(p_paid_on, public.school_today());
begin
  if public.auth_role() is distinct from 'office' then raise exception 'Only office staff can record payments.' using errcode = '42501'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Enter an amount greater than zero.' using errcode = '22023'; end if;
  if char_length(v_ref) < 3 or char_length(v_ref) > 40 then raise exception 'Enter the receipt / transaction reference (3 to 40 characters).' using errcode = '22023'; end if;
  if v_date > public.school_today() then raise exception 'Payment date cannot be in the future.' using errcode = '22023'; end if;

  -- Lock this student's fee row: two staff members cannot overspend the same balance at once.
  select total_fee into v_total from fees where student_id = p_student and academic_year_id = v_year for update;
  if not found then raise exception 'Set the student''s total fee first.' using errcode = '22023'; end if;
  v_paid := public._paid(p_student, v_year);
  if p_amount > v_total - v_paid then
    raise exception 'Amount exceeds the remaining balance of Rs. %.', v_total - v_paid using errcode = '22023';
  end if;
  if exists (select 1 from payments where student_id = p_student and amount = p_amount and not is_void
             and created_at > now() - interval '2 minutes') then
    raise exception 'The same amount was just recorded for this student. If this is a new payment, wait two minutes or use a different amount.' using errcode = 'P0001';
  end if;
  begin
    insert into payments (student_id, academic_year_id, amount, reference_no, paid_on, received_by)
    values (p_student, v_year, p_amount, v_ref, v_date, auth.uid()) returning id into v_id;
  exception when unique_violation then
    raise exception 'Reference "%" was already used. Duplicate payment prevented.', v_ref using errcode = 'P0001';
  end;
  perform public._notify_user(p_student, 'fee', 'Fee payment received', 'Rs. ' || p_amount || ' received. Remaining: Rs. ' || (v_total - v_paid - p_amount));
  perform public.write_audit(auth.uid(), 'fee.payment', 'student', p_student::text,
    jsonb_build_object('payment_id', v_id, 'amount', p_amount, 'reference', v_ref));
  return v_id;
end $$;

-- A wrong payment is never deleted: the administrator voids it with a reason and it stays visible in history.
create function public.void_payment(p_payment uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v_p payments;
begin
  if not public.is_admin() then raise exception 'Only the administrator can void a payment.' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Enter a reason.' using errcode = '22023'; end if;
  select * into v_p from payments where id = p_payment for update;
  if not found then raise exception 'Payment not found.' using errcode = 'P0002'; end if;
  if v_p.is_void then raise exception 'This payment is already void.' using errcode = '22023'; end if;
  perform 1 from fees where student_id = v_p.student_id and academic_year_id = v_p.academic_year_id for update;
  update payments set is_void = true, void_reason = btrim(p_reason) where id = p_payment;
  perform public._notify_user(v_p.student_id, 'fee', 'Payment corrected', 'A payment of Rs. ' || v_p.amount || ' was voided by the administrator.');
  perform public.write_audit(auth.uid(), 'fee.void', 'payment', p_payment::text,
    jsonb_build_object('amount', v_p.amount, 'reference', v_p.reference_no, 'reason', btrim(p_reason)));
end $$;

create function public.trg_payment_guard() returns trigger language plpgsql as $$
begin
  if row(new.id, new.student_id, new.academic_year_id, new.amount, new.reference_no, new.paid_on, new.received_by, new.created_at)
     is distinct from row(old.id, old.student_id, old.academic_year_id, old.amount, old.reference_no, old.paid_on, old.received_by, old.created_at) then
    raise exception 'Payment records cannot be edited. Void the payment and record a new one.';
  end if;
  if old.is_void and not new.is_void then raise exception 'A voided payment cannot be restored.'; end if;
  return new;
end $$;
create trigger payments_guard before update on payments for each row execute function public.trg_payment_guard();

create function public.fee_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_year uuid := public._fee_year();
begin
  if public.auth_role() not in ('office', 'admin') then raise exception 'Not allowed.' using errcode = '42501'; end if;
  return (select jsonb_build_object(
    'year_label', (select label from academic_years where id = v_year),
    'students_with_account', count(*),
    'total_fees', coalesce(sum(t.total_fee), 0), 'collected', coalesce(sum(t.paid), 0),
    'remaining', coalesce(sum(t.total_fee - t.paid), 0),
    'students_with_dues', count(*) filter (where t.total_fee - t.paid > 0))
    from (select f.total_fee, public._paid(f.student_id, v_year) as paid from fees f where f.academic_year_id = v_year) t);
end $$;

-- ---------- notifications for new content & announcements ------------------------
create function public.trg_notify_note() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public._notify_class(new.class_id, 'notes', 'New notes: ' || new.title,
    (select name from subjects where id = new.subject_id) || ' - ' || new.chapter);
  return new;
end $$;
create trigger notes_notify after insert on notes for each row execute function public.trg_notify_note();

create function public.trg_notify_video() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public._notify_class(new.class_id, 'video', 'New video: ' || new.title,
    (select name from subjects where id = new.subject_id) || ' - ' || new.chapter);
  return new;
end $$;
create trigger videos_notify after insert on videos for each row execute function public.trg_notify_video();

create function public.trg_notify_live() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public._notify_class(new.class_id, 'live', 'Live class scheduled: ' || new.title,
      (select name from subjects where id = new.subject_id) || ' on ' || to_char(new.scheduled_at at time zone 'Asia/Kolkata', 'DD Mon, HH12:MI AM'));
  elsif new.status = 'live' and old.status is distinct from 'live' then
    perform public._notify_class(new.class_id, 'live', 'Live class started: ' || new.title, 'Open Live Classes to join now.');
  end if;
  return new;
end $$;
create trigger live_notify after insert or update on live_classes for each row execute function public.trg_notify_live();

create function public.trg_notify_announcement() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, kind, title, body)
  select u.id, 'announcement', new.title, left(new.body, 200)
  from users u left join students s on s.user_id = u.id
  where u.status = 'active' and u.id <> new.created_by
    and (new.target_role is null or u.role = new.target_role)
    and (new.class_id is null or s.class_id = new.class_id);
  return new;
end $$;
create trigger announcements_notify after insert on announcements for each row execute function public.trg_notify_announcement();

-- ---------- private storage for notes and videos ------------------------------------
-- Path convention: <class_id>/<subject_id>/<random-file-name>
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('materials', 'materials', false, 52428800, array[
  'application/pdf','image/jpeg','image/png','image/webp','text/plain',
  'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'video/mp4','video/webm','video/quicktime'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy materials_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'materials' and public.auth_role() = 'teacher'
  and public.teaches(((storage.foldername(name))[1])::uuid, ((storage.foldername(name))[2])::uuid));
create policy materials_read on storage.objects for select to authenticated using (
  bucket_id = 'materials' and (public.is_admin()
    or ((storage.foldername(name))[1])::uuid = public.my_class_id()
    or public.teaches(((storage.foldername(name))[1])::uuid, ((storage.foldername(name))[2])::uuid)));
create policy materials_delete on storage.objects for delete to authenticated using (
  bucket_id = 'materials' and (public.is_admin()
    or public.teaches(((storage.foldername(name))[1])::uuid, ((storage.foldername(name))[2])::uuid)));

-- ---------- grants ---------------------------------------------------------------------
revoke execute on function
  public._pass_pct(), public._notify_class(uuid, text, text, text), public._notify_user(uuid, text, text, text),
  public._recompute_rankings(uuid), public._fee_year(), public._paid(uuid, uuid),
  public.trg_notify_note(), public.trg_notify_video(), public.trg_notify_live(), public.trg_notify_announcement(), public.trg_payment_guard()
from public, anon, authenticated;

revoke execute on function
  public.create_exam(uuid, text, date, numeric), public.marks_roster(uuid, uuid), public.save_mark(uuid, uuid, uuid, numeric, numeric),
  public.publish_marks(uuid, uuid), public.correct_published_mark(uuid, uuid, uuid, numeric, text), public.my_results(),
  public.exam_merit_list(uuid), public.exam_subject_summary(uuid), public.my_progress(), public.my_subject_teachers(),
  public.fee_account(uuid), public.fee_search(text), public.set_total_fee(uuid, numeric),
  public.add_payment(uuid, numeric, text, date), public.void_payment(uuid, text), public.fee_summary()
from public, anon;

grant execute on function
  public.create_exam(uuid, text, date, numeric), public.marks_roster(uuid, uuid), public.save_mark(uuid, uuid, uuid, numeric, numeric),
  public.publish_marks(uuid, uuid), public.correct_published_mark(uuid, uuid, uuid, numeric, text), public.my_results(),
  public.exam_merit_list(uuid), public.exam_subject_summary(uuid), public.my_progress(), public.my_subject_teachers(),
  public.fee_account(uuid), public.fee_search(text), public.set_total_fee(uuid, numeric),
  public.add_payment(uuid, numeric, text, date), public.void_payment(uuid, text), public.fee_summary()
to authenticated;
