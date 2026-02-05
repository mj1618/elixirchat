# Task: Emoji Picker

## Description
Add a visual emoji picker component to the message composition area. Currently users can only add emojis by typing them manually or using the limited reaction emojis. An emoji picker allows users to easily browse and insert emojis into their messages, enhancing the chat experience. The picker should support commonly used emoji categories and recent emojis.

## Requirements
- Add emoji picker button next to message input (smiley face icon)
- Clicking button opens emoji picker popover
- Emoji picker displays emojis organized by categories:
  - Recent (recently used emojis)
  - Smileys & People
  - Animals & Nature
  - Food & Drink
  - Activities
  - Travel & Places
  - Objects
  - Symbols
- Clicking an emoji inserts it at cursor position in message input
- Picker closes after selecting an emoji (or clicking outside)
- Store recently used emojis in localStorage
- Search/filter emojis by name
- Keyboard navigation support (arrow keys, enter to select)
- Works on both desktop and mobile

## Implementation Steps

1. **Create emoji data module** (`assets/js/emoji-data.js`):
   - Define emoji categories with emoji unicode characters
   - Include common emoji names for search
   - Export as JavaScript module

2. **Create emoji picker hook** (`assets/js/hooks/emoji_picker.js`):
   - Handle click outside to close
   - Manage recently used emojis in localStorage
   - Handle category navigation
   - Handle search filtering
   - Insert emoji at cursor position in input

3. **Update app.js** to include the emoji picker hook

4. **Add emoji picker UI to ChatLive** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add emoji button next to send button
   - Add emoji picker popover component
   - Handle emoji picker toggle state
   - Position picker above input area

5. **Add CSS styles** (`assets/css/app.css`):
   - Style emoji picker container
   - Style category tabs
   - Style emoji grid
   - Style search input
   - Responsive design for mobile

## Technical Details

