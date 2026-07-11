# Escalation Policy

Replaces self-assessed "is my model good enough?" introspection with **objective
triggers**. Agents judge their own capability poorly, so this policy keys off
observable conditions instead. If any trigger fires, stop and act as directed —
regardless of how confident you feel.

## Hard triggers — pause and write a pause report

Stop, record a pause in the session log (`status.md` → `PAUSED`, with reasons),
and hand back to the user or a stronger model if any of these hold:

- The change would touch **more than 3 modules** at once.
- The task involves **auth, secrets, access control, migrations, or data
  deletion/rewrite** and the approach is not already settled in a design log.
- **Concurrency, async ordering, or shared mutable state** is central to the fix.
- You have **failed the same fix twice** (two `validate` failures on the same
  approach) — do not try a third variation blindly; reassess or escalate.
- Requirements remain **ambiguous after one clarifying pass**.
- `./tasks.sh validate` **cannot be run or completed** and you cannot make it runnable.
- The blast radius is high and you **cannot state the rollback** in one sentence.

## Soft triggers — escalate the tier, do not necessarily stop

Bump the task to **high-risk** (design log required) if:

- The design has multiple viable approaches with real tradeoffs.
- The work spans subsystems or long instruction chains.
- Performance work forces a correctness/speed/cost tradeoff.

## Pause report (what to leave behind)

When a hard trigger fires, the session log must contain:

- which trigger(s) fired;
- the current understanding and options considered;
- the safest known-good state and how to return to it;
- a concrete recommended next step for a human or stronger model.

A good pause report is a successful outcome, not a failure.
