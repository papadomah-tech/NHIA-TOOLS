# NHIA M&E Tools

**Provider Monitoring & Evaluation — Progressive Web App**  
Ghana National Health Insurance Authority · NHIA

---

## Overview

NHIA M&E Tools is an offline-capable Progressive Web App built for NHIA field monitoring teams to assess health service provider compliance during on-site visits. The app replaces paper forms and Google Sheets, giving teams a structured workflow for creating monitoring assignments, conducting facility visits, scoring six assessment modules, and generating a consolidated printable report for submission to MRO HQ.

| | |
|---|---|
| **Platform** | Progressive Web App — runs in any modern browser, installable on Android and desktop |
| **Backend** | Supabase (Auth, PostgreSQL, Realtime) |
| **Hosting** | GitHub Pages or any static host |
| **Offline** | Full offline support via Service Worker and IndexedDB queue |

---

## File structure

```
nhia_me_tools/
├── index.html      Main application (single-file PWA)
├── manifest.json   Web app manifest (icons, theme, display mode)
├── sw.js           Service worker (offline cache + sync queue)
└── schema.sql      Supabase database schema
```

---

## User roles

The app has two roles, managed in the `user_profiles` table by IT administrators.

| Role | Can do | Cannot do |
|---|---|---|
| Team Leader | Create assignments, add facility visits, close visits, generate reports | See other teams' data |
| Team Member | Open and score assessment modules for assigned visits | Create assignments or close visits |

---

## Monitoring workflow

### 1. Assignment creation (Team Leader)

The Team Leader opens the app and taps New Assignment. They enter the monitoring period (e.g. Q2 2026), the district or region, and the names of team members. Assignments are created outside the app verbally or by email and only reflected inside it at this point. One monitoring period per team is active at a time.

### 2. Adding facility visits (Team Leader)

Within an assignment the Team Leader adds each facility to be visited: a health facility or a district office visit. Each visit has a name, type, date, and optional pre-visit notes.

### 3. Module assessment (Team Members)

Team Members open a visit and score each of the six modules. Each module presents a set of indicators with Yes/No/Partial drop-downs, numeric count fields, or free-text observation boxes. The app stores responses locally and syncs to Supabase when online.

### 4. Closing visits and generating a report (Team Leader)

Once a facility visit is complete the Team Leader closes it. When all visits are closed the Team Leader generates a consolidated report from the Assignment detail screen. The report downloads as a printable HTML file and is sent manually to MRO HQ.

---

## Assessment modules

| Module | Name | What it covers |
|---|---|---|
| M1 | Administrative | Accreditation, staff list, claims register, complaints mechanism, SLA copy |
| M2 | Folder verification | Patient folder sampling, NHIS card validity, diagnosis accuracy, ghost records, exemption compliance |
| M3 | Claims audit | Claims-to-folder matching, tariff coding, upcoding, submission timelines, rejected claims |
| M4 | Clinical | Protocols, drug-diagnosis match, rational drug use, referrals, infection prevention |
| M5 | Facility resources | Equipment, drug supply, cleanliness, staffing levels, water and sanitation |
| M6 | Financial / FPHC | Co-payment compliance, free primary health care for eligible beneficiaries, financial record reconciliation |

---

## Supabase setup

### Step 1 — Create a Supabase project

Go to [supabase.com](https://supabase.com), create a new project, and note the Project URL and anon public key from **Project Settings → API**.

### Step 2 — Run the schema

Open the SQL Editor in your Supabase dashboard. Create a new query, paste the full contents of `schema.sql`, and click Run. This creates four tables with row-level security and Realtime enabled:

- `user_profiles` — role and team assignment for each user
- `assignments` — monitoring periods and team metadata
- `visits` — individual facility visits within each assignment
- `module_scores` — JSONB responses per module per visit

### Step 3 — Create user accounts

Go to **Authentication → Users → Add user**. Enter the email and password for each staff member. Copy their UUID from the users list. Then run the following insert in the SQL Editor:

```sql
insert into public.user_profiles (id, display_name, role, team_id)
values
  ('LEADER-UUID', 'Ama Owusu',   'leader', 'a1b2c3d4-0000-0000-0000-000000000001'),
  ('MEMBER-UUID', 'Kofi Mensah', 'member', 'a1b2c3d4-0000-0000-0000-000000000001');
```

Team members sharing a `team_id` form one team. Team Leaders only see assignments and visits belonging to their own `team_id`.

### Step 4 — Configure the app

Open `index.html` in a text editor. Near the top of the `<script>` block, replace the two placeholder values:

```js
const SUPABASE_URL = 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_KEY = 'YOUR_ANON_KEY';
```

---

## Deployment

### GitHub Pages

1. Push the three files (`index.html`, `manifest.json`, `sw.js`) to a GitHub repository.
2. Go to the repository **Settings → Pages** and select the main branch and root folder.
3. GitHub provides a public URL in the format `https://username.github.io/repo-name`.
4. Field officers open this URL in Chrome on Android and use **Add to Home Screen** to install the PWA.

### Any static host

The app is three static files. Any host that serves HTML (Netlify, Vercel, a government web server) works without a build step.

---

## Offline behaviour

The service worker caches `index.html` and `manifest.json` on first load. All data entry writes to IndexedDB immediately. If the device is offline when a record is saved, the app queues the write and shows a pending badge in the top bar. When the connection returns the queue flushes automatically. Supabase Realtime subscriptions keep assignments and visits in sync across devices on the same team without polling.

---

## Support and administration

| Responsibility | Owner |
|---|---|
| User account creation and deactivation | IT administrator |
| Role changes (leader ↔ member) | IT administrator via Supabase dashboard |
| Assignment and visit data | Stored in Supabase PostgreSQL |
| Report distribution | Downloaded as HTML by the Team Leader and emailed manually to MRO HQ |

---

*Ghana National Health Insurance Authority · NHIA M&E Division*