### Emoji Data Structure
```javascript
// assets/js/emoji-data.js
export const emojiCategories = [
  {
    name: "recent",
    label: "Recent",
    icon: "🕐",
    emojis: [] // Populated from localStorage
  },
  {
    name: "smileys",
    label: "Smileys & People",
    icon: "😀",
    emojis: [
      { emoji: "😀", name: "grinning face" },
      { emoji: "😃", name: "grinning face with big eyes" },
      { emoji: "😄", name: "grinning face with smiling eyes" },
      { emoji: "😁", name: "beaming face with smiling eyes" },
      { emoji: "😆", name: "grinning squinting face" },
      { emoji: "😅", name: "grinning face with sweat" },
      { emoji: "🤣", name: "rolling on the floor laughing" },
      { emoji: "😂", name: "face with tears of joy" },
      { emoji: "🙂", name: "slightly smiling face" },
      { emoji: "😊", name: "smiling face with smiling eyes" },
      { emoji: "😇", name: "smiling face with halo" },
      { emoji: "🥰", name: "smiling face with hearts" },
      { emoji: "😍", name: "smiling face with heart-eyes" },
      { emoji: "🤩", name: "star-struck" },
      { emoji: "😘", name: "face blowing a kiss" },
      { emoji: "😗", name: "kissing face" },
      { emoji: "😚", name: "kissing face with closed eyes" },
      { emoji: "😙", name: "kissing face with smiling eyes" },
      { emoji: "🥲", name: "smiling face with tear" },
      { emoji: "😋", name: "face savoring food" },
      { emoji: "😛", name: "face with tongue" },
      { emoji: "😜", name: "winking face with tongue" },
      { emoji: "🤪", name: "zany face" },
      { emoji: "😝", name: "squinting face with tongue" },
      { emoji: "🤑", name: "money-mouth face" },
      { emoji: "🤗", name: "hugging face" },
      { emoji: "🤭", name: "face with hand over mouth" },
      { emoji: "🤫", name: "shushing face" },
      { emoji: "🤔", name: "thinking face" },
      { emoji: "🤐", name: "zipper-mouth face" },
      { emoji: "🤨", name: "face with raised eyebrow" },
      { emoji: "😐", name: "neutral face" },
      { emoji: "😑", name: "expressionless face" },
      { emoji: "😶", name: "face without mouth" },
      { emoji: "😏", name: "smirking face" },
      { emoji: "😒", name: "unamused face" },
      { emoji: "🙄", name: "face with rolling eyes" },
      { emoji: "😬", name: "grimacing face" },
      { emoji: "🤥", name: "lying face" },
      { emoji: "😌", name: "relieved face" },
      { emoji: "😔", name: "pensive face" },
      { emoji: "😪", name: "sleepy face" },
      { emoji: "🤤", name: "drooling face" },
      { emoji: "😴", name: "sleeping face" },
      { emoji: "😷", name: "face with medical mask" },
      { emoji: "🤒", name: "face with thermometer" },
      { emoji: "🤕", name: "face with head-bandage" },
      { emoji: "🤢", name: "nauseated face" },
      { emoji: "🤮", name: "face vomiting" },
      { emoji: "🤧", name: "sneezing face" },
      { emoji: "🥵", name: "hot face" },
      { emoji: "🥶", name: "cold face" },
      { emoji: "🥴", name: "woozy face" },
      { emoji: "😵", name: "dizzy face" },
      { emoji: "🤯", name: "exploding head" },
      { emoji: "🤠", name: "cowboy hat face" },
      { emoji: "🥳", name: "partying face" },
      { emoji: "🥸", name: "disguised face" },
      { emoji: "😎", name: "smiling face with sunglasses" },
      { emoji: "🤓", name: "nerd face" },
      { emoji: "🧐", name: "face with monocle" },
      { emoji: "😕", name: "confused face" },
      { emoji: "😟", name: "worried face" },
      { emoji: "🙁", name: "slightly frowning face" },
      { emoji: "☹️", name: "frowning face" },
      { emoji: "😮", name: "face with open mouth" },
      { emoji: "😯", name: "hushed face" },
      { emoji: "😲", name: "astonished face" },
      { emoji: "😳", name: "flushed face" },
      { emoji: "🥺", name: "pleading face" },
      { emoji: "😦", name: "frowning face with open mouth" },
      { emoji: "😧", name: "anguished face" },
      { emoji: "😨", name: "fearful face" },
      { emoji: "😰", name: "anxious face with sweat" },
      { emoji: "😥", name: "sad but relieved face" },
      { emoji: "😢", name: "crying face" },
      { emoji: "😭", name: "loudly crying face" },
      { emoji: "😱", name: "face screaming in fear" },
      { emoji: "😖", name: "confounded face" },
      { emoji: "😣", name: "persevering face" },
      { emoji: "😞", name: "disappointed face" },
      { emoji: "😓", name: "downcast face with sweat" },
      { emoji: "😩", name: "weary face" },
      { emoji: "😫", name: "tired face" },
      { emoji: "🥱", name: "yawning face" },
      { emoji: "😤", name: "face with steam from nose" },
      { emoji: "😡", name: "pouting face" },
      { emoji: "😠", name: "angry face" },
      { emoji: "🤬", name: "face with symbols on mouth" },
      { emoji: "😈", name: "smiling face with horns" },
      { emoji: "👿", name: "angry face with horns" },
      { emoji: "💀", name: "skull" },
      { emoji: "☠️", name: "skull and crossbones" },
      { emoji: "💩", name: "pile of poo" },
      { emoji: "🤡", name: "clown face" },
      { emoji: "👹", name: "ogre" },
      { emoji: "👺", name: "goblin" },
      { emoji: "👻", name: "ghost" },
      { emoji: "👽", name: "alien" },
      { emoji: "👾", name: "alien monster" },
      { emoji: "🤖", name: "robot" },
      // Hand gestures
      { emoji: "👋", name: "waving hand" },
      { emoji: "🤚", name: "raised back of hand" },
      { emoji: "🖐️", name: "hand with fingers splayed" },
      { emoji: "✋", name: "raised hand" },
      { emoji: "🖖", name: "vulcan salute" },
      { emoji: "👌", name: "OK hand" },
      { emoji: "🤌", name: "pinched fingers" },
      { emoji: "🤏", name: "pinching hand" },
      { emoji: "✌️", name: "victory hand" },
      { emoji: "🤞", name: "crossed fingers" },
      { emoji: "🤟", name: "love-you gesture" },
      { emoji: "🤘", name: "sign of the horns" },
      { emoji: "🤙", name: "call me hand" },
      { emoji: "👈", name: "backhand index pointing left" },
      { emoji: "👉", name: "backhand index pointing right" },
      { emoji: "👆", name: "backhand index pointing up" },
      { emoji: "🖕", name: "middle finger" },
      { emoji: "👇", name: "backhand index pointing down" },
      { emoji: "☝️", name: "index pointing up" },
      { emoji: "👍", name: "thumbs up" },
      { emoji: "👎", name: "thumbs down" },
      { emoji: "✊", name: "raised fist" },
      { emoji: "👊", name: "oncoming fist" },
      { emoji: "🤛", name: "left-facing fist" },
      { emoji: "🤜", name: "right-facing fist" },
      { emoji: "👏", name: "clapping hands" },
      { emoji: "🙌", name: "raising hands" },
      { emoji: "👐", name: "open hands" },
      { emoji: "🤲", name: "palms up together" },
      { emoji: "🤝", name: "handshake" },
      { emoji: "🙏", name: "folded hands" },
      { emoji: "✍️", name: "writing hand" },
      { emoji: "💪", name: "flexed biceps" },
    ]
  },
  {
    name: "animals",
    label: "Animals & Nature",
    icon: "🐻",
    emojis: [
      { emoji: "🐶", name: "dog face" },
      { emoji: "🐱", name: "cat face" },
      { emoji: "🐭", name: "mouse face" },
      { emoji: "🐹", name: "hamster" },
      { emoji: "🐰", name: "rabbit face" },
      { emoji: "🦊", name: "fox" },
      { emoji: "🐻", name: "bear" },
      { emoji: "🐼", name: "panda" },
      { emoji: "🐨", name: "koala" },
      { emoji: "🐯", name: "tiger face" },
      { emoji: "🦁", name: "lion" },
      { emoji: "🐮", name: "cow face" },
      { emoji: "🐷", name: "pig face" },
      { emoji: "🐸", name: "frog" },
      { emoji: "🐵", name: "monkey face" },
      { emoji: "🙈", name: "see-no-evil monkey" },
      { emoji: "🙉", name: "hear-no-evil monkey" },
      { emoji: "🙊", name: "speak-no-evil monkey" },
      { emoji: "🐔", name: "chicken" },
      { emoji: "🐧", name: "penguin" },
      { emoji: "🐦", name: "bird" },
      { emoji: "🐤", name: "baby chick" },
      { emoji: "🦆", name: "duck" },
      { emoji: "🦅", name: "eagle" },
      { emoji: "🦉", name: "owl" },
      { emoji: "🦇", name: "bat" },
      { emoji: "🐺", name: "wolf" },
      { emoji: "🐗", name: "boar" },
      { emoji: "🐴", name: "horse face" },
      { emoji: "🦄", name: "unicorn" },
      { emoji: "🐝", name: "honeybee" },
      { emoji: "🐛", name: "bug" },
      { emoji: "🦋", name: "butterfly" },
      { emoji: "🐌", name: "snail" },
      { emoji: "🐞", name: "lady beetle" },
      { emoji: "🐜", name: "ant" },
      { emoji: "🦟", name: "mosquito" },
      { emoji: "🦀", name: "crab" },
      { emoji: "🐙", name: "octopus" },
      { emoji: "🦑", name: "squid" },
      { emoji: "🐠", name: "tropical fish" },
      { emoji: "🐟", name: "fish" },
      { emoji: "🐬", name: "dolphin" },
      { emoji: "🐳", name: "spouting whale" },
      { emoji: "🐋", name: "whale" },
      { emoji: "🦈", name: "shark" },
      { emoji: "🐊", name: "crocodile" },
      { emoji: "🐅", name: "tiger" },
      { emoji: "🐆", name: "leopard" },
      { emoji: "🦓", name: "zebra" },
      { emoji: "🦍", name: "gorilla" },
      { emoji: "🦧", name: "orangutan" },
      { emoji: "🐘", name: "elephant" },
      { emoji: "🦛", name: "hippopotamus" },
      { emoji: "🦏", name: "rhinoceros" },
      { emoji: "🐪", name: "camel" },
      { emoji: "🦒", name: "giraffe" },
      { emoji: "🦘", name: "kangaroo" },
      { emoji: "🐃", name: "water buffalo" },
      { emoji: "🐂", name: "ox" },
      { emoji: "🐄", name: "cow" },
      { emoji: "🐎", name: "horse" },
      { emoji: "🐖", name: "pig" },
      { emoji: "🐏", name: "ram" },
      { emoji: "🐑", name: "ewe" },
      { emoji: "🦙", name: "llama" },
      { emoji: "🐕", name: "dog" },
      { emoji: "🐩", name: "poodle" },
      { emoji: "🦮", name: "guide dog" },
      { emoji: "🐈", name: "cat" },
      { emoji: "🐓", name: "rooster" },
      { emoji: "🦃", name: "turkey" },
      { emoji: "🦚", name: "peacock" },
      { emoji: "🦜", name: "parrot" },
      { emoji: "🦢", name: "swan" },
      { emoji: "🦩", name: "flamingo" },
      { emoji: "🐇", name: "rabbit" },
      { emoji: "🐁", name: "mouse" },
      { emoji: "🐀", name: "rat" },
      // Nature
      { emoji: "🌸", name: "cherry blossom" },
      { emoji: "💮", name: "white flower" },
      { emoji: "🏵️", name: "rosette" },
      { emoji: "🌹", name: "rose" },
      { emoji: "🥀", name: "wilted flower" },
      { emoji: "🌺", name: "hibiscus" },
      { emoji: "🌻", name: "sunflower" },
      { emoji: "🌼", name: "blossom" },
      { emoji: "🌷", name: "tulip" },
      { emoji: "🌱", name: "seedling" },
      { emoji: "🌲", name: "evergreen tree" },
      { emoji: "🌳", name: "deciduous tree" },
      { emoji: "🌴", name: "palm tree" },
      { emoji: "🌵", name: "cactus" },
      { emoji: "🌾", name: "sheaf of rice" },
      { emoji: "🌿", name: "herb" },
      { emoji: "☘️", name: "shamrock" },
      { emoji: "🍀", name: "four leaf clover" },
      { emoji: "🍁", name: "maple leaf" },
      { emoji: "🍂", name: "fallen leaf" },
      { emoji: "🍃", name: "leaf fluttering in wind" },
    ]
  },
  {
    name: "food",
    label: "Food & Drink",
    icon: "🍕",
    emojis: [
      { emoji: "🍇", name: "grapes" },
      { emoji: "🍈", name: "melon" },
      { emoji: "🍉", name: "watermelon" },
      { emoji: "🍊", name: "tangerine" },
      { emoji: "🍋", name: "lemon" },
      { emoji: "🍌", name: "banana" },
      { emoji: "🍍", name: "pineapple" },
      { emoji: "🥭", name: "mango" },
      { emoji: "🍎", name: "red apple" },
      { emoji: "🍏", name: "green apple" },
      { emoji: "🍐", name: "pear" },
      { emoji: "🍑", name: "peach" },
      { emoji: "🍒", name: "cherries" },
      { emoji: "🍓", name: "strawberry" },
      { emoji: "🫐", name: "blueberries" },
      { emoji: "🥝", name: "kiwi fruit" },
      { emoji: "🍅", name: "tomato" },
      { emoji: "🫒", name: "olive" },
      { emoji: "🥥", name: "coconut" },
      { emoji: "🥑", name: "avocado" },
      { emoji: "🍆", name: "eggplant" },
      { emoji: "🥔", name: "potato" },
      { emoji: "🥕", name: "carrot" },
      { emoji: "🌽", name: "ear of corn" },
      { emoji: "🌶️", name: "hot pepper" },
      { emoji: "🫑", name: "bell pepper" },
      { emoji: "🥒", name: "cucumber" },
      { emoji: "🥬", name: "leafy green" },
      { emoji: "🥦", name: "broccoli" },
      { emoji: "🧄", name: "garlic" },
      { emoji: "🧅", name: "onion" },
      { emoji: "🍄", name: "mushroom" },
      { emoji: "🥜", name: "peanuts" },
      { emoji: "🌰", name: "chestnut" },
      { emoji: "🍞", name: "bread" },
      { emoji: "🥐", name: "croissant" },
      { emoji: "🥖", name: "baguette bread" },
      { emoji: "🫓", name: "flatbread" },
      { emoji: "🥨", name: "pretzel" },
      { emoji: "🥯", name: "bagel" },
      { emoji: "🥞", name: "pancakes" },
      { emoji: "🧇", name: "waffle" },
      { emoji: "🧀", name: "cheese wedge" },
      { emoji: "🍖", name: "meat on bone" },
      { emoji: "🍗", name: "poultry leg" },
      { emoji: "🥩", name: "cut of meat" },
      { emoji: "🥓", name: "bacon" },
      { emoji: "🍔", name: "hamburger" },
      { emoji: "🍟", name: "french fries" },
      { emoji: "🍕", name: "pizza" },
      { emoji: "🌭", name: "hot dog" },
      { emoji: "🥪", name: "sandwich" },
      { emoji: "🌮", name: "taco" },
      { emoji: "🌯", name: "burrito" },
      { emoji: "🫔", name: "tamale" },
      { emoji: "🥙", name: "stuffed flatbread" },
      { emoji: "🧆", name: "falafel" },
      { emoji: "🥚", name: "egg" },
      { emoji: "🍳", name: "cooking" },
      { emoji: "🥘", name: "shallow pan of food" },
      { emoji: "🍲", name: "pot of food" },
      { emoji: "🫕", name: "fondue" },
      { emoji: "🥣", name: "bowl with spoon" },
      { emoji: "🥗", name: "green salad" },
      { emoji: "🍿", name: "popcorn" },
      { emoji: "🧈", name: "butter" },
      { emoji: "🧂", name: "salt" },
      { emoji: "🥫", name: "canned food" },
      { emoji: "🍱", name: "bento box" },
      { emoji: "🍘", name: "rice cracker" },
      { emoji: "🍙", name: "rice ball" },
      { emoji: "🍚", name: "cooked rice" },
      { emoji: "🍛", name: "curry rice" },
      { emoji: "🍜", name: "steaming bowl" },
      { emoji: "🍝", name: "spaghetti" },
      { emoji: "🍠", name: "roasted sweet potato" },
      { emoji: "🍢", name: "oden" },
      { emoji: "🍣", name: "sushi" },
      { emoji: "🍤", name: "fried shrimp" },
      { emoji: "🍥", name: "fish cake with swirl" },
      { emoji: "🥮", name: "moon cake" },
      { emoji: "🍡", name: "dango" },
      { emoji: "🥟", name: "dumpling" },
      { emoji: "🥠", name: "fortune cookie" },
      { emoji: "🥡", name: "takeout box" },
      { emoji: "🦪", name: "oyster" },
      { emoji: "🍦", name: "soft ice cream" },
      { emoji: "🍧", name: "shaved ice" },
      { emoji: "🍨", name: "ice cream" },
      { emoji: "🍩", name: "doughnut" },
      { emoji: "🍪", name: "cookie" },
      { emoji: "🎂", name: "birthday cake" },
      { emoji: "🍰", name: "shortcake" },
      { emoji: "🧁", name: "cupcake" },
      { emoji: "🥧", name: "pie" },
      { emoji: "🍫", name: "chocolate bar" },
      { emoji: "🍬", name: "candy" },
      { emoji: "🍭", name: "lollipop" },
      { emoji: "🍮", name: "custard" },
      { emoji: "🍯", name: "honey pot" },
      // Drinks
      { emoji: "🍼", name: "baby bottle" },
      { emoji: "🥛", name: "glass of milk" },
      { emoji: "☕", name: "hot beverage" },
      { emoji: "🫖", name: "teapot" },
      { emoji: "🍵", name: "teacup without handle" },
      { emoji: "🍶", name: "sake" },
      { emoji: "🍾", name: "bottle with popping cork" },
      { emoji: "🍷", name: "wine glass" },
      { emoji: "🍸", name: "cocktail glass" },
      { emoji: "🍹", name: "tropical drink" },
      { emoji: "🍺", name: "beer mug" },
      { emoji: "🍻", name: "clinking beer mugs" },
      { emoji: "🥂", name: "clinking glasses" },
      { emoji: "🥃", name: "tumbler glass" },
      { emoji: "🥤", name: "cup with straw" },
      { emoji: "🧋", name: "bubble tea" },
      { emoji: "🧃", name: "beverage box" },
      { emoji: "🧉", name: "mate" },
      { emoji: "🧊", name: "ice" },
    ]
  },
  {
    name: "activities",
    label: "Activities",
    icon: "⚽",
    emojis: [
      { emoji: "⚽", name: "soccer ball" },
      { emoji: "🏀", name: "basketball" },
      { emoji: "🏈", name: "american football" },
      { emoji: "⚾", name: "baseball" },
      { emoji: "🥎", name: "softball" },
      { emoji: "🎾", name: "tennis" },
      { emoji: "🏐", name: "volleyball" },
      { emoji: "🏉", name: "rugby football" },
      { emoji: "🥏", name: "flying disc" },
      { emoji: "🎱", name: "pool 8 ball" },
      { emoji: "🪀", name: "yo-yo" },
      { emoji: "🏓", name: "ping pong" },
      { emoji: "🏸", name: "badminton" },
      { emoji: "🏒", name: "ice hockey" },
      { emoji: "🏑", name: "field hockey" },
      { emoji: "🥍", name: "lacrosse" },
      { emoji: "🏏", name: "cricket game" },
      { emoji: "🪃", name: "boomerang" },
      { emoji: "🥅", name: "goal net" },
      { emoji: "⛳", name: "flag in hole" },
      { emoji: "🪁", name: "kite" },
      { emoji: "🏹", name: "bow and arrow" },
      { emoji: "🎣", name: "fishing pole" },
      { emoji: "🤿", name: "diving mask" },
      { emoji: "🥊", name: "boxing glove" },
      { emoji: "🥋", name: "martial arts uniform" },
      { emoji: "🎽", name: "running shirt" },
      { emoji: "🛹", name: "skateboard" },
      { emoji: "🛼", name: "roller skate" },
      { emoji: "🛷", name: "sled" },
      { emoji: "⛸️", name: "ice skate" },
      { emoji: "🥌", name: "curling stone" },
      { emoji: "🎿", name: "skis" },
      { emoji: "⛷️", name: "skier" },
      { emoji: "🏂", name: "snowboarder" },
      { emoji: "🪂", name: "parachute" },
      { emoji: "🏋️", name: "person lifting weights" },
      { emoji: "🤼", name: "wrestlers" },
      { emoji: "🤸", name: "person cartwheeling" },
      { emoji: "🤺", name: "person fencing" },
      { emoji: "⛹️", name: "person bouncing ball" },
      { emoji: "🤾", name: "person playing handball" },
      { emoji: "🏌️", name: "person golfing" },
      { emoji: "🏇", name: "horse racing" },
      { emoji: "🧘", name: "person in lotus position" },
      { emoji: "🏄", name: "person surfing" },
      { emoji: "🏊", name: "person swimming" },
      { emoji: "🤽", name: "person playing water polo" },
      { emoji: "🚣", name: "person rowing boat" },
      { emoji: "🧗", name: "person climbing" },
      { emoji: "🚵", name: "person mountain biking" },
      { emoji: "🚴", name: "person biking" },
      { emoji: "🎪", name: "circus tent" },
      { emoji: "🎭", name: "performing arts" },
      { emoji: "🎨", name: "artist palette" },
      { emoji: "🎬", name: "clapper board" },
      { emoji: "🎤", name: "microphone" },
      { emoji: "🎧", name: "headphone" },
      { emoji: "🎼", name: "musical score" },
      { emoji: "🎹", name: "musical keyboard" },
      { emoji: "🥁", name: "drum" },
      { emoji: "🪘", name: "long drum" },
      { emoji: "🎷", name: "saxophone" },
      { emoji: "🎺", name: "trumpet" },
      { emoji: "🎸", name: "guitar" },
      { emoji: "🪕", name: "banjo" },
      { emoji: "🎻", name: "violin" },
      { emoji: "🎲", name: "game die" },
      { emoji: "♟️", name: "chess pawn" },
      { emoji: "🎯", name: "direct hit" },
      { emoji: "🎳", name: "bowling" },
      { emoji: "🎮", name: "video game" },
      { emoji: "🎰", name: "slot machine" },
      { emoji: "🧩", name: "puzzle piece" },
    ]
  },
  {
    name: "travel",
    label: "Travel & Places",
    icon: "✈️",
    emojis: [
      { emoji: "🚗", name: "automobile" },
      { emoji: "🚕", name: "taxi" },
      { emoji: "🚙", name: "sport utility vehicle" },
      { emoji: "🚌", name: "bus" },
      { emoji: "🚎", name: "trolleybus" },
      { emoji: "🏎️", name: "racing car" },
      { emoji: "🚓", name: "police car" },
      { emoji: "🚑", name: "ambulance" },
      { emoji: "🚒", name: "fire engine" },
      { emoji: "🚐", name: "minibus" },
      { emoji: "🛻", name: "pickup truck" },
      { emoji: "🚚", name: "delivery truck" },
      { emoji: "🚛", name: "articulated lorry" },
      { emoji: "🚜", name: "tractor" },
      { emoji: "🏍️", name: "motorcycle" },
      { emoji: "🛵", name: "motor scooter" },
      { emoji: "🚲", name: "bicycle" },
      { emoji: "🛴", name: "kick scooter" },
      { emoji: "🚏", name: "bus stop" },
      { emoji: "🛣️", name: "motorway" },
      { emoji: "🛤️", name: "railway track" },
      { emoji: "🚃", name: "railway car" },
      { emoji: "🚄", name: "high-speed train" },
      { emoji: "🚅", name: "bullet train" },
      { emoji: "🚆", name: "train" },
      { emoji: "🚇", name: "metro" },
      { emoji: "🚈", name: "light rail" },
      { emoji: "🚉", name: "station" },
      { emoji: "✈️", name: "airplane" },
      { emoji: "🛫", name: "airplane departure" },
      { emoji: "🛬", name: "airplane arrival" },
      { emoji: "🛩️", name: "small airplane" },
      { emoji: "💺", name: "seat" },
      { emoji: "🚁", name: "helicopter" },
      { emoji: "🚀", name: "rocket" },
      { emoji: "🛸", name: "flying saucer" },
      { emoji: "🛶", name: "canoe" },
      { emoji: "⛵", name: "sailboat" },
      { emoji: "🚤", name: "speedboat" },
      { emoji: "🛥️", name: "motor boat" },
      { emoji: "🛳️", name: "passenger ship" },
      { emoji: "⛴️", name: "ferry" },
      { emoji: "🚢", name: "ship" },
      { emoji: "⚓", name: "anchor" },
      { emoji: "⛽", name: "fuel pump" },
      { emoji: "🚧", name: "construction" },
      { emoji: "🚦", name: "vertical traffic light" },
      { emoji: "🚥", name: "horizontal traffic light" },
      { emoji: "🏁", name: "chequered flag" },
      { emoji: "🚩", name: "triangular flag" },
      { emoji: "🏠", name: "house" },
      { emoji: "🏡", name: "house with garden" },
      { emoji: "🏢", name: "office building" },
      { emoji: "🏣", name: "Japanese post office" },
      { emoji: "🏤", name: "post office" },
      { emoji: "🏥", name: "hospital" },
      { emoji: "🏦", name: "bank" },
      { emoji: "🏨", name: "hotel" },
      { emoji: "🏩", name: "love hotel" },
      { emoji: "🏪", name: "convenience store" },
      { emoji: "🏫", name: "school" },
      { emoji: "🏬", name: "department store" },
      { emoji: "🏭", name: "factory" },
      { emoji: "🏯", name: "Japanese castle" },
      { emoji: "🏰", name: "castle" },
      { emoji: "💒", name: "wedding" },
      { emoji: "🗼", name: "Tokyo tower" },
      { emoji: "🗽", name: "Statue of Liberty" },
      { emoji: "⛪", name: "church" },
      { emoji: "🕌", name: "mosque" },
      { emoji: "🛕", name: "hindu temple" },
      { emoji: "🕍", name: "synagogue" },
      { emoji: "⛩️", name: "shinto shrine" },
      { emoji: "🕋", name: "kaaba" },
      { emoji: "⛲", name: "fountain" },
      { emoji: "⛺", name: "tent" },
      { emoji: "🌁", name: "foggy" },
      { emoji: "🌃", name: "night with stars" },
      { emoji: "🏙️", name: "cityscape" },
      { emoji: "🌄", name: "sunrise over mountains" },
      { emoji: "🌅", name: "sunrise" },
      { emoji: "🌆", name: "cityscape at dusk" },
      { emoji: "🌇", name: "sunset" },
      { emoji: "🌉", name: "bridge at night" },
      { emoji: "🌌", name: "milky way" },
      { emoji: "🌠", name: "shooting star" },
      { emoji: "🎇", name: "sparkler" },
      { emoji: "🎆", name: "fireworks" },
      { emoji: "🌈", name: "rainbow" },
      { emoji: "🏖️", name: "beach with umbrella" },
      { emoji: "🏝️", name: "desert island" },
      { emoji: "🏜️", name: "desert" },
      { emoji: "🌋", name: "volcano" },
      { emoji: "🏔️", name: "snow-capped mountain" },
      { emoji: "⛰️", name: "mountain" },
      { emoji: "🗻", name: "mount fuji" },
      { emoji: "🏕️", name: "camping" },
    ]
  },
  {
    name: "objects",
    label: "Objects",
    icon: "💡",
    emojis: [
      { emoji: "⌚", name: "watch" },
      { emoji: "📱", name: "mobile phone" },
      { emoji: "📲", name: "mobile phone with arrow" },
      { emoji: "💻", name: "laptop" },
      { emoji: "⌨️", name: "keyboard" },
      { emoji: "🖥️", name: "desktop computer" },
      { emoji: "🖨️", name: "printer" },
      { emoji: "🖱️", name: "computer mouse" },
      { emoji: "🖲️", name: "trackball" },
      { emoji: "💽", name: "computer disk" },
      { emoji: "💾", name: "floppy disk" },
      { emoji: "💿", name: "optical disk" },
      { emoji: "📀", name: "dvd" },
      { emoji: "📼", name: "videocassette" },
      { emoji: "📷", name: "camera" },
      { emoji: "📸", name: "camera with flash" },
      { emoji: "📹", name: "video camera" },
      { emoji: "🎥", name: "movie camera" },
      { emoji: "📽️", name: "film projector" },
      { emoji: "📺", name: "television" },
      { emoji: "📻", name: "radio" },
      { emoji: "🎙️", name: "studio microphone" },
      { emoji: "🎚️", name: "level slider" },
      { emoji: "🎛️", name: "control knobs" },
      { emoji: "🧭", name: "compass" },
      { emoji: "⏱️", name: "stopwatch" },
      { emoji: "⏲️", name: "timer clock" },
      { emoji: "⏰", name: "alarm clock" },
      { emoji: "🕰️", name: "mantelpiece clock" },
      { emoji: "📡", name: "satellite antenna" },
      { emoji: "🔋", name: "battery" },
      { emoji: "🔌", name: "electric plug" },
      { emoji: "💡", name: "light bulb" },
      { emoji: "🔦", name: "flashlight" },
      { emoji: "🕯️", name: "candle" },
      { emoji: "🪔", name: "diya lamp" },
      { emoji: "🧯", name: "fire extinguisher" },
      { emoji: "🛢️", name: "oil drum" },
      { emoji: "💸", name: "money with wings" },
      { emoji: "💵", name: "dollar banknote" },
      { emoji: "💴", name: "yen banknote" },
      { emoji: "💶", name: "euro banknote" },
      { emoji: "💷", name: "pound banknote" },
      { emoji: "💰", name: "money bag" },
      { emoji: "💳", name: "credit card" },
      { emoji: "💎", name: "gem stone" },
      { emoji: "⚖️", name: "balance scale" },
      { emoji: "🪜", name: "ladder" },
      { emoji: "🧰", name: "toolbox" },
      { emoji: "🔧", name: "wrench" },
      { emoji: "🔨", name: "hammer" },
      { emoji: "⚒️", name: "hammer and pick" },
      { emoji: "🛠️", name: "hammer and wrench" },
      { emoji: "🔩", name: "nut and bolt" },
      { emoji: "⚙️", name: "gear" },
      { emoji: "🔗", name: "link" },
      { emoji: "⛓️", name: "chains" },
      { emoji: "🪝", name: "hook" },
      { emoji: "🧲", name: "magnet" },
      { emoji: "🔫", name: "pistol" },
      { emoji: "💣", name: "bomb" },
      { emoji: "🧨", name: "firecracker" },
      { emoji: "🪓", name: "axe" },
      { emoji: "🔪", name: "kitchen knife" },
      { emoji: "🗡️", name: "dagger" },
      { emoji: "⚔️", name: "crossed swords" },
      { emoji: "🛡️", name: "shield" },
      { emoji: "🚬", name: "cigarette" },
      { emoji: "⚰️", name: "coffin" },
      { emoji: "🪦", name: "headstone" },
      { emoji: "⚱️", name: "funeral urn" },
      { emoji: "🏺", name: "amphora" },
      { emoji: "🔮", name: "crystal ball" },
      { emoji: "📿", name: "prayer beads" },
      { emoji: "🧿", name: "nazar amulet" },
      { emoji: "💈", name: "barber pole" },
      { emoji: "⚗️", name: "alembic" },
      { emoji: "🔭", name: "telescope" },
      { emoji: "🔬", name: "microscope" },
      { emoji: "🕳️", name: "hole" },
      { emoji: "🩹", name: "adhesive bandage" },
      { emoji: "🩺", name: "stethoscope" },
      { emoji: "💊", name: "pill" },
      { emoji: "💉", name: "syringe" },
      { emoji: "🩸", name: "drop of blood" },
      { emoji: "🧬", name: "dna" },
      { emoji: "🦠", name: "microbe" },
      { emoji: "🧫", name: "petri dish" },
      { emoji: "🧪", name: "test tube" },
      { emoji: "🌡️", name: "thermometer" },
      { emoji: "🧹", name: "broom" },
      { emoji: "🧺", name: "basket" },
      { emoji: "🧻", name: "roll of paper" },
      { emoji: "🚽", name: "toilet" },
      { emoji: "🚿", name: "shower" },
      { emoji: "🛁", name: "bathtub" },
      { emoji: "🛀", name: "person taking bath" },
      { emoji: "🧼", name: "soap" },
      { emoji: "🪥", name: "toothbrush" },
      { emoji: "🪒", name: "razor" },
      { emoji: "🧽", name: "sponge" },
      { emoji: "🪣", name: "bucket" },
      { emoji: "🧴", name: "lotion bottle" },
      { emoji: "🛎️", name: "bellhop bell" },
      { emoji: "🔑", name: "key" },
      { emoji: "🗝️", name: "old key" },
      { emoji: "🚪", name: "door" },
      { emoji: "🪑", name: "chair" },
      { emoji: "🛋️", name: "couch and lamp" },
      { emoji: "🛏️", name: "bed" },
      { emoji: "🛌", name: "person in bed" },
      { emoji: "🧸", name: "teddy bear" },
      { emoji: "🖼️", name: "framed picture" },
      { emoji: "🪞", name: "mirror" },
      { emoji: "🪟", name: "window" },
      { emoji: "🛍️", name: "shopping bags" },
      { emoji: "🛒", name: "shopping cart" },
      { emoji: "🎁", name: "wrapped gift" },
      { emoji: "🎈", name: "balloon" },
      { emoji: "🎏", name: "carp streamer" },
      { emoji: "🎀", name: "ribbon" },
      { emoji: "🎊", name: "confetti ball" },
      { emoji: "🎉", name: "party popper" },
      { emoji: "🎎", name: "Japanese dolls" },
      { emoji: "🏮", name: "red paper lantern" },
      { emoji: "🎐", name: "wind chime" },
      { emoji: "🧧", name: "red envelope" },
      { emoji: "📩", name: "envelope with arrow" },
      { emoji: "📨", name: "incoming envelope" },
      { emoji: "📧", name: "e-mail" },
      { emoji: "💌", name: "love letter" },
      { emoji: "📮", name: "postbox" },
      { emoji: "📪", name: "closed mailbox with lowered flag" },
      { emoji: "📫", name: "closed mailbox with raised flag" },
      { emoji: "📬", name: "open mailbox with raised flag" },
      { emoji: "📭", name: "open mailbox with lowered flag" },
      { emoji: "📦", name: "package" },
      { emoji: "📯", name: "postal horn" },
      { emoji: "📜", name: "scroll" },
      { emoji: "📃", name: "page with curl" },
      { emoji: "📄", name: "page facing up" },
      { emoji: "📑", name: "bookmark tabs" },
      { emoji: "🧾", name: "receipt" },
      { emoji: "📊", name: "bar chart" },
      { emoji: "📈", name: "chart increasing" },
      { emoji: "📉", name: "chart decreasing" },
      { emoji: "📰", name: "newspaper" },
      { emoji: "🗞️", name: "rolled-up newspaper" },
      { emoji: "📁", name: "file folder" },
      { emoji: "📂", name: "open file folder" },
      { emoji: "🗂️", name: "card index dividers" },
      { emoji: "📅", name: "calendar" },
      { emoji: "📆", name: "tear-off calendar" },
      { emoji: "🗒️", name: "spiral notepad" },
      { emoji: "🗓️", name: "spiral calendar" },
      { emoji: "📇", name: "card index" },
      { emoji: "📋", name: "clipboard" },
      { emoji: "📌", name: "pushpin" },
      { emoji: "📍", name: "round pushpin" },
      { emoji: "📎", name: "paperclip" },
      { emoji: "🖇️", name: "linked paperclips" },
      { emoji: "📏", name: "straight ruler" },
      { emoji: "📐", name: "triangular ruler" },
      { emoji: "✂️", name: "scissors" },
      { emoji: "🗃️", name: "card file box" },
      { emoji: "🗄️", name: "file cabinet" },
      { emoji: "🗑️", name: "wastebasket" },
      { emoji: "🔒", name: "locked" },
      { emoji: "🔓", name: "unlocked" },
      { emoji: "🔏", name: "locked with pen" },
      { emoji: "🔐", name: "locked with key" },
      { emoji: "✏️", name: "pencil" },
      { emoji: "🖊️", name: "pen" },
      { emoji: "🖋️", name: "fountain pen" },
      { emoji: "✒️", name: "black nib" },
      { emoji: "🖌️", name: "paintbrush" },
      { emoji: "🖍️", name: "crayon" },
      { emoji: "📝", name: "memo" },
      { emoji: "📒", name: "ledger" },
      { emoji: "📔", name: "notebook with decorative cover" },
      { emoji: "📕", name: "closed book" },
      { emoji: "📗", name: "green book" },
      { emoji: "📘", name: "blue book" },
      { emoji: "📙", name: "orange book" },
      { emoji: "📚", name: "books" },
      { emoji: "📖", name: "open book" },
      { emoji: "🔖", name: "bookmark" },
      { emoji: "🏷️", name: "label" },
    ]
  },
  {
    name: "symbols",
    label: "Symbols",
    icon: "❤️",
    emojis: [
      { emoji: "❤️", name: "red heart" },
      { emoji: "🧡", name: "orange heart" },
      { emoji: "💛", name: "yellow heart" },
      { emoji: "💚", name: "green heart" },
      { emoji: "💙", name: "blue heart" },
      { emoji: "💜", name: "purple heart" },
      { emoji: "🖤", name: "black heart" },
      { emoji: "🤍", name: "white heart" },
      { emoji: "🤎", name: "brown heart" },
      { emoji: "💔", name: "broken heart" },
      { emoji: "❣️", name: "heart exclamation" },
      { emoji: "💕", name: "two hearts" },
      { emoji: "💞", name: "revolving hearts" },
      { emoji: "💓", name: "beating heart" },
      { emoji: "💗", name: "growing heart" },
      { emoji: "💖", name: "sparkling heart" },
      { emoji: "💘", name: "heart with arrow" },
      { emoji: "💝", name: "heart with ribbon" },
      { emoji: "💟", name: "heart decoration" },
      { emoji: "☮️", name: "peace symbol" },
      { emoji: "✝️", name: "latin cross" },
      { emoji: "☪️", name: "star and crescent" },
      { emoji: "🕉️", name: "om" },
      { emoji: "☸️", name: "wheel of dharma" },
      { emoji: "✡️", name: "star of David" },
      { emoji: "🔯", name: "dotted six-pointed star" },
      { emoji: "🕎", name: "menorah" },
      { emoji: "☯️", name: "yin yang" },
      { emoji: "☦️", name: "orthodox cross" },
      { emoji: "🛐", name: "place of worship" },
      { emoji: "⛎", name: "Ophiuchus" },
      { emoji: "♈", name: "Aries" },
      { emoji: "♉", name: "Taurus" },
      { emoji: "♊", name: "Gemini" },
      { emoji: "♋", name: "Cancer" },
      { emoji: "♌", name: "Leo" },
      { emoji: "♍", name: "Virgo" },
      { emoji: "♎", name: "Libra" },
      { emoji: "♏", name: "Scorpio" },
      { emoji: "♐", name: "Sagittarius" },
      { emoji: "♑", name: "Capricorn" },
      { emoji: "♒", name: "Aquarius" },
      { emoji: "♓", name: "Pisces" },
      { emoji: "🆔", name: "ID button" },
      { emoji: "⚛️", name: "atom symbol" },
      { emoji: "🉑", name: "Japanese acceptable button" },
      { emoji: "☢️", name: "radioactive" },
      { emoji: "☣️", name: "biohazard" },
      { emoji: "📴", name: "mobile phone off" },
      { emoji: "📳", name: "vibration mode" },
      { emoji: "🈶", name: "Japanese not free of charge button" },
      { emoji: "🈚", name: "Japanese free of charge button" },
      { emoji: "🈸", name: "Japanese application button" },
      { emoji: "🈺", name: "Japanese open for business button" },
      { emoji: "🈷️", name: "Japanese monthly amount button" },
      { emoji: "✴️", name: "eight-pointed star" },
      { emoji: "🆚", name: "VS button" },
      { emoji: "💮", name: "white flower" },
      { emoji: "🉐", name: "Japanese bargain button" },
      { emoji: "㊙️", name: "Japanese secret button" },
      { emoji: "㊗️", name: "Japanese congratulations button" },
      { emoji: "🈴", name: "Japanese passing grade button" },
      { emoji: "🈵", name: "Japanese no vacancy button" },
      { emoji: "🈹", name: "Japanese discount button" },
      { emoji: "🈲", name: "Japanese prohibited button" },
      { emoji: "🅰️", name: "A button blood type" },
      { emoji: "🅱️", name: "B button blood type" },
      { emoji: "🆎", name: "AB button blood type" },
      { emoji: "🆑", name: "CL button" },
      { emoji: "🅾️", name: "O button blood type" },
      { emoji: "🆘", name: "SOS button" },
      { emoji: "❌", name: "cross mark" },
      { emoji: "⭕", name: "hollow red circle" },
      { emoji: "🛑", name: "stop sign" },
      { emoji: "⛔", name: "no entry" },
      { emoji: "📛", name: "name badge" },
      { emoji: "🚫", name: "prohibited" },
      { emoji: "💯", name: "hundred points" },
      { emoji: "💢", name: "anger symbol" },
      { emoji: "♨️", name: "hot springs" },
      { emoji: "🚷", name: "no pedestrians" },
      { emoji: "🚯", name: "no littering" },
      { emoji: "🚳", name: "no bicycles" },
      { emoji: "🚱", name: "non-potable water" },
      { emoji: "🔞", name: "no one under eighteen" },
      { emoji: "📵", name: "no mobile phones" },
      { emoji: "🚭", name: "no smoking" },
      { emoji: "❗", name: "exclamation mark" },
      { emoji: "❕", name: "white exclamation mark" },
      { emoji: "❓", name: "question mark" },
      { emoji: "❔", name: "white question mark" },
      { emoji: "‼️", name: "double exclamation mark" },
      { emoji: "⁉️", name: "exclamation question mark" },
      { emoji: "🔅", name: "dim button" },
      { emoji: "🔆", name: "bright button" },
      { emoji: "〽️", name: "part alternation mark" },
      { emoji: "⚠️", name: "warning" },
      { emoji: "🚸", name: "children crossing" },
      { emoji: "🔱", name: "trident emblem" },
      { emoji: "⚜️", name: "fleur-de-lis" },
      { emoji: "🔰", name: "Japanese symbol for beginner" },
      { emoji: "♻️", name: "recycling symbol" },
      { emoji: "✅", name: "check mark button" },
      { emoji: "🈯", name: "Japanese reserved button" },
      { emoji: "💹", name: "chart increasing with yen" },
      { emoji: "❇️", name: "sparkle" },
      { emoji: "✳️", name: "eight-spoked asterisk" },
      { emoji: "❎", name: "cross mark button" },
      { emoji: "🌐", name: "globe with meridians" },
      { emoji: "💠", name: "diamond with a dot" },
      { emoji: "Ⓜ️", name: "circled M" },
      { emoji: "🌀", name: "cyclone" },
      { emoji: "💤", name: "zzz" },
      { emoji: "🏧", name: "ATM sign" },
      { emoji: "🚾", name: "water closet" },
      { emoji: "♿", name: "wheelchair symbol" },
      { emoji: "🅿️", name: "P button" },
      { emoji: "🛗", name: "elevator" },
      { emoji: "🈳", name: "Japanese vacancy button" },
      { emoji: "🈂️", name: "Japanese service charge button" },
      { emoji: "🛂", name: "passport control" },
      { emoji: "🛃", name: "customs" },
      { emoji: "🛄", name: "baggage claim" },
      { emoji: "🛅", name: "left luggage" },
      { emoji: "🚹", name: "men's room" },
      { emoji: "🚺", name: "women's room" },
      { emoji: "🚼", name: "baby symbol" },
      { emoji: "⚧️", name: "transgender symbol" },
      { emoji: "🚻", name: "restroom" },
      { emoji: "🚮", name: "litter in bin sign" },
      { emoji: "🎦", name: "cinema" },
      { emoji: "📶", name: "antenna bars" },
      { emoji: "🈁", name: "Japanese here button" },
      { emoji: "🔣", name: "input symbols" },
      { emoji: "ℹ️", name: "information" },
      { emoji: "🔤", name: "input latin letters" },
      { emoji: "🔡", name: "input latin lowercase" },
      { emoji: "🔠", name: "input latin uppercase" },
      { emoji: "🆖", name: "NG button" },
      { emoji: "🆗", name: "OK button" },
      { emoji: "🆙", name: "UP! button" },
      { emoji: "🆒", name: "COOL button" },
      { emoji: "🆕", name: "NEW button" },
      { emoji: "🆓", name: "FREE button" },
      { emoji: "0️⃣", name: "keycap 0" },
      { emoji: "1️⃣", name: "keycap 1" },
      { emoji: "2️⃣", name: "keycap 2" },
      { emoji: "3️⃣", name: "keycap 3" },
      { emoji: "4️⃣", name: "keycap 4" },
      { emoji: "5️⃣", name: "keycap 5" },
      { emoji: "6️⃣", name: "keycap 6" },
      { emoji: "7️⃣", name: "keycap 7" },
      { emoji: "8️⃣", name: "keycap 8" },
      { emoji: "9️⃣", name: "keycap 9" },
      { emoji: "🔟", name: "keycap 10" },
      { emoji: "🔢", name: "input numbers" },
      { emoji: "#️⃣", name: "keycap number sign" },
      { emoji: "*️⃣", name: "keycap asterisk" },
      { emoji: "⏏️", name: "eject button" },
      { emoji: "▶️", name: "play button" },
      { emoji: "⏸️", name: "pause button" },
      { emoji: "⏯️", name: "play or pause button" },
      { emoji: "⏹️", name: "stop button" },
      { emoji: "⏺️", name: "record button" },
      { emoji: "⏭️", name: "next track button" },
      { emoji: "⏮️", name: "last track button" },
      { emoji: "⏩", name: "fast-forward button" },
      { emoji: "⏪", name: "fast reverse button" },
      { emoji: "⏫", name: "fast up button" },
      { emoji: "⏬", name: "fast down button" },
      { emoji: "◀️", name: "reverse button" },
      { emoji: "🔼", name: "upwards button" },
      { emoji: "🔽", name: "downwards button" },
      { emoji: "➡️", name: "right arrow" },
      { emoji: "⬅️", name: "left arrow" },
      { emoji: "⬆️", name: "up arrow" },
      { emoji: "⬇️", name: "down arrow" },
      { emoji: "↗️", name: "up-right arrow" },
      { emoji: "↘️", name: "down-right arrow" },
      { emoji: "↙️", name: "down-left arrow" },
      { emoji: "↖️", name: "up-left arrow" },
      { emoji: "↕️", name: "up-down arrow" },
      { emoji: "↔️", name: "left-right arrow" },
      { emoji: "↪️", name: "left arrow curving right" },
      { emoji: "↩️", name: "right arrow curving left" },
      { emoji: "⤴️", name: "right arrow curving up" },
      { emoji: "⤵️", name: "right arrow curving down" },
      { emoji: "🔀", name: "shuffle tracks button" },
      { emoji: "🔁", name: "repeat button" },
      { emoji: "🔂", name: "repeat single button" },
      { emoji: "🔄", name: "counterclockwise arrows button" },
      { emoji: "🔃", name: "clockwise vertical arrows" },
      { emoji: "🎵", name: "musical note" },
      { emoji: "🎶", name: "musical notes" },
      { emoji: "➕", name: "plus" },
      { emoji: "➖", name: "minus" },
      { emoji: "➗", name: "divide" },
      { emoji: "✖️", name: "multiply" },
      { emoji: "♾️", name: "infinity" },
      { emoji: "💲", name: "heavy dollar sign" },
      { emoji: "💱", name: "currency exchange" },
      { emoji: "™️", name: "trade mark" },
      { emoji: "©️", name: "copyright" },
      { emoji: "®️", name: "registered" },
      { emoji: "👁️‍🗨️", name: "eye in speech bubble" },
      { emoji: "🔚", name: "END arrow" },
      { emoji: "🔙", name: "BACK arrow" },
      { emoji: "🔛", name: "ON! arrow" },
      { emoji: "🔝", name: "TOP arrow" },
      { emoji: "🔜", name: "SOON arrow" },
      { emoji: "〰️", name: "wavy dash" },
      { emoji: "➰", name: "curly loop" },
      { emoji: "➿", name: "double curly loop" },
      { emoji: "✔️", name: "check mark" },
      { emoji: "☑️", name: "check box with check" },
      { emoji: "🔘", name: "radio button" },
      { emoji: "🔴", name: "red circle" },
      { emoji: "🟠", name: "orange circle" },
      { emoji: "🟡", name: "yellow circle" },
      { emoji: "🟢", name: "green circle" },
      { emoji: "🔵", name: "blue circle" },
      { emoji: "🟣", name: "purple circle" },
      { emoji: "🟤", name: "brown circle" },
      { emoji: "⚫", name: "black circle" },
      { emoji: "⚪", name: "white circle" },
      { emoji: "🟥", name: "red square" },
      { emoji: "🟧", name: "orange square" },
      { emoji: "🟨", name: "yellow square" },
      { emoji: "🟩", name: "green square" },
      { emoji: "🟦", name: "blue square" },
      { emoji: "🟪", name: "purple square" },
      { emoji: "🟫", name: "brown square" },
      { emoji: "⬛", name: "black large square" },
      { emoji: "⬜", name: "white large square" },
      { emoji: "◼️", name: "black medium square" },
      { emoji: "◻️", name: "white medium square" },
      { emoji: "◾", name: "black medium-small square" },
      { emoji: "◽", name: "white medium-small square" },
      { emoji: "▪️", name: "black small square" },
      { emoji: "▫️", name: "white small square" },
      { emoji: "🔶", name: "large orange diamond" },
      { emoji: "🔷", name: "large blue diamond" },
      { emoji: "🔸", name: "small orange diamond" },
      { emoji: "🔹", name: "small blue diamond" },
      { emoji: "🔺", name: "red triangle pointed up" },
      { emoji: "🔻", name: "red triangle pointed down" },
      { emoji: "💭", name: "thought balloon" },
      { emoji: "🗯️", name: "right anger bubble" },
      { emoji: "💬", name: "speech balloon" },
      { emoji: "🗨️", name: "left speech bubble" },
      { emoji: "🗣️", name: "speaking head" },
      { emoji: "👤", name: "bust in silhouette" },
      { emoji: "👥", name: "busts in silhouette" },
    ]
  }
];

// Max recent emojis to store
export const MAX_RECENT = 24;

// Storage key
export const RECENT_EMOJIS_KEY = "elixirchat_recent_emojis";
```

