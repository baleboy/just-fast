# Testing phone⇄watch sync

Sync is a headline promise of the app and the hardest thing in it to trust,
because a failure and a slow success look identical from the outside. This is
the procedure for telling them apart. **It needs real hardware** — a simulator
can't sign in to iCloud, so none of it is reachable from `simctl`.

## What you're reading

Both apps carry a DEBUG-only **Sync diagnostics** screen:

- iPhone: Settings → General → **Sync diagnostics** (or launch with
  `-syncDiagnostics`, which opens it straight away).
- Watch: Settings → **Sync diagnostics**.

Six facts, in the same order on both, so the two can be read side by side:

| Row | What it tells you |
| --- | --- |
| Mirroring requested | Whether the store opened with CloudKit at all. "No" means a local-only fallback and nothing below matters. |
| Status | `CloudSyncStatus` — the same verdict the shipping warning row uses. |
| Open fast | The id prefix and start of the fast **this device** thinks is running. |
| Waiting since | When the current *wait window* opened, and whether it came from a **launch** or a **resume**. |
| To first import | Seconds from that window opening until this device heard from another one. The number this whole exercise is about. |
| Last import / export | Absolute times, so the phone's export and the watch's import can be lined up. |
| Last local write | When this device last wrote a fast. The anchor the two above are measured from. |

Events lists the last 50, newest first, including ones still in flight — an
import that started forty seconds ago and hasn't finished is the most
diagnostic state there is, and it only shows up because in-flight events are
recorded. **Watch relay** marks a hand-off over WatchConnectivity, `sent` on the watch and
`received` on the phone — the only way to see, from the device, whether the
phone was actually woken when the watch started a fast. **App active** marks every resume, so the question the background
case turns on — *does an import follow a resume, or only a cold launch?* — is
answered by reading down the list.

Live, on either device:

```bash
log stream --predicate 'subsystem == "com.baleware.fastino"' --style compact
```

For the watch, run it from Console.app with the watch selected in the sidebar.

## Row 1 — the resumed watch app

**This is the reported failure and the measurement that decides everything.** A
cold launch is the easy case: mirroring sets itself up and imports as part of
opening the store. A *resume* gets no setup, so unless a silent push arrived
while the app was suspended, there may be nothing to make it pull at all.

1. On both devices, open Sync diagnostics and tap **Clear log**.
2. Open Fastino on the **watch**, then let the screen go dark and put the wrist
   down. Leave the app in the background — do not force-quit it.
3. Wait a couple of minutes. On the **phone**, in the foreground app, start a
   fast. Note the time.
4. Raise the **watch**. Fastino comes back to the app you left. **Leave it open,
   untouched, for 60 seconds.**
5. Record: did the fast appear, and how long did it take? Then open Sync
   diagnostics on the watch and read the event list from the bottom up.

| Outcome | What it means | What to do |
| --- | --- | --- |
| Appears within a few seconds | Sync works on resume too. | Nothing. |
| **App active** is the newest event and no import follows it | The resume triggered no pull — the failure this test exists to find. Check the phone's **Last export** to confirm the data left the phone. | This is what justifies the WatchConnectivity fast path (below). |
| An import follows **App active** but takes 10–40s | Sync works; the app was lying during the gap. **This is what was measured (~30s), and `SyncTiming.resumeImportTimeout` is set to 45s because of it.** The wait also continues past that deadline while an import is still running, so a slower one is covered too. |
| The phone never exported | The problem is on the writing side, not the reading one. | Row 4, and the Control Center gap in row 7. |
| Watch shows a *different* open fast | Not a delivery problem — a merge one. | `OpenFastMerge` / `SyncReconciler`. |

### Row 1b — the same thing cold

Force-quit the watch app first (crown, swipe), then repeat. If the cold case
works and the resumed one doesn't, the diagnosis is settled: mirroring only
pulls at setup, and nothing else on the watch will make it pull.

## Result on file

Run 2026-09-07, Debug builds, fast started in the foreground phone app, watch
app resumed from background: **the fast arrived, and took about 30 seconds.**
So the resume does import — the watch was simply asserting "Ready" throughout
the wait. The constants above come from this run; re-measure if the number
looks different on other hardware, and treat a single sample as a single
sample.

## If a later run says the resume never imports

`NSPersistentCloudKitContainer` exposes no public "fetch now", so there is
nothing to call on foreground that would fix it. The fix is then the
**WatchConnectivity fast path**, deferred until this measurement exists:

- The phone sends the open fast on every `FastStore` write via
  `updateApplicationContext`, which is delivered to the watch even when the
  watch app isn't running and is waiting at `receivedApplicationContext` the
  moment it resumes.
- `WCSession` is already activated on the watch for `CompanionProbe`; the phone
  has no session yet.
- The cost to weigh first: a WC-applied write and the CloudKit import of the
  same fast are two different rows, so `Fast.id` has to become the identity the
  reconciler dedupes on. CloudKit dedupes by its own record id, not ours.
- CloudKit stays the path for the devices being apart, which WC can't serve.

## The rest of the matrix

Run each the same way — clear both logs, act, then read both screens. Record
the seconds and the outcome.

| # | Setup | Action | Expect |
| --- | --- | --- | --- |
| 2 | Both apps open, devices together | Start a fast on the **watch** | Phone reflects it |
| 3 | Phone app open, watch app force-quit | Start on phone, then open the watch | The cold-launch case — appears within the checking window |
| 4 | Phone backgrounded immediately after starting | Start on phone, background it within a second, open the watch | The known weak point: the export may not have finished before suspension |
| 5 | Devices apart (watch on Wi-Fi, phone elsewhere) | Start on phone | Slower, but should arrive — this is the case CloudKit is here for |
| 6 | Watch in Airplane Mode | Start on phone, then re-enable | Arrives on reconnect |
| 7 | Start from **Control Center** on the phone, don't open the app | Open the watch | **Known not to sync** — that write happens in the widget extension with mirroring off (`SetFastingIntent`), and only reaches CloudKit when the phone app next runs |
| 8 | End a fast on the phone | Watch open | Complication stops counting too (`RemoteChangeRefresher`) |
| 9 | Standalone watch (phone app deleted) | Start and end on the watch | Works throughout; notifications come from the watch (`NotificationOwnership`) |
| 10 | Phone backgrounded, start reminder due in a few minutes | Start on the **watch**, leave the phone alone | No reminder fires. The phone's diagnostics show a **Watch relay · received** with no import before it — that's the relay doing its job, not CloudKit |

Row 10 is the one the relay exists for, and it's the one that used to fail (the
reminder is armed on the phone; only the phone can cancel it). It's worth
running against a real reminder time rather than a contrived one: set the
anchor to a couple of minutes out in Settings, background the phone, start on
the watch, and wait past it. A **Watch relay** row on both devices — `sent` on
the watch, `received` on the phone — is the proof the phone was woken; its
absence on the phone means it wasn't, and the reminder will fire.

## Recording results

Keep the numbers somewhere durable — the point of the exercise is a
distribution, not one anecdote. Two runs of row 1 that disagree are themselves
the finding.
