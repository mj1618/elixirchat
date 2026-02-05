import { emojiCategories, MAX_RECENT, RECENT_EMOJIS_KEY } from "../emoji-data";

const EmojiPicker = {
  mounted() {
    this.isOpen = false;
    this.activeCategory = "smileys"; // Default to smileys since recent may be empty
    this.searchQuery = "";
    this.recentEmojis = this.loadRecentEmojis();
    
    // Set up references
    this.toggleBtn = this.el.querySelector("[data-emoji-toggle]");
    this.picker = this.el.querySelector("[data-emoji-picker]");
    this.searchInput = this.el.querySelector("[data-emoji-search]");
    this.categoryTabs = this.el.querySelector("[data-category-tabs]");
    this.emojiGrid = this.el.querySelector("[data-emoji-grid]");
    
    // Set up click outside handler
    this.clickOutsideHandler = (e) => {
      if (this.isOpen && !this.el.contains(e.target)) {
        this.close();
      }
    };
    
    document.addEventListener("click", this.clickOutsideHandler);
    
    // Set up toggle handler
    if (this.toggleBtn) {
      this.toggleBtn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.toggle();
      });
    }
    
    // Set up search handler
    if (this.searchInput) {
      this.searchInput.addEventListener("input", (e) => {
        this.searchQuery = e.target.value;
        this.renderEmojiGrid();
      });
    }
    
    // Initial render of category tabs
    this.renderCategoryTabs();
  },
  
  destroyed() {
    document.removeEventListener("click", this.clickOutsideHandler);
  },
  
  loadRecentEmojis() {
    try {
      return JSON.parse(localStorage.getItem(RECENT_EMOJIS_KEY)) || [];
    } catch {
      return [];
    }
  },
  
  saveRecentEmoji(emoji) {
    const recent = this.loadRecentEmojis().filter(e => e !== emoji);
    recent.unshift(emoji);
    const updated = recent.slice(0, MAX_RECENT);
    localStorage.setItem(RECENT_EMOJIS_KEY, JSON.stringify(updated));
    this.recentEmojis = updated;
  },
  
  toggle() {
    this.isOpen ? this.close() : this.open();
  },
  
  open() {
    this.isOpen = true;
    if (this.picker) {
      this.picker.classList.remove("hidden");
    }
    // Set default category - recent if we have any, otherwise smileys
    this.activeCategory = this.recentEmojis.length > 0 ? "recent" : "smileys";
    this.searchQuery = "";
    if (this.searchInput) {
      this.searchInput.value = "";
    }
    this.renderCategoryTabs();
    this.renderEmojiGrid();
  },
  
  close() {
    this.isOpen = false;
    if (this.picker) {
      this.picker.classList.add("hidden");
    }
  },
  
  selectEmoji(emoji) {
    this.saveRecentEmoji(emoji);
    this.pushEvent("insert_emoji", { emoji });
    this.close();
  },
  
  selectCategory(categoryName) {
    this.activeCategory = categoryName;
    this.searchQuery = "";
    if (this.searchInput) {
      this.searchInput.value = "";
    }
    this.renderCategoryTabs();
    this.renderEmojiGrid();
  },
  
  renderCategoryTabs() {
    if (!this.categoryTabs) return;
    
    this.categoryTabs.innerHTML = "";
    
    emojiCategories.forEach(category => {
      // Skip recent if empty
      if (category.name === "recent" && this.recentEmojis.length === 0) {
        return;
      }
      
      const tab = document.createElement("button");
      tab.type = "button";
      tab.className = `emoji-category-tab ${this.activeCategory === category.name ? "active" : ""}`;
      tab.title = category.label;
      tab.textContent = category.icon;
      tab.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.selectCategory(category.name);
      });
      this.categoryTabs.appendChild(tab);
    });
  },
  
  renderEmojiGrid() {
    if (!this.emojiGrid) return;
    
    this.emojiGrid.innerHTML = "";
    
    let emojisToShow = [];
    
    if (this.searchQuery.trim()) {
      // Search mode - search across all categories
      const query = this.searchQuery.toLowerCase();
      emojiCategories.forEach(category => {
        if (category.name === "recent") return;
        category.emojis.forEach(({ emoji, name }) => {
          if (name.toLowerCase().includes(query)) {
            emojisToShow.push({ emoji, name });
          }
        });
      });
    } else {
      // Category mode
      if (this.activeCategory === "recent") {
        emojisToShow = this.recentEmojis.map(emoji => ({ emoji, name: "recent" }));
      } else {
        const category = emojiCategories.find(c => c.name === this.activeCategory);
        if (category) {
          emojisToShow = category.emojis;
        }
      }
    }
    
    if (emojisToShow.length === 0) {
      const noResults = document.createElement("div");
      noResults.className = "text-center text-base-content/50 py-8";
      noResults.textContent = this.searchQuery ? "No emojis found" : "No recent emojis";
      this.emojiGrid.appendChild(noResults);
      return;
    }
    
    const grid = document.createElement("div");
    grid.className = "emoji-grid";
    
    emojisToShow.forEach(({ emoji, name }) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "emoji-btn";
      btn.title = name;
      btn.textContent = emoji;
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.selectEmoji(emoji);
      });
      grid.appendChild(btn);
    });
    
    this.emojiGrid.appendChild(grid);
  }
};

export default EmojiPicker;