### LiveView Emoji Picker Hook
```javascript
// assets/js/hooks/emoji_picker.js
import { emojiCategories, MAX_RECENT, RECENT_EMOJIS_KEY } from "../emoji-data";

const EmojiPicker = {
  mounted() {
    this.isOpen = false;
    this.activeCategory = "recent";
    this.searchQuery = "";
    this.recentEmojis = this.loadRecentEmojis();
    
    // Set up click outside handler
    this.clickOutsideHandler = (e) => {
      if (this.isOpen && !this.el.contains(e.target)) {
        this.close();
      }
    };
    
    document.addEventListener("click", this.clickOutsideHandler);
    
    // Set up event handlers
    this.el.querySelector("[data-emoji-toggle]").addEventListener("click", (e) => {
      e.stopPropagation();
      this.toggle();
    });
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
    this.render();
  },
  
  close() {
    this.isOpen = false;
    const picker = this.el.querySelector("[data-emoji-picker]");
    if (picker) picker.classList.add("hidden");
  },
  
  selectEmoji(emoji) {
    this.saveRecentEmoji(emoji);
    this.pushEvent("insert_emoji", { emoji });
    this.close();
  },
  
  render() {
    // Implementation renders the picker UI
  }
};

export default EmojiPicker;
```

### UI in ChatLive
```heex
<%!-- Emoji picker button and popover --%>
<div id="emoji-picker" phx-hook="EmojiPicker" class="relative">
  <button
    type="button"
    data-emoji-toggle
    class="btn btn-ghost btn-circle"
    title="Add emoji"
  >
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
      <path stroke-linecap="round" stroke-linejoin="round" d="M15.182 15.182a4.5 4.5 0 0 1-6.364 0M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM9.75 9.75c0 .414-.168.75-.375.75S9 10.164 9 9.75 9.168 9 9.375 9s.375.336.375.75Zm-.375 0h.008v.015h-.008V9.75Zm5.625 0c0 .414-.168.75-.375.75s-.375-.336-.375-.75.168-.75.375-.75.375.336.375.75Zm-.375 0h.008v.015h-.008V9.75Z" />
    </svg>
  </button>
  
  <div data-emoji-picker class="hidden absolute bottom-12 right-0 z-50 bg-base-100 rounded-lg shadow-xl border border-base-300 w-80">
    <%!-- Search input --%>
    <div class="p-2 border-b border-base-300">
      <input
        type="text"
        placeholder="Search emojis..."
        class="input input-sm input-bordered w-full"
        data-emoji-search
      />
    </div>
    
    <%!-- Category tabs --%>
    <div class="flex border-b border-base-300 overflow-x-auto" data-category-tabs>
      <!-- Rendered by JS hook -->
    </div>
    
    <%!-- Emoji grid --%>
    <div class="h-64 overflow-y-auto p-2" data-emoji-grid>
      <!-- Rendered by JS hook -->
    </div>
  </div>
</div>
```

