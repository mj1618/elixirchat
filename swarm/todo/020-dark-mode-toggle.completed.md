# Task: Dark Mode Toggle

## Description
Add a user-preference dark mode toggle to the application. Users should be able to switch between light and dark themes, with their preference persisted across sessions. The app should also respect the user's system preference as the default.

## Requirements
- Add a theme toggle button to the navigation/header area
- Support at least two themes: light and dark (using DaisyUI themes)
- Persist theme preference in localStorage
- Respect system preference (prefers-color-scheme) as initial default
- Theme changes should be instant (no page reload)
- Theme toggle should be accessible from all pages (login, chat list, chat view)
- Smooth transition when switching themes

## Implementation Steps

1. **Create Theme Hook** (`assets/js/hooks/theme_toggle.js`):
   - Initialize theme from localStorage or system preference
   - Handle theme toggle events
   - Update `data-theme` attribute on HTML element
   - Persist preference to localStorage

2. **Update app.js** to include the theme toggle hook

3. **Add theme toggle UI to layouts** (`lib/elixirchat_web/components/layouts.ex`):
   - Add toggle button in the app layout header
   - Use sun/moon icons for light/dark
   - Make it visually appealing and accessible

4. **Update root layout** (`lib/elixirchat_web/components/layouts/root.html.heex`):
   - Set initial data-theme from system preference
   - Add script to prevent flash of wrong theme on page load

5. **Ensure all pages look good in both themes**:
   - Test login page
   - Test chat list
   - Test chat view
   - Verify all components render correctly in both themes

## Technical Details

### Theme Toggle Hook
```javascript
// assets/js/hooks/theme_toggle.js
const THEME_KEY = "elixirchat_theme";

const ThemeToggle = {
  mounted() {
    // Initialize theme
    this.theme = this.getInitialTheme();
    this.applyTheme(this.theme);
    
    // Handle toggle click
    this.el.addEventListener("click", () => {
      this.toggleTheme();
    });
    
    // Update icon
    this.updateIcon();
  },
  
  getInitialTheme() {
    // Check localStorage first
    const stored = localStorage.getItem(THEME_KEY);
    if (stored) return stored;
    
    // Fall back to system preference
    if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
      return "dark";
    }
    return "light";
  },
  
  applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem(THEME_KEY, theme);
    this.theme = theme;
  },
  
  toggleTheme() {
    const newTheme = this.theme === "light" ? "dark" : "light";
    this.applyTheme(newTheme);
    this.updateIcon();
  },
  
  updateIcon() {
    const sunIcon = this.el.querySelector('[data-theme-icon="light"]');
    const moonIcon = this.el.querySelector('[data-theme-icon="dark"]');
    
    if (sunIcon && moonIcon) {
      if (this.theme === "dark") {
        sunIcon.classList.remove("hidden");
        moonIcon.classList.add("hidden");
      } else {
        sunIcon.classList.add("hidden");
        moonIcon.classList.remove("hidden");
      }
    }
  }
};

export default ThemeToggle;
```

### Initial Theme Script (prevent flash)
```html
<!-- In root.html.heex, before </head> -->
<script>
  (function() {
    const stored = localStorage.getItem("elixirchat_theme");
    const theme = stored || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    document.documentElement.setAttribute("data-theme", theme);
  })();
</script>
```

### Toggle Button Component
```heex
<button
  id="theme-toggle"
  phx-hook="ThemeToggle"
  class="btn btn-ghost btn-circle"
  title="Toggle theme"
  aria-label="Toggle dark mode"
>
  <!-- Sun icon (shown when dark mode is active, click to switch to light) -->
  <svg data-theme-icon="light" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 hidden">
    <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" />
  </svg>
  <!-- Moon icon (shown when light mode is active, click to switch to dark) -->
  <svg data-theme-icon="dark" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
    <path stroke-linecap="round" stroke-linejoin="round" d="M21.752 15.002A9.72 9.72 0 0 1 18 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 0 0 3 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 0 0 9.002-5.998Z" />
  </svg>
</button>
```

## DaisyUI Theme Configuration

The app should use DaisyUI's built-in light and dark themes. The tailwind.config.js should include:

```javascript
daisyui: {
  themes: ["light", "dark"],
}
```

## Acceptance Criteria
- [ ] Theme toggle button visible in header/navbar area
- [ ] Clicking toggle switches between light and dark themes
- [ ] Theme persists across page reloads
- [ ] Theme persists across browser sessions (localStorage)
- [ ] System preference is respected on first visit
- [ ] No flash of wrong theme on page load
- [ ] All pages render correctly in both themes
- [ ] Icon changes appropriately (sun for dark mode, moon for light mode)
- [ ] Smooth visual transition when switching themes
- [ ] Toggle is accessible (aria labels, keyboard accessible)

## Dependencies
None - this is a standalone UI feature

## Testing Notes
- Toggle theme and verify immediate visual change
- Refresh page and verify theme persists
- Clear localStorage and verify system preference is used
- Test with system set to dark mode
- Test with system set to light mode
- Test on login page (before auth)
- Test on chat list page
- Test on individual chat page
- Verify all components (buttons, cards, modals) look correct in both themes
- Test on mobile viewport

## Edge Cases to Handle
- localStorage unavailable (use system preference, don't crash)
- System preference changes while app is open (optional: listen for changes)
- First-time user with no preference (use system preference)
- Icons loading before hook runs (use CSS to hide appropriately)

## Future Enhancements (not in this task)
- More theme options (multiple color schemes)
- User preference stored in database (synced across devices)
- Scheduled theme switching (dark at night)
- Per-conversation theme settings

## Completion Notes (Agent d12ce640)

### What was done
The dark mode toggle feature was already mostly implemented in the codebase:
- `root.html.heex` already had the JavaScript to handle theme switching via `phx:set-theme` events
- `layouts.ex` already had a `theme_toggle/1` component with a 3-way toggle (system/light/dark)
- CSS already had light and dark DaisyUI theme configurations

**What I added:**
1. Added the theme toggle to the **login page** (`login_live.ex`) - positioned in top-right corner
2. Added the theme toggle to the **signup page** (`signup_live.ex`) - positioned in top-right corner
3. Added the theme toggle to the **chat list navbar** (`chat_list_live.ex`) - in the navbar
4. Added the theme toggle to the **chat page navbar** (`chat_live.ex`) - in the navbar

### Testing performed
- Verified theme toggle appears on login page ✓
- Verified theme toggle appears on signup page ✓
- Tested dark mode toggle - verified colors change to dark theme ✓
- Tested light mode toggle - verified colors change to light theme ✓
- Tested system mode - respects system preference ✓
- Theme persists across page navigation via localStorage ✓

### Implementation approach
Used the existing `ElixirchatWeb.Layouts.theme_toggle/0` component which provides:
- 3-way toggle: system, light, dark
- Uses hero icons (computer-desktop, sun, moon)
- Persists preference in localStorage with key "phx:theme"
- Respects system preference via prefers-color-scheme
- Instant theme changes without page reload
