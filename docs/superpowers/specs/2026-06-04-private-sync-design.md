# Aslan Private Sync Design

## Context

Aslan is a private fork of Kazumi for personal use and sharing with a small circle of friends. The app currently keeps local watch history and collection state in Hive. Kazumi's original WebDAV sync is present in Aslan but hidden behind `AppFeatureFlags.webDavSync == false`.

LaevaBangumi is the existing data-source backend used by Aslan. It provides public anime metadata/resource APIs, uses Node.js ESM, Express 5, SQLite through `better-sqlite3`, and runs scheduled resource fetching in the same process. It does not currently have users, authentication, or private per-device state.

The new sync feature should provide convenient cross-device tracking for:

- Watch history and per-episode playback progress.
- Collection/following status such as watching, plan to watch, watched, on hold, and abandoned.

This design targets a private/small-scale deployment. It should not overbuild a public account platform, but it must keep each friend user's private sync data isolated.

## Goals

1. Let one user sync Aslan state across multiple devices.
2. Let multiple small-circle users share the same LaevaBangumi instance without mixing their private state.
3. Keep Aslan offline-first: local Hive remains the immediate source of truth in the UI.
4. Use server-side merge as the authoritative cross-device conflict resolver.
5. Reuse Aslan/Kazumi's existing event-based watch-history merge concepts.
6. Replace WebDAV/Hive-file transport with structured HTTP JSON APIs.
7. Keep the backend deployable in the existing LaevaBangumi process at first, with clean boundaries for later extraction.

## Non-Goals

- Public registration, OAuth, password login, or social features.
- Real-time collaborative sync.
- Large-scale multi-tenant operations.
- Syncing Aslan settings, plugin state, downloaded files, danmaku cache, or search history.
- Directly syncing watch history to Bangumi.tv.
- Continuing to use WebDAV `.tmp` Hive box files for new collection sync.

## Design Summary

Add a private sync domain to LaevaBangumi. The domain has manually provisioned users, user tokens, devices, immutable events, and materialized current state tables. Aslan writes local changes into a pending event log, then periodically calls a single merge endpoint. The server authenticates the token, stores events idempotently, merges them into current state inside a SQLite transaction, and returns the latest user snapshot. Aslan applies that snapshot back to local Hive.

This keeps the client simple and resilient: local changes work offline, duplicate uploads are harmless, and conflict resolution is centralized.

## Backend Architecture

### Process Boundary

Initial deployment should keep sync routes inside the LaevaBangumi Express app:

- Existing public routes remain read-only and unauthenticated.
- New private routes live under `/api/sync/*`.
- Sync repositories and services are separate from public anime/resource repositories.
- Scheduled resource fetching does not depend on sync requests.

This is acceptable for a small deployment because SQLite WAL and short transactions are enough for expected traffic. If sync or crawler workloads start affecting each other, the sync domain can later move to a separate process using the same SQLite file or a migrated database.

### Authentication

Use manually provisioned bearer tokens.

- Each person gets one `sync_user`.
- Each user has one or more token hashes.
- The server never stores raw tokens.
- Tokens are created by an admin script, copied once, and entered in Aslan settings.
- Requests use `Authorization: Bearer <token>`.

This avoids public registration while still isolating each friend's data.

### Devices

Each Aslan install has a stable `deviceId`, already similar to Kazumi's `historySyncDeviceId`. A device registration endpoint stores:

- `device_id`
- `user_id`
- human-readable device name
- platform string if available
- app version if available
- last seen time

Device registration is idempotent.

## Data Model

Use SQLite tables in LaevaBangumi. Column names follow the existing snake_case style.

### Users and Tokens

`sync_users`

- `user_id INTEGER PRIMARY KEY AUTOINCREMENT`
- `display_name TEXT NOT NULL`
- `created_at TEXT NOT NULL DEFAULT (datetime('now'))`
- `disabled_at TEXT`

`sync_tokens`

