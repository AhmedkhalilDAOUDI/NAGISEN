# Switching on Feed push notifications

Likes, comments and follows can reach members' iPhones as notifications. The app, the database
triggers (`push.sql`) and the sender (`functions/notify`) are ready; they need a paid Apple
Developer account to work. Until these steps are done, nothing is sent and nothing breaks.

1. **Apple key.** In the Apple Developer site, Certificates, IDs & Profiles → Keys → add a key with
   *Apple Push Notifications service (APNs)*. Download the `.p8` file once and note its Key ID and
   your Team ID. In Identifiers, make sure `com.daywell.nutrition` has Push Notifications enabled.
2. **Deploy the sender.** With the Supabase CLI, from this folder's parent:
   `supabase functions deploy notify --no-verify-jwt`
3. **Function secrets.** In Supabase → Edge Functions → notify → Secrets, add:
   - `APNS_KEY_ID`, `APNS_TEAM_ID`: from step 1
   - `APNS_PRIVATE_KEY`: the whole contents of the `.p8` file
   - `APNS_BUNDLE_ID`: `com.daywell.nutrition`
   - `APNS_PRODUCTION`: `false` for builds from Xcode, `true` for TestFlight and the App Store
   - `PUSH_WEBHOOK_SECRET`: any long random string
4. **Vault.** In Supabase → Project Settings → Vault, add two secrets:
   - `push_webhook_secret`: the same random string as above
   - `project_url`: `https://<your project ref>.supabase.co`
5. **Database.** Run `push.sql` in the SQL Editor.
6. **App.** Build with your paid team (the regular build, not the personal one). Members turn
   notifications on in Account → Notifications.
