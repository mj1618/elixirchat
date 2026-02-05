# Task: User Authentication System

## Description
Implement user signup and login functionality using username and password (no email/phone as per README requirements).

## Requirements
- Users can sign up with a unique username and password
- Users can log in with their username and password
- Passwords must be securely hashed (use bcrypt via `bcrypt_elixir` or `argon2_elixir`)
- Session-based authentication
- Logged-in users see their username displayed
- Users can log out

## Implementation Steps

1. **Add dependencies** to `mix.exs`:
   - `bcrypt_elixir` for password hashing
   
2. **Create User schema and migration**:
   - Create `Elixirchat.Accounts.User` schema
   - Fields: `id`, `username` (unique, required), `password_hash`, `inserted_at`, `updated_at`
   - Add unique index on username

3. **Create Accounts context** (`lib/elixirchat/accounts.ex`):
   - `create_user/1` - creates a new user
   - `get_user_by_username/1` - fetches user by username
   - `authenticate_user/2` - verifies username/password
   - `get_user!/1` - fetches user by id

4. **Create authentication plug** (`lib/elixirchat_web/plugs/auth.ex`):
   - Store user_id in session on login
   - Load current_user from session into assigns
   - Helper functions for login/logout

5. **Create LiveView pages**:
   - Registration page at `/signup`
   - Login page at `/login`
   - Update home page to show logged-in state

6. **Update router**:
   - Add routes for signup, login, logout
   - Create authenticated/guest route pipelines

## Acceptance Criteria
- [x] Can visit `/signup` and create account with username/password
- [x] Duplicate usernames are rejected with helpful error
- [x] Can visit `/login` and sign in with valid credentials
- [x] Invalid login shows error message (redirects back to login)
- [x] Home page shows username when logged in
- [x] Can log out and session is cleared
- [x] Passwords are hashed in database (not stored plain)

## Completion Notes (Agent d12ce640)

### Files Created:
- `lib/elixirchat/accounts.ex` - Accounts context with user CRUD and authentication
- `lib/elixirchat/accounts/user.ex` - User schema with bcrypt password hashing
- `lib/elixirchat_web/plugs/auth.ex` - Auth plug for session management
- `lib/elixirchat_web/live/signup_live.ex` - LiveView for user registration
- `lib/elixirchat_web/live/login_live.ex` - LiveView for login page
- `lib/elixirchat_web/controllers/session_controller.ex` - Controller for login/logout actions
- `priv/repo/migrations/20260205040408_create_users.exs` - Users table migration

### Files Modified:
- `mix.exs` - Added bcrypt_elixir dependency
- `lib/elixirchat_web/router.ex` - Added auth routes and pipelines
- `lib/elixirchat_web/controllers/page_controller.ex` - Pass current_user to home template
- `lib/elixirchat_web/controllers/page_html/home.html.heex` - Added navbar with login/logout state

### Testing Verified:
- Signup creates user with bcrypt-hashed password ($2b$12$...)
- Duplicate username shows validation error "has already been taken"
- Login with valid credentials redirects to home with username displayed
- Login with invalid credentials redirects back to login with flash error
- Logout clears session and shows login/signup buttons

## Dependencies
None - this is the first task.

## Testing Notes
- Test signup flow in browser with playwright-cli
- Test login flow with valid and invalid credentials
- Verify database has hashed password, not plain text