- `token_id INTEGER PRIMARY KEY AUTOINCREMENT`
- `user_id INTEGER NOT NULL REFERENCES sync_users(user_id) ON DELETE CASCADE`
- `token_hash TEXT NOT NULL UNIQUE`
- `label TEXT`
- `created_at TEXT NOT NULL DEFAULT (datetime('now'))`
- `last_used_at TEXT`
- `revoked_at TEXT`

`sync_devices`

- `user_id INTEGER NOT NULL REFERENCES sync_users(user_id) ON DELETE CASCADE`
- `device_id TEXT NOT NULL`
- `device_name TEXT`
- `platform TEXT`
- `app_version TEXT`
- `first_seen_at TEXT NOT NULL DEFAULT (datetime('now'))`
- `last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))`
- primary key: `(user_id, device_id)`

### Immutable Event Log

`sync_events`

- `user_id INTEGER NOT NULL REFERENCES sync_users(user_id) ON DELETE CASCADE`
- `event_id TEXT NOT NULL`
- `device_id TEXT NOT NULL`
- `seq INTEGER NOT NULL`
- `domain TEXT NOT NULL` with values `watch` or `collection`
- `op TEXT NOT NULL`
- `entity_key TEXT`
- `bangumi_id INTEGER`
- `updated_at_ms INTEGER NOT NULL`
- `version TEXT NOT NULL`
- `payload_json TEXT NOT NULL`
- `received_at TEXT NOT NULL DEFAULT (datetime('now'))`
- primary key: `(user_id, event_id)`
- index: `(user_id, domain, version)`
- index: `(user_id, device_id, seq)`

`event_id` is generated client-side as `<deviceId>:<seq>` for normal events. Local import events may use a stable prefix such as `local-import:<deviceId>:<domain>:<entity>`.

`version` is the lexicographic merge key:

```text
updatedAtMs padded to 16 digits + "|" + eventId
```

This preserves Kazumi's existing deterministic last-write-wins ordering.

### Watch History State

`watch_history_items`

- `user_id INTEGER NOT NULL`
- `entity_key TEXT NOT NULL`
- `bangumi_id INTEGER NOT NULL`
- `adapter_name TEXT NOT NULL`
- `last_watch_episode INTEGER NOT NULL`
- `last_watch_time_ms INTEGER NOT NULL`
- `last_src TEXT`
- `last_watch_episode_name TEXT`
- `bangumi_item_json TEXT NOT NULL`
- `item_version TEXT NOT NULL`
- `deleted_version TEXT`
- primary key: `(user_id, entity_key)`

`watch_progress`

- `user_id INTEGER NOT NULL`
- `entity_key TEXT NOT NULL`
- `episode INTEGER NOT NULL`
- `road INTEGER NOT NULL`
- `progress_ms INTEGER NOT NULL`
- `progress_version TEXT NOT NULL`
- primary key: `(user_id, entity_key, episode)`

`watch_clear_state`

- `user_id INTEGER PRIMARY KEY`
- `clear_version TEXT`

`entity_key` remains compatible with Aslan's current local key: `adapterName + bangumiId`.

### Collection State

`collection_items`

- `user_id INTEGER NOT NULL`
- `bangumi_id INTEGER NOT NULL`
- `type INTEGER NOT NULL`
- `collected_at_ms INTEGER`
- `updated_at_ms INTEGER NOT NULL`
- `bangumi_item_json TEXT NOT NULL`
- `item_version TEXT NOT NULL`
- `deleted_version TEXT`
- primary key: `(user_id, bangumi_id)`

`collection_clear_state`

- `user_id INTEGER PRIMARY KEY`
- `clear_version TEXT`

Collection type values should match Aslan's existing `CollectType` values:

- `1`: watching
- `2`: plan to watch
- `3`: on hold
- `4`: watched
- `5`: abandoned

### Subject Prewarm Integration

The sync domain may reference `subjects(bangumi_id)` but should not require a subject row to already exist. When a sync event includes a `bangumi_id` unknown to LaevaBangumi:

1. Store the user's private state anyway.
2. Insert or update a minimal subject snapshot if `bangumi_item_json` contains enough metadata.
3. Enqueue existing metadata/mapping/episode refresh jobs asynchronously.

Sync success must not depend on resource prewarm success.

