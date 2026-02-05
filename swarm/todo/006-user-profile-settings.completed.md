# Task: User Profile & Settings

## Description
Add a user settings/profile page where users can manage their account. This includes changing their password and deleting their account. This improves the user experience by giving users control over their account.

## Requirements
- Users can access a settings/profile page from the navigation
- Users can change their password (requires current password verification)
- Users can delete their account (with confirmation)
- Form validation and error handling for all operations
- Success/error flash messages for user feedback

## Implementation Steps

1. **Add account management functions to Accounts context** (`lib/elixirchat/accounts.ex`):
   - `change_user_password/3` - changes password after verifying current password
   - `delete_user/1` - deletes user and associated data
   - `validate_current_password/2` - verifies user's current password

2. **Create Settings LiveView** (`lib/elixirchat_web/live/settings_live.ex`):
   - Display current username (read-only)
   - Password change form with:
     - Current password field
     - New password field
     - Confirm new password field
   - Delete account button with confirmation modal

3. **Update navigation**:
   - Add "Settings" link to the navbar for authenticated users
   - Link from chat list page to settings

4. **Add route**:
   - Add `/settings` route in authenticated scope

5. **Handle account deletion**:
   - Delete user's conversation memberships
   - Optionally: keep messages but mark sender as "deleted user"
   - Clear session and redirect to home page

## Acceptance Criteria
- [x] Settings page is accessible at `/settings` for logged-in users
- [x] User can change password with current password verification
- [x] Password change shows appropriate success/error messages
- [x] User can delete their account after confirmation
- [x] Account deletion logs user out and redirects to home
- [x] Non-authenticated users cannot access settings page
- [x] Form validation prevents empty or mismatched passwords

## Completion Notes

**Agent: b723b367**
**Date: 2026-02-05**

### What was implemented:

1. **Accounts Context Updates** (`lib/elixirchat/accounts.ex`):
   - Added `change_user_password/2` - returns a changeset for password changes
   - Added `validate_current_password/2` - validates user's current password
   - Added `update_user_password/3` - updates password after verifying current password
   - Added `delete_user/1` - deletes the user account

2. **User Schema Updates** (`lib/elixirchat/accounts/user.ex`):
   - Added `current_password` virtual field
   - Added `password_changeset/2` for password changes

3. **Settings LiveView** (`lib/elixirchat_web/live/settings_live.ex`):
   - Profile section with read-only username display
   - Password change form with current password verification
   - Delete account confirmation modal (requires typing "delete my account")
   - Flash message support for success/error feedback

4. **Router Updates** (`lib/elixirchat_web/router.ex`):
   - Added `/settings` route in authenticated scope

5. **Navigation Updates** (`lib/elixirchat_web/live/chat_list_live.ex`):
   - Added Settings link with gear icon to the navbar

### Testing performed:
- Verified settings page loads for authenticated users
- Tested password change with correct current password (success)
- Verified flash messages display properly
- Tested delete account modal opens with confirmation dialog
- Verified login works with changed password

## Dependencies
- Task 001: User Authentication System (completed)

## Testing Notes
- Test password change with correct/incorrect current password
- Test password change with mismatched new passwords
- Test account deletion removes user from system
- Verify deleted user cannot log in
- Test navigation to settings page from various locations
- Verify redirect to login for non-authenticated access