### CSS Styles
```css
/* Emoji picker styles */
.emoji-grid {
  display: grid;
  grid-template-columns: repeat(8, 1fr);
  gap: 2px;
}

.emoji-btn {
  @apply p-1 text-xl rounded hover:bg-base-200 cursor-pointer transition-colors;
  aspect-ratio: 1;
  display: flex;
  align-items: center;
  justify-content: center;
}

.emoji-btn:hover {
  transform: scale(1.2);
}

.emoji-category-tab {
  @apply p-2 text-lg hover:bg-base-200 cursor-pointer;
}

.emoji-category-tab.active {
  @apply bg-base-200 border-b-2 border-primary;
}
```

## Acceptance Criteria
- [ ] Emoji button visible next to message input
- [ ] Clicking button opens emoji picker popover
- [ ] Emojis organized by categories with tabs
- [ ] Can navigate between categories
- [ ] Clicking emoji inserts it into message input at cursor position
- [ ] Picker closes after selecting emoji
- [ ] Clicking outside picker closes it
- [ ] Recent emojis category shows recently used emojis
- [ ] Recently used emojis persist across sessions (localStorage)
- [ ] Search/filter emojis by name works
- [ ] Picker works on mobile devices
- [ ] Works alongside existing features (mentions, attachments)

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Click emoji button and verify picker opens
- Select an emoji and verify it's inserted into message input
- Switch between emoji categories
- Search for "heart" and verify relevant emojis appear
- Use an emoji, then reopen picker and verify it appears in "Recent"
- Close browser, reopen, and verify recent emojis persist
- Try on mobile viewport
- Send a message with emojis and verify they display correctly
- Test in both direct and group chats

## Edge Cases to Handle
- Empty recent emojis (first time user)
- Search with no results
- Very long message input (cursor position handling)
- Mobile touch events
- Picker positioning near screen edges
- Multiple rapid emoji selections
- Keyboard navigation (optional enhancement)

## Future Enhancements (not in this task)
- Skin tone selector for applicable emojis
- Custom/slack-style emoji support
- Emoji shortcodes (:smile:)
- Frequently used (based on count, not recency)
- Animated emoji/GIF support
- Keyboard shortcuts (Ctrl+E or : trigger)