## API Design

All sync responses should use the existing LaevaBangumi envelope style.

### `POST /api/sync/register-device`

Authenticates the token and upserts the device row.

Request:

```json
{
  "deviceId": "uuid",
  "deviceName": "MacBook Pro",
  "platform": "macos",
  "appVersion": "x.y.z"
}
```

Response:

```json
{
  "data": {
    "user": { "displayName": "Alice" },
    "deviceId": "uuid"
  },
  "meta": { "updatedAt": "2026-06-04T00:00:00.000Z" }
}
```

### `POST /api/sync/merge`

Uploads pending local events and returns the latest server snapshot for the authenticated user.

Request:

```json
{
  "deviceId": "uuid",
  "clientSeq": 42,
  "events": [
    {
      "eventId": "uuid:42",
      "deviceId": "uuid",
      "seq": 42,
      "domain": "watch",
      "op": "watch.upsertProgress",
      "updatedAt": 1780500000000,
      "entityKey": "LaevaBangumi12345",
      "bangumiId": 12345,
      "payload": {}
    }
  ],
  "snapshotVersion": null
}
```

Response:

```json
{
  "data": {
    "acceptedEventIds": ["uuid:42"],
    "ignoredDuplicateEventIds": [],
    "snapshot": {
      "generatedAt": 1780500001000,
      "watch": {
        "clearVersion": null,
        "histories": []
      },
      "collection": {
        "clearVersion": null,
        "items": []
      }
    }
  },
  "meta": { "updatedAt": "2026-06-04T00:00:01.000Z" }
}
```

The first implementation can return a full snapshot. For the expected small data size, this is simpler and robust. Delta snapshots can be added later with cursors if needed.

### `GET /api/sync/status`

Returns token validity, current user, registered devices, and summary counts.

Response:

```json
{
  "data": {
    "user": { "displayName": "Alice" },
    "devices": [],
    "watchHistoryCount": 0,
    "collectionCount": 0
  },
  "meta": { "updatedAt": "2026-06-04T00:00:00.000Z" }
}
```

## Event Payloads

### Watch Upsert

`op = watch.upsertProgress`

Payload:

```json
{
  "entityKey": "LaevaBangumi12345",
  "adapterName": "LaevaBangumi",
  "bangumiId": 12345,
  "bangumiItem": {},
  "episode": 3,
  "road": 0,
  "progressMs": 652000,
  "lastSrc": "https://...",
  "lastWatchEpisodeName": "第 3 话"
}
```

Merge behavior:

- Ignore if event version is not newer than user `watch_clear_state.clear_version`.
- Ignore if there is a newer or equal `deleted_version` for the same `entity_key`.
- Update item metadata when event version is newer or equal to `item_version`.
- Update one episode progress when event version is newer or equal to that episode's `progress_version`.
- Clear `deleted_version` when the upsert wins.

### Watch Delete

`op = watch.deleteHistory`

Payload:

```json
{
  "entityKey": "LaevaBangumi12345"
}
```

Merge behavior:

- If newer than item and previous delete versions, remove item and progress rows.
- Store `deleted_version` tombstone for that `entity_key`.

Implementation note: because deleting the item row would lose the tombstone, use either a tombstone row in `watch_history_items` or a separate `watch_deleted_items` table. A separate tombstone table is cleaner if the implementation wants `watch_history_items` to contain only live rows.

### Watch Clear

`op = watch.clearAll`

Payload:

```json
{}
```

Merge behavior:

- If newer than existing `clear_version`, remove all live watch rows for the user.
- Remove per-item delete tombstones older than the clear if separate tombstone tables are used.
- Store the new `clear_version`.

### Collection Upsert

`op = collection.upsert`

Payload:

```json
{
  "bangumiId": 12345,
  "type": 1,
  "bangumiItem": {},
  "collectedAt": 1780500000000
}
```

Merge behavior:

- Ignore if event version is not newer than `collection_clear_state.clear_version`.
- Ignore if there is a newer or equal delete tombstone for this `bangumi_id`.
- Upsert `collection_items` when event version is newer or equal to `item_version`.
- Clear the delete tombstone when the upsert wins.

