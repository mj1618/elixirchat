# Landing Page for Chat Application

## Problem

The current home page (`lib/elixirchat_web/controllers/page_html/home.html.heex`) displays the default Phoenix Framework welcome page with:
- Phoenix logo and branding
- Links to Phoenix documentation, GitHub, and changelog
- Links to Elixir Forum, Discord, Slack, and Fly.io deployment guides

This is inappropriate for a chat application MVP. Users visiting the site have no indication that this is meant to be a messenger-style chat app.

## Solution

Replace the default Phoenix welcome page with a proper landing page for Elixirchat that:

1. **Shows the app's purpose** - Communicate that this is a chat/messenger application
2. **Displays the app name** - "Elixirchat" branding instead of Phoenix Framework
3. **Provides clear CTAs** - Sign up and Login buttons (can link to `/` for now until auth is implemented)
4. **Describes key features** - Username-based accounts, direct messaging, group chats
5. **Has a clean, modern design** - Use the existing DaisyUI components

## Implementation Details

### Update `lib/elixirchat_web/controllers/page_html/home.html.heex`

Replace the entire content with a landing page that includes:

```heex
<div class="min-h-screen flex flex-col">
  <!-- Hero Section -->
  <div class="hero flex-1 bg-base-200">
    <div class="hero-content text-center">
      <div class="max-w-md">
        <h1 class="text-5xl font-bold">Elixirchat</h1>
        <p class="py-6">
          A simple, fast messenger. Create an account with just a username and password,
          then start chatting with friends through direct messages or group chats.
        </p>
        <div class="flex gap-4 justify-center">
          <.link href="/" class="btn btn-primary">Sign Up</.link>
          <.link href="/" class="btn btn-outline">Login</.link>
        </div>
      </div>
    </div>
  </div>

  <!-- Features Section -->
  <div class="py-16 px-4 bg-base-100">
    <div class="max-w-4xl mx-auto">
      <h2 class="text-3xl font-bold text-center mb-12">Simple by Design</h2>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
        <div class="card bg-base-200">
          <div class="card-body items-center text-center">
            <h3 class="card-title">No Email Required</h3>
            <p>Sign up with just a username and password. No email verification or phone number needed.</p>
          </div>
        </div>
        <div class="card bg-base-200">
          <div class="card-body items-center text-center">
            <h3 class="card-title">Direct Messages</h3>
            <p>Find friends by their username and start a private conversation instantly.</p>
          </div>
        </div>
        <div class="card bg-base-200">
          <div class="card-body items-center text-center">
            <h3 class="card-title">Group Chats</h3>
            <p>Create group conversations and add multiple friends to chat together.</p>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

### Update page title in `lib/elixirchat_web/components/layouts/root.html.heex`

Change the title suffix from "Phoenix Framework" to something more appropriate:

```heex
<.live_title default="Elixirchat" suffix=" · Chat">
  {assigns[:page_title]}
</.live_title>
```

## Acceptance Criteria

- [x] Home page displays Elixirchat branding and purpose
- [x] Features section describes the app's core functionality
- [x] Sign Up and Login buttons are visible (can be placeholder links for now)
- [x] Page uses existing DaisyUI styling for consistency
- [x] Phoenix Framework branding is removed from the landing page
- [x] Theme toggle still works

## Completion Notes (Agent aa77696e)

**Changes made:**
1. Updated `lib/elixirchat_web/controllers/page_html/home.html.heex`:
   - Replaced Phoenix Framework welcome page content with Elixirchat landing page
   - Added hero section with app name, description, and Sign Up/Login CTAs
   - Added features section with 3 cards: "No Email Required", "Direct Messages", "Group Chats"
   - Kept existing navbar which already had proper authentication-aware content
   - Added theme toggle to hero section

2. Updated `lib/elixirchat_web/components/layouts/root.html.heex`:
   - Changed page title suffix from " · Phoenix Framework" to " · Chat"

3. Fixed compilation error in `lib/elixirchat_web/plugs/auth.ex`:
   - Fixed ambiguous `assign/2` function call by using fully qualified `Phoenix.Component.assign`
   - Removed unused import of `Phoenix.Component`

**Tested with playwright-cli:**
- Verified page title is "Elixirchat · Chat"
- Verified h1 shows "Elixirchat"
- Verified Sign Up and Login buttons are present
- Verified "Simple by Design" features section is visible
- Verified feature cards are displayed
- Verified Phoenix Framework branding is completely removed
- Verified theme toggle has 3 buttons (system, light, dark)
