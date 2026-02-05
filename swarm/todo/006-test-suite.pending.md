# Task: Comprehensive Test Suite

## Description
Add comprehensive test coverage for the existing authentication and chat functionality. The current test folder only contains boilerplate Phoenix tests - we need proper unit and integration tests to ensure the application works correctly and to prevent regressions.

## Requirements
- Unit tests for Accounts context (user creation, authentication)
- Unit tests for Chat context (conversations, messages, membership)
- Integration tests for LiveView pages (signup, login, chat)
- Test real-time messaging with PubSub
- Test authorization (users can't access others' chats)

## Implementation Steps

1. **Create test fixtures/factories** (`test/support/fixtures.ex`):
   - `user_fixture/1` - creates a test user
   - `conversation_fixture/2` - creates a test conversation
   - `message_fixture/3` - creates a test message

2. **Create Accounts context tests** (`test/elixirchat/accounts_test.exs`):
   - Test `create_user/1` with valid/invalid params
   - Test username uniqueness validation
   - Test password hashing
   - Test `authenticate_user/2` with valid/invalid credentials
   - Test `get_user_by_username/1`
   - Test `get_user/1`

3. **Create Chat context tests** (`test/elixirchat/chat_test.exs`):
   - Test `create_direct_conversation/2`
   - Test `get_or_create_direct_conversation/2` returns existing
   - Test `list_user_conversations/1`
   - Test `send_message/3`
   - Test `list_messages/2`
   - Test `mark_conversation_read/2`
   - Test `member?/2`
   - Test `search_users/2`
   - Test PubSub broadcasting

4. **Create LiveView tests**:
   - `test/elixirchat_web/live/signup_live_test.exs`
     - Test signup form renders
     - Test successful signup creates user
     - Test duplicate username shows error
   - `test/elixirchat_web/live/login_live_test.exs`
     - Test login form renders
     - Test successful login creates session
     - Test invalid credentials show error
   - `test/elixirchat_web/live/chat_list_live_test.exs`
     - Test redirects unauthenticated users
     - Test shows user's conversations
     - Test new chat button works
   - `test/elixirchat_web/live/chat_live_test.exs`
     - Test redirects unauthenticated users
     - Test denies access to non-member
     - Test shows messages
     - Test sending messages works

5. **Update test_helper.exs if needed**:
   - Add any necessary test configuration
   - Ensure Ecto sandbox is properly configured

## Acceptance Criteria
- [ ] All Accounts context functions have test coverage
- [ ] All Chat context functions have test coverage  
- [ ] LiveView pages have integration tests
- [ ] Tests pass with `mix test`
- [ ] No flaky tests (reliable PubSub testing)

## Dependencies
- Task 001: User Authentication System (completed)
- Task 002: Direct Chat System (in progress - but we can test what's completed)

## Testing Notes
- Run `mix test` to execute all tests
- Use `mix test --cover` to check coverage
- Tests should be isolated (each test starts with clean database)
- Use `Ecto.Adapters.SQL.Sandbox` for database isolation

## Notes
This task can be worked on in parallel with other feature work since it tests existing completed functionality. The tests may need minor updates as features are finalized, but having the test infrastructure in place is valuable.
