---
name: extend-time-vault-lock
description: >-
  Locks or extends Time Vault (leverage photo) timers in Fly staging or
  production via StartTimerServer (first encrypt / relock) or AddTimeServer
  (wrap an active blob). Use when the user asks to add lock time, start a
  timer, encrypt/re-encrypt, add 24h/7d of verrouillage, or lock a random or
  specific photo for TIME_VAULT_LOCK_EMAIL or another account.
---

# Extend Time Vault Lock

Lock or extend one or more `LeveragePhoto` rows with the same dispatch as `BetaEvents::Actions::LeveragePhotoLockFromEvent`:

- `can_add_time?` → `LeveragePhotos::AddTimeServer` (active photo: wrap the existing tlock blob)
- `can_start_timer?` → `LeveragePhotos::StartTimerServer` (draft: first encrypt of `original_image`; unlocked: encrypt original if present, else wrap the remaining blob)

Never `update!` `locked_until` alone. Never call `StartTimer` / `AddTime` with a hand-built blob.

Run from the repo (or any dir with Fly auth). Execute the helper; do not reinvent the runner.

## Defaults

| Input | Default |
| --- | --- |
| Environment | Production (`dc-backend`) unless the user says staging |
| Email | `$TIME_VAULT_LOCK_EMAIL` unless another account is named |
| Duration | Random inclusive range **24h–7 days** unless a duration is given |
| Target | **1 random** eligible photo unless ids or a count are given |

Omit `--email` for the default account. The script reads `TIME_VAULT_LOCK_EMAIL` from the environment, then repo-root `.env`, then `backend/.env`. Pass `--email` only when the user names another account.

Eligible means `eligible_for_lock?` (`can_start_timer?` or `can_add_time?`). Random picks prefer already-locked photos, then drafts/unlocked — same as `LeveragePhotos::ResolveTarget` for `lock`.

`StartTimerServer` duration must stay in `MIN_DURATION_SECONDS`–`MAX_DURATION_SECONDS` (1 minute–365 days). `AddTimeServer` only requires `added_seconds > 0`.

## Command

```bash
bash .cursor/skills/extend-time-vault-lock/scripts/extend_lock.sh \
  --prod \
  --duration random \
  --count 1
```

| Flag | Meaning |
| --- | --- |
| `--prod` / `--staging` | Fly app (`dc-backend` / `dc-backend-staging`) |
| `--email` | Owner of the photos (overrides `$TIME_VAULT_LOCK_EMAIL`) |
| `--duration` | `random`, integer seconds, or `24h` / `7d` / `90m` |
| `--count N` | N distinct random eligible photos |
| `--ids 388,12` | Those ids only (must belong to `--email` and be eligible). Ignores `--count` |

Per-photo duration: `random` is drawn independently. A given spec is applied to every selected photo. For `add_time` it is **added** on top of `locked_until`; for `start_timer` it is the lock length **from now**.

Wait **30s + ~25s per photo** (`block_until_ms`). Encryption downloads/uploads the blob.

## Mapping user requests

- "une photo au hasard" / "a random photo" → `--count 1`
- "plusieurs" / "3 photos" → `--count 3`
- "la photo 388" / "these ids" → `--ids 388` (comma-separated)
- "24h" / "7 jours" / "3 hours" → `--duration 24h` (or `7d` / `3h`)
- no duration given → `--duration random`

## Output

Report each photo **id**, `action` (`add_time` or `start_timer`), added duration, `locked_until` before/after, and `tlock_layer_count`. Quote ids from the JSON `results` array. If the command fails (unknown email, ineligible ids, layer cap, duration out of range), do not retry with a direct SQL/`update!` bypass.

## Guardrails

- Scope strictly to the given email. Do not pick another user's photos.
- Do not run this against the local database unless the user explicitly targets local.
- Production mutation is expected when they say prod / "en prod" / give the live account.
