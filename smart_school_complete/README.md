# Smart School - Stage 1 + Stage 2

**No computer tools? Build the APK on GitHub: see `GITHUB_STEPS.md`.**

Flutter app + Supabase (Postgres, private file storage, Edge Functions). No Firebase, no email,
no Google sign-in, no OTP, no phone login. People sign in with **school ID + 6-digit PIN**.

## What Stage 1 contains
- Full database schema for every table in the brief (Stage 2 tables are created and locked down now).
- ID + PIN login (PBKDF2-hashed PINs, 5 wrong tries locks for 15 minutes, admin can reset PINs).
- Registration for Student / Teacher / Office with a live camera photo of the ID card.
- Administrator approval screen: zoomable ID photo, verification checklist, class/subject assignment.
  The photo is deleted from storage right after approve or reject.
- Complete attendance module: teacher P/A list, duplicate prevention, corrections with reason + audit
  history, class-teacher dashboard (whole class, all subjects, low-attendance list, CSV report),
  student My Attendance (overall %, per subject, daily history, monthly report, warnings, offline copy).

## What Stage 2 adds (migration 003 + new screens)
- **Examinations**: administrator creates exams per class (name, date, default max); students are notified.
- **Marks entry** (teacher): one student at a time in roll order, marks box with **Save** and **Next** side by side,
  Next also saves, progress bar, jump list, marks validated 0..max on the phone AND in the database, a teacher can
  only enter marks for their own subject and class, drafts are saved to the server as you go, a confirmation
  dialog before **Publish**, published marks are locked.
- **Authorised correction** (administrator only): reason required, written to the audit log, ranks recalculated automatically.
- **Results, percentage and rank** (student): subject-wise marks, total, percentage (from real maximum marks),
  PASS/FAIL (pass mark = setting `pass_percentage`, default 35), class rank with ties sharing a position (1,2,2,4),
  different congratulation pop-ups for ranks 1, 2, 3, 4-5 and the rest, class merit list (setting `show_merit_list`),
  report card PDF, offline copy.
- **Fees**: office searches by roll number (exact match only) or name, sets total fees, adds payments. Remaining is always
  computed (total minus payments), never stored. Duplicate reference numbers and accidental double entries are blocked,
  a payment can never exceed the balance, payments cannot be edited or deleted; a wrong payment is **voided** by the
  administrator with a reason and stays visible. Student **My Fees** with history and PDF receipts.
- **Notes, videos, live classes**: teachers upload PDF / image / document / text notes by chapter, add video links or
  upload videos (50 MB max), schedule and start live classes; students see only their own class. Files sit in a private
  bucket and open through short-lived signed links.
- **Live classes** use Jitsi Meet (video, microphone, screen sharing) or any Meet/Zoom link the teacher pastes.
  The public Jitsi server may ask the teacher to sign in once to start a meeting; use your own link if you prefer.
- **Notifications** (new notes, videos, live classes, exams, results, fee payments, announcements) with a bell icon.
  These are in-app notifications; phone push notifications are not included (see limits).
- **Announcements**, **subjects** (add / switch off), **fee summary**, **audit log** in the administrator's School tab.
- **Study Assistant**: rule-based advice from the student's own verified marks and attendance (weak subjects,
  drops, improvement, low-attendance subjects). It reads data only and can never create, change or publish marks.

## Requirements
Flutter 3.27 or newer (Android SDK installed), Node 18+ for the Supabase CLI.

## Setup (about 30 minutes)

### 1. Create the Supabase project
Create a project at supabase.com. Note the **Project URL**, the **anon key**, and (Settings > API) the
**JWT secret** (legacy HS256 secret). Keep the service key private.

### 2. Create the database
Open SQL Editor and run, in order: `001_schema.sql`, `002_security_and_attendance.sql`, then `003_stage2.sql` (all in `supabase/migrations`).
Optionally run `supabase/tests/stage1_security_test.sql` and `stage2_test.sql` to verify the rules (they roll back).
Migration 003 closes direct writes to `marks` and `payments` so every change goes through the checked functions.

### 3. Deploy the Edge Functions
```bash
npm i -g supabase
supabase login && supabase link --project-ref <your-ref>
supabase secrets set APP_JWT_SECRET="<project JWT secret>" SETUP_SECRET="<any long random string>"
supabase functions deploy login register session admin bootstrap-admin --no-verify-jwt
```

### 4. Create the first administrator (once)
```bash
curl -X POST "https://<ref>.supabase.co/functions/v1/bootstrap-admin" \
  -H "x-setup-secret: <SETUP_SECRET>" -H "Content-Type: application/json" \
  -d '{"login_id":"ADMIN01","full_name":"Principal Name","pin":"<6 digits>"}'
```
It refuses to run again once an administrator exists.

### 5. Prepare the Android project
```bash
bash scripts/setup_android.sh
flutter test
```
Replace `assets/logo.png` with the school's official logo (square PNG, 512x512 recommended).

### 6. Build the APK
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key> \
  --dart-define=SCHOOL_NAME="Your School Name"
```
Output: `build/app/outputs/flutter-apk/app-release.apk`. For Play Store distribution, add your own
release signing key (https://docs.flutter.dev/deployment/android).

## First-run walkthrough
1. Sign in as Administrator (Admin ID + PIN) > Classes: add sections if needed.
2. On other phones: register a teacher and a few students (camera photo of the ID card).
3. Administrator > Approvals: review photo, tick checks, assign class/subjects, approve.
4. Administrator > Classes: choose the class teacher.
5. Teacher signs in > tap a subject > mark P/A > Submit attendance.
6. Student signs in > My Attendance.
7. Administrator > School > Examinations > New exam. Teacher > subject > Marks > pick the exam > enter, Save, Next > Publish.
8. Student > Examination Results / Percentage & Rank.
9. Office signs in > search roll number > Set total fees > Add payment. Student > My Fees.

## Security notes
- PINs are never stored in readable form; hashes sit in a table no app role can read.
- Every table has row-level security; attendance can only be written through checked database functions.
- ID photos live in a private bucket, readable only by the administrator, under random file names.
- Registrations with a wrong ID photo can be rejected; one ID can be tried at most 3 times per 24 hours.
- Weak PINs (123456, 111111, your own roll number) are refused.

## Known limits (read before going live)
- Not included: phone push notifications (needs Firebase Cloud Messaging; the in-app bell works), academic-year rollover
  and promoting students to the next year, parent accounts, an LLM-based assistant (the assistant is rule-based on purpose).
- PDFs (receipts, report cards) use a built-in font: names in Kannada/Hindi will not print unless a Unicode font is bundled.
- Backups: Supabase takes daily backups on paid plans; on the free plan export the database yourself regularly.
- Stage 2 was written without being compiled or run (no Flutter/Postgres in the build environment). Run `flutter test`,
  both SQL tests and the walkthrough before real use, and send any error to the developer.
- "Verification" is the administrator comparing the photo with the typed details. Automatic OCR is not
  reliable enough to trust for identity, so it is not used.
- A camera-only capture discourages but cannot fully prevent a fake photo; the administrator check is the control.
- The token is signed with Supabase's legacy JWT secret. If Supabase retires that secret for your project,
  the signing step in `_shared/common.ts` must move to the new signing-key method.
- Roll numbers must be unique within a year across all sections (a login is roll number + year).
- A rejected registration is reported at sign-in without needing the PIN (the PIN is discarded on rejection); the message contains no personal data.
- Stage 1 was not compiled or run end-to-end by its author (no Flutter/Postgres available there). Run `flutter test`, the SQL test, and the walkthrough above before real use.
