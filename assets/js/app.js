// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/elixirchat"
import topbar from "../vendor/topbar"
import EmojiPicker from "./hooks/emoji_picker"

// Custom hooks for chat functionality
const Hooks = {
  EmojiPicker,
  
  BrowserNotification: {
    mounted() {
      // Request notification permission on mount
      if ("Notification" in window && Notification.permission === "default") {
        Notification.requestPermission();
      }

      // Handle notification events from server
      this.handleEvent("notify", ({ sender, message, conversation_id, conversation_name }) => {
        // Don't notify if tab is focused
        if (document.hasFocus()) return;

        // Don't notify if permission not granted
        if (!("Notification" in window) || Notification.permission !== "granted") return;

        const title = conversation_name || sender;
        const body = `${sender}: ${this.truncate(message, 100)}`;

        const notification = new Notification(title, {
          body: body,
          icon: "/images/logo.svg",
          tag: `conversation-${conversation_id}`,
          renotify: true
        });

        notification.onclick = () => {
          window.focus();
          notification.close();
        };

        // Auto-close after 5 seconds
        setTimeout(() => notification.close(), 5000);
      });
    },

    truncate(str, length) {
      if (!str) return "";
      if (str.length <= length) return str;
      return str.substring(0, length) + "...";
    }
  },

  MentionInput: {
    mounted() {
      this.input = this.el.querySelector('input[name="message"]');
      this.fileInput = this.el.querySelector('input[type="file"]');
      if (!this.input) return;
      
      this.mentionStart = null;
      this.debounceTimer = null;
      
      this.input.addEventListener('input', (e) => {
        this.handleInput();
      });
      
      this.input.addEventListener('keydown', (e) => {
        // Handle escape to close mention dropdown
        if (e.key === 'Escape') {
          this.mentionStart = null;
          this.pushEvent("close_mentions", {});
        }
      });
      
      // Listen for mention insertion from server
      this.handleEvent("insert_mention", ({username}) => {
        if (this.mentionStart !== null && this.input) {
          const value = this.input.value;
          const before = value.substring(0, this.mentionStart);
          const after = value.substring(this.input.selectionStart);
          this.input.value = `${before}@${username} ${after}`;
          this.input.focus();
          const newPos = this.mentionStart + username.length + 2; // +2 for @ and space
          this.input.setSelectionRange(newPos, newPos);
          this.mentionStart = null;
          
          // Trigger input event so LiveView updates
          this.input.dispatchEvent(new Event('input', { bubbles: true }));
        }
      });

      // Drag and drop support
      this.setupDragAndDrop();
      
      // Paste support for images
      this.setupPasteHandler();
    },
    
    setupDragAndDrop() {
      const form = this.el.querySelector('form');
      if (!form) return;

      // Prevent default drag behaviors
      ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
        form.addEventListener(eventName, (e) => {
          e.preventDefault();
          e.stopPropagation();
        });
      });

      // Highlight drop area on drag over
      ['dragenter', 'dragover'].forEach(eventName => {
        form.addEventListener(eventName, () => {
          form.classList.add('ring-2', 'ring-primary', 'ring-opacity-50');
        });
      });

      ['dragleave', 'drop'].forEach(eventName => {
        form.addEventListener(eventName, () => {
          form.classList.remove('ring-2', 'ring-primary', 'ring-opacity-50');
        });
      });

      // Handle dropped files
      form.addEventListener('drop', (e) => {
        const files = e.dataTransfer.files;
        if (files.length > 0 && this.fileInput) {
          // Create a new DataTransfer to set files on the input
          const dt = new DataTransfer();
          for (let i = 0; i < files.length; i++) {
            dt.items.add(files[i]);
          }
          this.fileInput.files = dt.files;
          // Trigger change event for LiveView to pick up
          this.fileInput.dispatchEvent(new Event('change', { bubbles: true }));
        }
      });
    },

    setupPasteHandler() {
      this.input.addEventListener('paste', (e) => {
        const items = e.clipboardData?.items;
        if (!items) return;

        for (let i = 0; i < items.length; i++) {
          const item = items[i];
          if (item.type.startsWith('image/')) {
            e.preventDefault();
            const file = item.getAsFile();
            if (file && this.fileInput) {
              const dt = new DataTransfer();
              dt.items.add(file);
              this.fileInput.files = dt.files;
              this.fileInput.dispatchEvent(new Event('change', { bubbles: true }));
            }
            break;
          }
        }
      });
    },
    
    handleInput() {
      const value = this.input.value;
      const cursorPos = this.input.selectionStart;
      
      // Find @ before cursor
      const textBeforeCursor = value.substring(0, cursorPos);
      const lastAtIndex = textBeforeCursor.lastIndexOf('@');
      
      if (lastAtIndex !== -1) {
        const textAfterAt = textBeforeCursor.substring(lastAtIndex + 1);
        // Check if we're in a mention (no spaces after @)
        if (!/\s/.test(textAfterAt)) {
          this.mentionStart = lastAtIndex;
          
          // Debounce the search
          clearTimeout(this.debounceTimer);
          this.debounceTimer = setTimeout(() => {
            this.pushEvent("mention_search", { query: textAfterAt });
          }, 150);
          return;
        }
      }
      
      this.mentionStart = null;
      this.pushEvent("close_mentions", {});
    },
    
    destroyed() {
      if (this.debounceTimer) {
        clearTimeout(this.debounceTimer);
      }
    }
  },

  ScrollToBottom: {
    mounted() {
      this.scrollBtn = document.getElementById('scroll-to-bottom-btn');
      this.isNearBottom = true;
      
      // Initial scroll to bottom
      this.scrollToBottom();
      
      // Track scroll position
      this.el.addEventListener('scroll', () => this.handleScroll());
      
      // Listen for manual scroll to bottom button click
      this.el.addEventListener('scroll-to-bottom', () => {
        this.scrollToBottom();
      });
      
      // Listen for scroll_to_message events
      this.handleEvent("scroll_to_message", ({message_id}) => {
        const element = document.getElementById(`message-${message_id}`);
        if (element) {
          element.scrollIntoView({ behavior: "smooth", block: "center" });
          element.classList.add("highlight-message");
          setTimeout(() => element.classList.remove("highlight-message"), 2000);
        }
      });

      // Set up read receipt tracking
      this.setupReadReceiptTracking();
    },
    updated() {
      // Only auto-scroll if user was already near bottom
      if (this.isNearBottom) {
        this.scrollToBottom();
      }
      // Re-observe new messages after update
      this.observeNewMessages();
      // Update button visibility after DOM update
      this.handleScroll();
    },
    handleScroll() {
      const threshold = 100; // pixels from bottom
      const scrollTop = this.el.scrollTop;
      const scrollHeight = this.el.scrollHeight;
      const clientHeight = this.el.clientHeight;
      
      this.isNearBottom = scrollTop + clientHeight >= scrollHeight - threshold;
      
      // Show/hide scroll to bottom button
      if (this.scrollBtn) {
        if (this.isNearBottom) {
          this.scrollBtn.classList.add('hidden');
        } else {
          this.scrollBtn.classList.remove('hidden');
        }
      }
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight;
      this.isNearBottom = true;
      if (this.scrollBtn) {
        this.scrollBtn.classList.add('hidden');
      }
    },
    setupReadReceiptTracking() {
      // Track which messages have been read
      this.readMessages = new Set();
      this.pendingReads = new Set();
      this.sendTimeout = null;

      // Create intersection observer for detecting visible messages
      this.observer = new IntersectionObserver(
        (entries) => {
          entries.forEach(entry => {
            if (entry.isIntersecting) {
              const messageId = entry.target.dataset.messageId;
              if (messageId && !this.readMessages.has(messageId)) {
                this.pendingReads.add(messageId);
                this.scheduleSendReads();
              }
            }
          });
        },
        { threshold: 0.5, root: this.el }
      );

      // Observe all existing message elements
      this.observeAllMessages();
    },
    observeAllMessages() {
      const messages = this.el.querySelectorAll('[data-message-id]');
      messages.forEach(el => {
        if (!el._observed) {
          this.observer.observe(el);
          el._observed = true;
        }
      });
    },
    observeNewMessages() {
      // Find and observe any new message elements
      const messages = this.el.querySelectorAll('[data-message-id]');
      messages.forEach(el => {
        if (!el._observed) {
          this.observer.observe(el);
          el._observed = true;
        }
      });
    },
    scheduleSendReads() {
      if (this.sendTimeout) return;
      this.sendTimeout = setTimeout(() => {
        const ids = Array.from(this.pendingReads);
        if (ids.length > 0) {
          this.pushEvent("messages_viewed", { message_ids: ids });
          ids.forEach(id => this.readMessages.add(id));
          this.pendingReads.clear();
        }
        this.sendTimeout = null;
      }, 500);
    },
    destroyed() {
      if (this.observer) {
        this.observer.disconnect();
      }
      if (this.sendTimeout) {
        clearTimeout(this.sendTimeout);
      }
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

