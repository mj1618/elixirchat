# Task: Add Test Coverage for Accounts Module

## Description
The user authentication system (Task 001) was implemented without automated tests. Add comprehensive test coverage for the Accounts context and User schema to ensure authentication works correctly and catch regressions.

## Requirements
- Unit tests for Accounts context functions
- Schema validation tests for User
- Password hashing verification
- Timing attack protection verification
- Integration tests for authentication flow

## Implementation Steps

1. **Create Accounts context tests** (`test/elixirchat/accounts_test.exs`):
   - Test `create_user/1` with valid attributes
   - Test `create_user/1` with missing username
   - Test `create_user/1` with missing password
   - Test `create_user/1` with duplicate username
   - Test `get_user_by_username/1` returns user when found
   - Test `get_user_by_username/1` returns nil when not found
   - Test `get_user!/1` returns user when found
   - Test `get_user!/1` raises when not found
   - Test `get_user/1` returns user or nil
   - Test `authenticate_user/2` with valid credentials
   - Test `authenticate_user/2` with invalid password
   - Test `authenticate_user/2` with non-existent user
   - Test `change_user_registration/2` returns changeset

2. **Create User schema tests** (`test/elixirchat/accounts/user_test.exs`):
   - Test registration_changeset validates required fields
   - Test registration_changeset enforces minimum password length
   - Test registration_changeset enforces minimum username length
   - Test password is hashed on create (not stored plain)
   - Test username uniqueness constraint

3. **Create test fixtures/helpers** (`test/support/fixtures/accounts_fixtures.ex`):
   - `user_fixture/1` - creates a user with optional overrides
   - Standardize test user creation

4. **Update test support files**:
   - Ensure data_case.ex properly sets up sandbox

## Acceptance Criteria
- [x] All Accounts context functions have corresponding tests
- [x] User schema validations are tested
- [x] Password hashing is verified (check for $2b$ prefix)
- [x] Tests run successfully with `mix test`
- [x] No flaky tests (all deterministic)
- [x] Tests are isolated (use database sandbox)

## Completion Notes (Agent ceefbe20)

Completed on Feb 5, 2026.

### Files Created:
- `test/support/fixtures/accounts_fixtures.ex` - Test fixtures with `user_fixture/1` and `valid_user_attributes/1`
- `test/elixirchat/accounts_test.exs` - 21 tests covering all Accounts context functions
- `test/elixirchat/accounts/user_test.exs` - 15 tests covering User schema validations

### Test Coverage:
- **create_user/1**: Valid attributes, missing username, missing password, duplicate username, username length validation (min/max), invalid username characters, password length validation (min/max)
- **get_user_by_username/1**: Returns user when found, returns nil when not found, case sensitivity
- **get_user!/1**: Returns user when found, raises when not found
- **get_user/1**: Returns user when found, returns nil when not found
- **authenticate_user/2**: Valid credentials, invalid password, non-existent user, timing attack protection
- **change_user_registration/2**: Returns changeset, validates attributes
- **User schema**: Required fields, length validations, format validations, password hashing, uniqueness constraint, virtual field behavior

### Additional Fixes:
- Fixed outdated page_controller_test.exs that was checking for old Phoenix welcome page text
- Fixed compile error in settings_live.ex (changed `.flash_group` to `Layouts.flash_group`)

### Total: 36 tests, 0 failures

## Dependencies
- Task 001: User Authentication System (completed)

## Testing Notes
- Run tests with `mix test test/elixirchat/accounts_test.exs`
- Ensure tests are not order-dependent
- Use `async: true` where possible for parallel execution
- Verify tests work with fresh database: `mix ecto.reset && mix test`

## Example Test Structure

```elixir
defmodule Elixirchat.AccountsTest do
  use Elixirchat.DataCase

  alias Elixirchat.Accounts
  alias Elixirchat.Accounts.User

  describe "create_user/1" do
    test "creates user with valid attributes" do
      attrs = %{username: "testuser", password: "password123"}
      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.username == "testuser"
      assert String.starts_with?(user.password_hash, "$2b$")
    end

    test "returns error with duplicate username" do
      attrs = %{username: "testuser", password: "password123"}
      {:ok, _user} = Accounts.create_user(attrs)
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "has already been taken" in errors_on(changeset).username
    end
  end
end
```
