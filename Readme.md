# 🇮🇳 IndicKeyboardKit  
### A Drop-In Multi-Language Keyboard for iOS (SwiftUI)

IndicKeyboardKit is a fully self-contained **in-app keyboard** for iOS supporting **16+ Indic languages + English**.  
It includes Gboard-style popups, matras, smart delete logic, accurate cursor control, a number pad, and optional Google-powered suggestions.

> ⚠️ This is **not a System Keyboard Extension**.  
> It is an **in-app keyboard UI** that you embed inside any SwiftUI / UIKit screen.

---

## ✨ Features

- ✔ **All major Indic languages** (Hindi, Marathi, Bengali, Tamil, Telugu, Kannada, Malayalam, Odia, Gujarati, Punjabi, Assamese, Urdu, Sanskrit)
- ✔ **Long-press popup characters** (matras, glyph variants)
- ✔ **Smart delete** for Devanagari (delete matra first → consonant second)
- ✔ **Tap cursor + text selection** (using custom UITextView wrapper)
- ✔ **Number pad / symbols pad** included
- ✔ **Google suggestion bar**
- ✔ **Only two files required**
  - `IndicKeyboard.swift`
  - `AllLanguageKeys.swift`

---

## 📦 Installation

### **Manual Setup (Recommended)**

Copy these two files directly into your project:

Sources/
│── IndicKeyboard.swift
│── AllLanguageKeys.swift

yaml
Copy code

No need for SPM, CocoaPods, or linking frameworks.

---

## 🚀 Quick Start (Integrate Keyboard in < 2 Minutes)

### **1️⃣ Import SwiftUI**
```swift
import SwiftUI
2️⃣ Create a text state
swift
Copy code
@State private var text = ""
3️⃣ Add the Indic Keyboard
swift
Copy code
IndicKeyboardEditor(
    text: $text,
    languageCode: "hi"       // choose any language
)
You now have a complete full-feature keyboard inside your app.

🌐 Supported Languages
Use these codes for languageCode:

Language	Code
Hindi	"hi"
Marathi	"mr"
Bengali	"bn"
Tamil	"ta"
Telugu	"te"
Kannada	"kn"
Malayalam	"ml"
Gujarati	"gu"
Punjabi	"pa"
Odia	"or"
Assamese	"as"
Sanskrit	"sa"
Urdu	"ur"
English	"en"

Example:

swift
Copy code
IndicKeyboardEditor(text: $text, languageCode: "bn")   // Bengali
🔄 Dynamic Language Switching
swift
Copy code
@State private var selectedLanguage = "hi"

Picker("Language", selection: $selectedLanguage) {
    Text("Hindi").tag("hi")
    Text("Tamil").tag("ta")
    Text("English").tag("en")
}

IndicKeyboardEditor(text: $text, languageCode: selectedLanguage)
The keyboard reloads automatically when the language changes.

🧩 Popup Keys (Matras & Glyph Variants)
Popups are controlled by your AllLanguageKeys.swift:

swift
Copy code
KeyModel(main: "क", popup: ["का", "कि", "की", "कु", "कू"])
Long-press on "क" → user sees a popup grid with all variants.

💡 Smart Delete (Exclusive Feature)
For Devanagari languages (hi, mr, sa):

If last character is a matra → delete only matra

If no matra → delete entire consonant cluster

This matches Gboard behavior.

🔢 Number Pad / Symbols Pad
When the user taps 123, the keyboard switches to:

Number row (0–9)

Symbols

DEL

ABC to return

Symbol keys come from symbolKeys in AllLanguageKeys.swift.

🧭 Accurate Cursor Control (UITextView Wrapper)
The built-in EditableTextView supports:

Tap to move cursor

Drag to select text

Cursor works correctly for Indic UTF-16 characters

System keyboard stays hidden

🧪 Demo Usage Example
swift
Copy code
struct DemoEditor: View {
    @State private var text = ""

    var body: some View {
        VStack {
            Text("Type below:")
            TextEditor(text: $text)
                .frame(height: 200)
                .border(Color.gray)

            IndicKeyboardEditor(text: $text, languageCode: "ta")  // Tamil
        }
    }
}
📁 Recommended Repository Structure
Copy code
IndicKeyboardKit/
│
├── Sources/
│   ├── IndicKeyboard.swift
│   ├── AllLanguageKeys.swift
│
├── Example/
│   └── DemoApp/
│
└── README.md
➕ Add Your Own Language
Open AllLanguageKeys.swift

Add a new case:

swift
Copy code
case "ne":   // Nepali
    return nepaliRows
Define keys/popup rows

Keyboard loads automatically. No extra code required.

📥 Disable Suggestions (Optional)
Remove these lines from IndicKeyboardEditor:

swift
Copy code
.onChange(of: text) { _ in updateSuggestions() }
.onChange(of: cursorUTF16Pos) { _ in updateSuggestions() }
Or empty the suggestion bar by returning an empty array.

❤️ Contributing
Pull requests are welcome for:

New languages

Better UI

Improved popups

Transliteration support

Performance upgrades

📜 License
MIT License — Free to use commercially.

🎉 Done!
Your app now supports a modern, customizable, multilingual Indic keyboard with:

Smart delete

Popups

Matras

Suggestions

Cursor control

SwiftUI support

Just use:

swift
Copy code
IndicKeyboardEditor(text: $text, languageCode: "hi")
