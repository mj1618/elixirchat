# Elixirchat

A real-time chat application built with Phoenix LiveView. Features username/password authentication, direct messages, group chats, and an AI agent powered by OpenAI.

# Testing

Make sure to test your work using the playwright-cli, see AGENTS.md

## Tech Stack

- Elixir / Phoenix 1.8 / LiveView
- PostgreSQL
- TailwindCSS + DaisyUI
- Deployed on Fly.io

## Local Development

```bash
# Install dependencies and setup database
mix setup

# Start the server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000)

## Deployment

The app is deployed on Fly.io at **https://elixirchat.fly.dev/**

### Deploy Changes

```bash
fly deploy
```

This builds the Docker image, runs migrations automatically, and performs a rolling deploy.

### Useful Commands

```bash
# View logs
fly logs

# Check status
fly status

# SSH into the app
fly ssh console

# Run IEx console
fly ssh console --command "/app/bin/elixirchat remote"

# Connect to Postgres
fly postgres connect -a elixirchat-db
```

### Environment Variables

Set secrets with `fly secrets set KEY=value`:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | Auto-configured by Fly Postgres |
| `SECRET_KEY_BASE` | Phoenix secret key |
| `OPENAI_API_KEY` | For AI agent feature |
| `PHX_HOST` | Custom domain (optional) |

## Features

- Username/password authentication (no email required)
- Direct messages between users
- Group chats with multiple participants
- AI agent - mention `@agent` in a chat to ask questions