### Collection Delete

`op = collection.delete`

Payload:

```json
{
  "bangumiId": 12345
}
```

Merge behavior:

- If newer than item and previous delete versions, remove the collection row.
- Store a tombstone for `bangumi_id`.

### Collection Clear

`op = collection.clearAll`

Payload:

```json
{}
```

Merge behavior:

- If newer than existing clear version, remove all collection rows for the user.
- Store the new clear version.

## Client Architecture

### Local State

Aslan continues using existing Hive boxes:

- `histories`
- `collectibles`
- `collectchanges` can remain for legacy WebDAV compatibility but should not be used for the new HTTP sync.

Add a new local pending event log for HTTP sync. It can initially reuse the JSONL approach used by `HistorySyncService`, but it should cover both watch and collection domains.

Suggested local file:

```text
<ApplicationSupportDirectory>/sync/private-sync.local.jsonl
```

### Client Services

Add a sync transport abstraction:

- `PrivateSyncApi`: HTTP client for `/api/sync/*`.
- `PrivateSyncService`: local event append/read/replace, merge orchestration, and snapshot application.
- Domain codecs for watch history and collection events/snapshots.

The old WebDAV implementation can remain hidden or be removed later. The new private sync should not depend on `AppFeatureFlags.webDavSync`.

### Event Creation

Watch history:

- Preserve current behavior that playback updates local history while playing.
- Do not upload every second.
- Append a sync event only when progress changed meaningfully, such as:
  - episode changed,
  - road changed,
  - progress advanced by at least 15-30 seconds,
  - playback is paused/stopped,
  - app is backgrounded.

Collection:

- When user adds, changes, or deletes a collection item, update Hive first and append a collection sync event.
- On first sync enablement, convert current Hive collection rows into `collection.upsert` import events.

### Sync Triggers

Aslan should attempt sync:

- After app startup if sync is enabled.
- When the user taps manual sync.
- When app moves to background.
- After a collection mutation.
- Periodically during long playback, with a conservative debounce.

### Snapshot Application

After a successful merge response:

1. Apply watch snapshot to `GStorage.histories`.
2. Apply collection snapshot to `GStorage.collectibles`.
3. Clear only the uploaded local pending events acknowledged by the server.
4. Refresh MobX controllers where needed.

If snapshot application fails, keep pending events so a later sync can retry. The server accepts duplicate events idempotently.

### Privacy Mode

Aslan's current privacy mode semantics remain:

- Do not write watch history.
- Do not emit watch sync events.
- Do not delete existing server state automatically.

Collection state is not affected by privacy mode unless a separate setting is introduced later.

## Conflict Policy

Use deterministic last-write-wins with tombstones.

- Every event has a stable `version`.
- Later `version` wins.
- Equal timestamp ties are broken by `eventId`.
- Watch item metadata and each episode progress have separate versions.
- Collection state has one version per `bangumi_id`.
- Deletes and clear-all operations create tombstones.
- Older upserts cannot revive deleted or cleared data.

This matches the spirit of Kazumi's current watch-history sync while extending it to collections.

## Error Handling

Client behavior:

- Network failure: keep pending events and show a non-blocking sync failure toast only for manual sync.
- Authentication failure: mark sync disabled until token is fixed.
- Server validation failure for one event: server should reject the whole request with details; client keeps pending events.
- Snapshot application failure: keep pending events and log the error.

Server behavior:

- Invalid token: `401`.
- Disabled user or revoked token: `403`.
- Invalid device or event payload: `400`.
- Duplicate `event_id`: accept as idempotent and list under `ignoredDuplicateEventIds`.
- Transaction failure: `500`, no partial merge visible.

## Deployment and Admin Workflow

Add a small admin CLI script in LaevaBangumi:

```text
npm run sync:user:create -- --name Alice
npm run sync:token:create -- --user Alice --label "Alice phone"
npm run sync:token:revoke -- --token-id 1
```

The token creation command prints the raw token once. The user enters it into Aslan's sync settings.

For the initial private deployment, no web admin UI is required.

