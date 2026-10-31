-- =====================================================================
-- SMART SCHOOL  |  Migration 001: schema, security helpers, seed data
-- No Supabase Auth is used. Identity = school ID + PIN, verified by the
-- `login` Edge Function, which issues a signed token (claim `sub` = users.id).
-- =====================================================================
create extension if not exists pgcrypto;

create type user_role      as enum ('student','teacher','office','admin');
create type account_status as enum ('active','disabled');
create type review_status  as enum ('pending','approved','rejected');
create type att_status     as enum ('P','A');

-- ---------- Accounts -------------------------------------------------
create table academic_years (
  id         uuid primary key default gen_random_uuid(),
  label      text not null unique,
  starts_on  date not null,
  ends_on    date not null check (ends_on > starts_on),
  is_current boolean not null default false
);
create unique index one_current_year on academic_years (is_current) where is_current;

create table users (
  id         uuid primary key default gen_random_uuid(),
  role       user_role not null,
  login_id   text not null check (login_id ~ '^[A-Za-z0-9-]{1,20}$'),
  year_level smallint check (year_level in (1,2)),
  full_name  text not null check (char_length(full_name) between 2 and 80),
  status     account_status not null default 'active',
  created_at timestamptz not null default now(),
  check ((role = 'student') = (year_level is not null))
);
create unique index users_identity on users (role, lower(login_id), coalesce(year_level, 0));

-- PIN hashes live in their own table that no client role can read.
create table credentials (
  user_id         uuid primary key references users(id) on delete cascade,
  pin_hash        text not null,
  pin_salt        text not null,
  iterations      int  not null,
  failed_attempts int  not null default 0,
  locked_until    timestamptz,
  must_change_pin boolean not null default false,
  last_login_at   timestamptz
);

create table students     (user_id uuid primary key references users(id) on delete cascade,
                           class_id uuid not null, roll_no int not null check (roll_no > 0));
create table teachers     (user_id uuid primary key references users(id) on delete cascade);
create table office_staff (user_id uuid primary key references users(id) on delete cascade);
create table administrators (user_id uuid primary key references users(id) on delete cascade);

-- ---------- Academic structure --------------------------------------
create table subjects (
  id        uuid primary key default gen_random_uuid(),
  name      text not null unique,
  is_active boolean not null default true
);

create table classes (
  id               uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_years(id),
  year_level       smallint not null check (year_level in (1,2)),
  section          text not null default '',
  class_teacher_id uuid references users(id) on delete set null,
  unique (academic_year_id, year_level, section)
);
alter table students add constraint students_class_fk foreign key (class_id) references classes(id);
create unique index students_roll_in_class on students (class_id, roll_no);

