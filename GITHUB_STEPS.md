# Build the APK with GitHub (no Android Studio)

1. Supabase: create a project. Note Project URL, anon key, JWT secret. In SQL Editor run `supabase/migrations/001`, `002`, `003` in order.
2. Create an access token at supabase.com/dashboard/account/tokens.
3. GitHub: new PRIVATE repository, upload everything in this folder (check that `.github/workflows` has 3 files).
4. Settings > Secrets and variables > Actions > add: SUPABASE_URL, SUPABASE_ANON_KEY, SCHOOL_NAME, SUPABASE_PROJECT_REF,
   SUPABASE_ACCESS_TOKEN, APP_JWT_SECRET, SETUP_SECRET (any long random text).
5. Actions tab > run "Deploy backend (Supabase functions)", then "Create first administrator (run once)", then "Build APK".
6. Download the artifact `smart-school-apk`, unzip, install `app-release.apk` on the phone.
7. Replace `assets/logo.png` with your logo before building (upload it to the repo, same name).