## Testing Strategy

### LaevaBangumi

Unit tests:

- Token hashing and bearer authentication.
- Device registration idempotency.
- Event validation.
- Watch merge:
  - upsert creates item and progress,
  - newer progress wins,
  - per-episode versions are independent,
  - delete tombstone blocks older upsert,
  - clear-all blocks older upsert.
- Collection merge:
  - upsert creates/updates type,
  - delete tombstone blocks older upsert,
  - clear-all blocks older upsert.
- Duplicate event upload is idempotent.

API tests:

- `/api/sync/status` rejects missing token.
- `/api/sync/register-device` creates device.
- `/api/sync/merge` accepts events and returns full snapshot.

### Aslan

Dart tests:

- JSON codecs for sync events and snapshots.
- Local event append/read/ack behavior.
- Watch progress event debounce decisions.
- Snapshot application to Hive-like repositories, or repository-level unit tests where Hive integration is practical.

Manual tests:

- Device A watches an episode; Device B syncs and resumes at the same episode/progress.
- Device A changes collection state; Device B syncs and sees the new state.
- Device A deletes history; Device B's older upsert does not restore it.
- Invalid token disables sync and preserves local data.

## Migration Plan

Phase 1: Backend foundation

- Add sync auth, users, tokens, devices.
- Add event tables and merge service.
- Add `/api/sync/status`, `/api/sync/register-device`, `/api/sync/merge`.
- Add admin scripts for user/token provisioning.

Phase 2: Aslan watch-history sync

- Add private sync settings.
- Add HTTP transport and local pending log.
- Convert current watch history to import events on first enablement.
- Apply watch snapshots to local Hive.

Phase 3: Aslan collection sync

- Add collection event generation.
- Convert current collectibles to import events on first enablement.
- Apply collection snapshots to local Hive.
- Keep Bangumi.tv collection sync separate and optional.

Phase 4: Polish and operations

- Add sync status UI and manual sync button.
- Add logs for accepted/duplicate/rejected events.
- Add conservative background sync triggers.
- Add database backup guidance.

## Open Decisions

The following decisions should be made during implementation planning, not after coding starts:

1. Whether tombstones live in the main state tables or dedicated deleted tables. Dedicated deleted tables are recommended.
2. Whether the first backend version stores full `bangumi_item_json` exactly as Aslan sends it or normalizes it into a narrower sync DTO. Exact JSON is recommended for compatibility.
3. Whether collection sync should interact with Bangumi.tv sync automatically. It should remain separate in the first version.
4. Whether to keep the hidden WebDAV UI behind a feature flag. Keeping it hidden is acceptable until private sync is proven stable.

## Agent Goal Prompt

Use this prompt with an agent `/goal` when ready to implement:

```text
Implement private cross-device sync for Aslan and LaevaBangumi based on /Users/laevatain/Documents/Code/Aslan/docs/superpowers/specs/2026-06-04-private-sync-design.md.

Scope:
- LaevaBangumi backend: add manually provisioned bearer-token users, devices, immutable sync events, server-side merge, and /api/sync/status, /api/sync/register-device, /api/sync/merge.
- Aslan client: add private sync settings, HTTP sync transport, local pending JSONL event log, watch-history sync, collection sync, snapshot application, and conservative sync triggers.
- Preserve offline-first behavior: local Hive updates must work without network.
- Keep users isolated by token; do not build public registration or OAuth.
- Use deterministic LWW versions with tombstones as described in the design.
- Keep existing public LaevaBangumi data-source APIs working unchanged.

Execution requirements:
- First inspect both repositories: /Users/laevatain/Documents/Code/LaevaBangumi and /Users/laevatain/Documents/Code/Aslan.
- Break the work into backend foundation, Aslan watch sync, Aslan collection sync, and polish/testing phases.
- Use TDD for merge logic and API contracts before implementation.
- Prefer small, focused repository/service files over expanding large route files.
- Run relevant Node tests in LaevaBangumi and Flutter/Dart tests in Aslan after each phase.
- Do not remove existing WebDAV code unless a later explicit task asks for cleanup.
```