create table teacher_assignments (
  id         uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references users(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  class_id   uuid not null references classes(id) on delete cascade,
  unique (teacher_id, subject_id, class_id)
);

-- ---------- Registration (pre-approval) -----------------------------
create table registrations (
  id                  uuid primary key default gen_random_uuid(),
  role                user_role not null check (role <> 'admin'),
  full_name           text not null,
  login_id            text not null,
  year_level          smallint check (year_level in (1,2)),
  section             text not null default '',
  subject_ids         uuid[] not null default '{}',
  year_levels         smallint[] not null default '{}',
  id_photo_path       text,
  id_photo_deleted_at timestamptz,
  status              review_status not null default 'pending',
  reject_reason       text,
  reviewed_by         uuid references users(id),
  reviewed_at         timestamptz,
  user_id             uuid references users(id),
  created_at          timestamptz not null default now(),
  check ((role = 'student') = (year_level is not null))
);
create unique index one_pending_registration
  on registrations (role, lower(login_id), coalesce(year_level, 0)) where status = 'pending';

create table registration_secrets (
  registration_id uuid primary key references registrations(id) on delete cascade,
  pin_hash text not null, pin_salt text not null, iterations int not null
);

-- ---------- Attendance ------------------------------------------------
create table attendance_sessions (
  id           uuid primary key default gen_random_uuid(),
  class_id     uuid not null references classes(id),
  subject_id   uuid not null references subjects(id),
  teacher_id   uuid not null references users(id),
  session_date date not null,
  period       smallint not null default 1 check (period between 1 and 12),
  created_at   timestamptz not null default now(),
  -- blocks duplicate attendance for the same class session
  unique (class_id, subject_id, session_date, period)
);

create table attendance_records (
  session_id uuid not null references attendance_sessions(id) on delete cascade,
  student_id uuid not null references users(id),
  status     att_status not null,
  updated_at timestamptz not null default now(),
  primary key (session_id, student_id)
);
create index att_records_student on attendance_records (student_id);

create table attendance_audit (
  id         bigint generated always as identity primary key,
  session_id uuid not null references attendance_sessions(id) on delete cascade,
  student_id uuid not null references users(id),
  old_status att_status,
  new_status att_status not null,
  reason     text not null,
  changed_by uuid not null references users(id),
  changed_at timestamptz not null default now()
);

-- ---------- Content (UI arrives in Stage 2) ---------------------------
create table notes (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id), class_id uuid not null references classes(id),
  teacher_id uuid not null references users(id), chapter text not null default 'General',
  title text not null, kind text not null check (kind in ('pdf','image','document','text')),
  body text, file_path text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table videos (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id), class_id uuid not null references classes(id),
  teacher_id uuid not null references users(id), chapter text not null default 'General',
  title text not null, url text, file_path text, created_at timestamptz not null default now()
);
create table live_classes (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id), class_id uuid not null references classes(id),
  teacher_id uuid not null references users(id), title text not null,
  scheduled_at timestamptz not null, join_url text not null,
  status text not null default 'scheduled' check (status in ('scheduled','live','ended'))
);

-- ---------- Examinations, marks, rankings (Stage 2) ---------------------
create table examinations (
  id uuid primary key default gen_random_uuid(),
  name text not null, class_id uuid not null references classes(id),
  starts_on date, default_max_marks numeric not null default 100 check (default_max_marks > 0),
  is_published boolean not null default false, created_at timestamptz not null default now()
);
create table marks (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references examinations(id), subject_id uuid not null references subjects(id),
  student_id uuid not null references users(id), entered_by uuid not null references users(id),
  marks_obtained numeric not null check (marks_obtained >= 0),
  max_marks numeric not null check (max_marks > 0),
  status text not null default 'draft' check (status in ('draft','published')),
  updated_at timestamptz not null default now(),
  unique (exam_id, subject_id, student_id),
  check (marks_obtained <= max_marks)
);
create table rankings (
  exam_id uuid not null references examinations(id), student_id uuid not null references users(id),
  total_obtained numeric not null, total_max numeric not null, percentage numeric not null,
  rank int not null, computed_at timestamptz not null default now(),
  primary key (exam_id, student_id)
);

-- ---------- Fees (Stage 2) ----------------------------------------------
create table fees (
  student_id uuid not null references users(id), academic_year_id uuid not null references academic_years(id),
  total_fee numeric not null check (total_fee >= 0), primary key (student_id, academic_year_id)
);
create table payments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references users(id), academic_year_id uuid not null references academic_years(id),
  amount numeric not null check (amount > 0), reference_no text not null unique,
  paid_on date not null default current_date, received_by uuid not null references users(id),
  is_void boolean not null default false, void_reason text, created_at timestamptz not null default now()
);

-- ---------- Communication & audit ---------------------------------------
create table notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references users(id) on delete cascade,
  kind text not null, title text not null, body text not null default '',
  is_read boolean not null default false, created_at timestamptz not null default now()
);
create table announcements (
  id uuid primary key default gen_random_uuid(), title text not null, body text not null,
  target_role user_role, class_id uuid references classes(id),
  created_by uuid not null references users(id), created_at timestamptz not null default now()
);
create table audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid, action text not null, entity text not null, entity_id text,
  details jsonb not null default '{}', at timestamptz not null default now()
);
create table app_settings (key text primary key, value jsonb not null);

-- ---------- Security helpers (read the caller from the signed token) ----
create function public.auth_role() returns user_role
language sql stable security definer set search_path = public as $$
  select role from users where id = auth.uid() and status = 'active'
