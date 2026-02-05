# Human Tasks for Fly.io Deployment

## Swarm Task Cleanup Needed

The file `swarm/todo/010-message-deletion.pending.md` appears to be a duplicate/subset of `010-message-edit-delete.aa77696e.processing.md` which already covers message deletion. Consider removing or marking it as completed/cancelled to avoid conflicts.

---

## Deployment Status: COMPLETE

The app is deployed at: **https://elixirchat.fly.dev/**

### Remaining Task: Set OPENAI_API_KEY - DONE

To enable the AI agent feature, set your OpenAI API key:

```bash
fly secrets set OPENAI_API_KEY=sk-your-key-here --app elixirchat
```

---

## Useful Commands

```bash
# View logs
fly logs

# SSH into the running machine
fly ssh console

# Run IEx console on the running app
fly ssh console --command "/app/bin/elixirchat remote"

# Check app status
fly status

# View secrets (names only)
fly secrets list

# Scale the app
fly scale count 2  # Run 2 instances
fly scale memory 512  # Change memory

# Connect to Postgres directly
fly postgres connect -a elixirchat-db

# Run migrations manually
fly ssh console --command "/app/bin/migrate"
```

## Troubleshooting

### Database Connection Issues

If the app can't connect to the database, verify the attachment:

```bash
fly secrets list
# Should show DATABASE_URL
```

If DATABASE_URL is missing, re-attach:

```bash
fly postgres attach elixirchat-db --app elixirchat
```

### Migration Failures

Check logs for migration errors:

```bash
fly logs
```

You can also run migrations manually:

```bash
fly ssh console --command "/app/bin/migrate"
```

### App Won't Start

Check the logs:

```bash
fly logs
```

Common issues:
- Missing SECRET_KEY_BASE: `fly secrets set SECRET_KEY_BASE=...`
- Missing DATABASE_URL: Re-attach postgres
- Port mismatch: Ensure PORT=4000 in fly.toml matches internal_port
