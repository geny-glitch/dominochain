<wizard-report>
# PostHog post-wizard report

The wizard has completed a deep integration of PostHog analytics into this Ruby on Rails application. The project already had `posthog-ruby` and `posthog-rails` gems installed, an initializer configured with auto-exception capture and ActiveJob instrumentation, and many key events already tracked. This session extended that coverage with 8 new events across 5 files, filling gaps in web login, Chaster/Strava lifecycle, control request rejection, Strava goal management, and showcase game completions.

## Changes made

- **`.env`** — Updated `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST` with correct values.
- **`app/controllers/sessions_controller.rb`** — Added `web_login` event + `PostHog.identify` on successful web sign-in via Devise. ✨
- **`app/controllers/controls_controller.rb`** — Added `control_request_rejected` event in `reject_request`. ✨
- **`app/controllers/chaster_controller.rb`** — Added `chaster_connected` on OAuth callback success and `chaster_disconnected` on disconnect. ✨
- **`app/controllers/strava_controller.rb`** — Added `strava_disconnected`, `strava_goal_destroyed`, and `strava_goal_checked` (with `status`, `valid_count`, `required_count` properties). ✨
- **`app/controllers/showcase_controller.rb`** — Added `showcase_game_completed` (with `game_kind` and `seconds_added`) on successful time addition. ✨

## Event tracking summary

| Event | Description | File |
|---|---|---|
| `user_logged_in` | User authenticated via API login | `app/controllers/api/auth_controller.rb` |
| `user_registered` | New beta user registered (API or web) | `app/controllers/api/auth_controller.rb`, `app/controllers/registrations_controller.rb` |
| `user_logged_out` | User logged out via API | `app/controllers/api/auth_controller.rb` |
| `boss_registered` | New boss user registered via web | `app/controllers/boss_registrations_controller.rb` |
| `web_login` ✨ | User authenticated via web (Devise session) | `app/controllers/sessions_controller.rb` |
| `control_request_sent` | Beta user sent a control request to a boss | `app/controllers/api/control_requests_controller.rb` |
| `control_accepted` | Boss accepted control (via link or request) | `app/controllers/controls_controller.rb` |
| `control_released` | Boss released control over a beta user | `app/controllers/controls_controller.rb` |
| `control_request_rejected` ✨ | Boss rejected a control request | `app/controllers/controls_controller.rb` |
| `task_created` | Boss created a task for a beta user | `app/controllers/tasks_controller.rb` |
| `task_proof_reviewed` | Boss reviewed task completion proof | `app/controllers/tasks_controller.rb` |
| `task_punishment_sent` | Boss sent a punishment for an expired task | `app/controllers/tasks_controller.rb` |
| `chaster_connected` ✨ | Beta user connected their Chaster account | `app/controllers/chaster_controller.rb` |
| `chaster_disconnected` ✨ | Beta user disconnected their Chaster account | `app/controllers/chaster_controller.rb` |
| `chaster_time_added` | Time added to a Chaster lock via API | `app/controllers/api/chaster_controller.rb` |
| `cigarette_entry_logged` | Beta user logged cigarette consumption | `app/controllers/api/cigarette_entries_controller.rb` |
| `strava_connected` | Beta user connected their Strava account | `app/controllers/strava_controller.rb` |
| `strava_disconnected` ✨ | Beta user disconnected their Strava account | `app/controllers/strava_controller.rb` |
| `strava_goal_created` | Beta user created a Strava goal | `app/controllers/strava_controller.rb` |
| `strava_goal_destroyed` ✨ | Beta user deleted a Strava goal | `app/controllers/strava_controller.rb` |
| `strava_goal_checked` ✨ | Strava goal manually checked (pass/fail result) | `app/controllers/strava_controller.rb` |
| `showcase_game_completed` ✨ | Showcase game ended, time added to lock | `app/controllers/showcase_controller.rb` |

✨ = newly added in this session

## Next steps

We've built some insights and a dashboard for you to keep an eye on user behavior, based on the events we just instrumented:

- [Analytics basics dashboard](/dashboard/674635)
- [New User Registrations](/insights/jCDaF0Ys) — Beta and boss signups over time (weekly, 90 days)
- [User Login Activity](/insights/UGnGIdfg) — Unique daily web vs API logins (30 days)
- [Control Request Conversion Funnel](/insights/EcSX6X4H) — `control_request_sent` → `control_accepted` conversion (90 days)
- [Task Management Activity](/insights/P5vbv0Li) — Tasks created, proofs reviewed, punishments sent (30 days)
- [Integration Adoption](/insights/r4SrdBKi) — Chaster and Strava connections over time (weekly, 90 days)

### Agent skill

We've left an agent skill folder in your project at `.claude/skills/integration-ruby-on-rails/`. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.

</wizard-report>