$$;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.auth_role() = 'admin', false)
$$;

create function public.my_class_id() returns uuid
language sql stable security definer set search_path = public as $$
  select s.class_id from students s join users u on u.id = s.user_id
  where s.user_id = auth.uid() and u.status = 'active'
$$;

create function public.teaches(p_class uuid, p_subject uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from teacher_assignments ta join users u on u.id = ta.teacher_id
    where ta.teacher_id = auth.uid() and ta.class_id = p_class and ta.subject_id = p_subject
      and u.role = 'teacher' and u.status = 'active')
$$;

create function public.is_class_teacher(p_class uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from classes c join users u on u.id = c.class_teacher_id
    where c.id = p_class and c.class_teacher_id = auth.uid()
      and u.role = 'teacher' and u.status = 'active')
$$;

create function public.teaches_student(p_student uuid, p_subject uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from students s where s.user_id = p_student and public.teaches(s.class_id, p_subject))
$$;

create function public.school_today() returns date
language sql stable security definer set search_path = public as $$
  select (now() at time zone coalesce((select value #>> '{}' from app_settings where key = 'timezone'), 'Asia/Kolkata'))::date
$$;

create function public.low_threshold() returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from app_settings where key = 'low_attendance_threshold'), 75)
$$;

-- internal only (never granted to client roles)
create function public.write_audit(p_actor uuid, p_action text, p_entity text, p_entity_id text, p_details jsonb)
returns void language sql security definer set search_path = public as $$
  insert into audit_logs (actor_id, action, entity, entity_id, details) values (p_actor, p_action, p_entity, p_entity_id, coalesce(p_details, '{}'));
$$;

-- ---------- Integrity triggers -------------------------------------------
create function public.trg_class_teacher_check() returns trigger language plpgsql
security definer set search_path = public as $$
begin
  if new.class_teacher_id is not null
     and not exists (select 1 from users where id = new.class_teacher_id and role = 'teacher' and status = 'active') then
    raise exception 'The class teacher must be an active teacher account.';
  end if;
  if tg_op = 'UPDATE' and new.class_teacher_id is distinct from old.class_teacher_id then
    perform public.write_audit(auth.uid(), 'class.set_class_teacher', 'class', new.id::text,
      jsonb_build_object('from', old.class_teacher_id, 'to', new.class_teacher_id));
  end if;
  return new;
end $$;
create trigger classes_class_teacher before insert or update on classes
  for each row execute function public.trg_class_teacher_check();

create function public.trg_assignment_check() returns trigger language plpgsql
security definer set search_path = public as $$
begin
  if not exists (select 1 from users where id = new.teacher_id and role = 'teacher') then
    raise exception 'Only teacher accounts can be assigned to subjects.';
  end if;
  return new;
end $$;
create trigger assignments_teacher_only before insert or update on teacher_assignments
  for each row execute function public.trg_assignment_check();

create function public.trg_forbid_change() returns trigger language plpgsql as $$
begin raise exception 'Records in % cannot be changed or deleted.', tg_table_name; end $$;
create trigger payments_no_delete before delete on payments for each row execute function public.trg_forbid_change();
create trigger att_audit_no_delete before delete on attendance_audit for each row execute function public.trg_forbid_change();
create trigger att_audit_no_update before update on attendance_audit for each row execute function public.trg_forbid_change();
create trigger audit_no_delete before delete on audit_logs for each row execute function public.trg_forbid_change();
create trigger audit_no_update before update on audit_logs for each row execute function public.trg_forbid_change();

-- ---------- Seed data ----------------------------------------------------
insert into academic_years (label, starts_on, ends_on, is_current) values ('2026-27', '2026-06-01', '2027-03-31', true);
insert into subjects (name) values ('Physics'),('Chemistry'),('Mathematics'),('Biology'),('English'),('Hindi'),('Kannada');
insert into classes (academic_year_id, year_level, section)
  select a.id, v.y, '' from academic_years a, (values (1),(2)) v(y) where a.is_current;
insert into app_settings values ('low_attendance_threshold','75'), ('correction_window_days','7'), ('timezone','"Asia/Kolkata"');
