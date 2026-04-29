I'll create a complete step-by-step learning guide for you. Since this is a long technical walkthrough you'll want to keep open while working, I'll save it as a markdown file you can follow along with.Here is your complete step-by-step Patroni learning guide. It's organized in **9 phases** so you can stop and understand each one before moving to the next:

| Phase | What you learn |
|---|---|
| 1 | Podman network + volumes (the foundation) |
| 2 | etcd — the "brain" that decides who is primary |
| 3 | Building your own Patroni + PostgreSQL 16 image (`Containerfile`) |
| 4 | Three Patroni nodes with separate config files |
| 5 | HAProxy on ports 5000 (writes), 5001 (reads), 7000 (stats UI) |
| 6 | Connecting and verifying replication |
| 7 | A real **stocks + options + OHLC + orders + trades** schema |
| 8 | Killing the primary and watching automatic failover happen |
| 9 | Day-to-day `patronictl` operations + cleanup + troubleshooting |

A few important things to know before you start:

- **Single etcd vs production 3-node etcd** — the guide uses 1 etcd node to keep the learning curve smaller, and the last section tells you what to upgrade later.
- **Every command is explained** — flags, env variables, and the "why" behind each step are written right next to the command.
- **Failover is the highlight** — Phase 8 is where Patroni earns its name. After you stop `pg-node1`, run `patronictl list` on `pg-node2` and you'll see a replica get promoted to Leader within ~30 seconds, and HAProxy follows automatically.
- **Your stock schema in Phase 7** includes `instruments`, `ohlc_minute`, `strategies`, `orders`, `trades`, and `positions` tables — designed for option selling/buying workflows with proper indexes, lot sizes, and underlying symbol tracking (NIFTY CE/PE examples included).

Start with Phase 1 and run the commands one at a time. After each phase, run the verification command shown — don't move forward until that step passes. If anything fails, the troubleshooting table at the bottom covers the most common issues.

Once you finish Phase 8 successfully, ping me and we can go deeper into any piece — synchronous replication, TimescaleDB for tick data, PgBouncer pooling, or backup with pgBackRest.
