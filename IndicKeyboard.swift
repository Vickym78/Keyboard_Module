//
//  IndicKeyboard.swift
//  IndicKeyboardKit
//
//  Single-file multi-language Indic keyboard (in-app, not system extension)
//
//  Usage:
//
//  struct YourView: View {
//      @State private var text = ""
//
//      var body: some View {
//          VStack {
//              TextEditor(text: $text)
//                  .frame(height: 200)
//                  .padding()
//
//              IndicKeyboardEditor(
//                  text: $text,
//                  languageCode: "hi"   // "hi", "bn", "ta", "mr", "en", etc.
//              )
//          }
//      }
//  }
//
//  NOTE: This file depends on AllLanguageKeys.swift
//  (keysForLang(_:) and symbolKeys must be defined there).
//

import SwiftUI
import UIKit

// MARK: - Google Word Suggester (uses HTTPS)
actor GoogleWordSuggester {
    private let session = URLSession(configuration: .ephemeral)

    func suggest(_ text: String, lang: String) async -> [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, query.count >= 2 else { return [] }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let hl = lang == "en" ? "en" : "\(lang)-IN"
        // ✅ Use HTTPS to avoid ATS error
        let urlStr = "https://suggestqueries.google.com/complete/search?client=firefox&hl=\(hl)&q=\(encoded)"

        guard let url = URL(string: urlStr) else { return [] }

        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count >= 2,
                  let suggestions = json[1] as? [String] else { return [] }
            return Array(suggestions.prefix(8))
        } catch {
            print("Suggestion error: \(error)")
            return []
        }
    }
}

// MARK: - Public entry: IndicKeyboardEditor

/// A complete editor + keyboard + suggestion bar for a given language code.
public struct IndicKeyboardEditor: View {

    @Binding public var text: String
    public let languageCode: String

    @State private var cursorUTF16Pos = 0
    @State private var selectionLengthUTF16 = 0

    @State private var suggestions: [String] = []
    @State private var currentWord = ""

    @State private var debounceTask: Task<Void, Never>? = nil

    private let suggester = GoogleWordSuggester()

    public init(text: Binding<String>, languageCode: String) {
        self._text = text
        self.languageCode = languageCode
    }

    public var body: some View {
        VStack(spacing: 0) {

            // Text area (uses UITextView under the hood, so no system keyboard)
            EditableTextView(
                text: $text,
                cursorUTF16Pos: $cursorUTF16Pos,
                selectionLength: $selectionLengthUTF16
            )
            .frame(height: 220)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)

            // Suggestion bar
            ZStack {
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(suggestions, id: \.self) { word in
                                Button {
                                    replaceCurrentWord(with: word + " ")
                                } label: {
                                    Text(word)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.15))
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .frame(height: 48)
                } else {
                    // fixed height spacer so layout doesn't jump
                    HStack { Spacer() }
                        .frame(height: 48)
                        .background(Color.clear)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: suggestions)

            // Actual QWERTY keyboard
            QWERTYKeyboardView(
                text: $text,
                cursorUTF16Pos: $cursorUTF16Pos,
                selectionLengthUTF16: $selectionLengthUTF16,
                langCode: languageCode
            )
            .id(languageCode)   // re-render when language changes
        }
        .background(Color(.systemBackground))
        .onChange(of: text) { _ in updateSuggestions() }
        .onChange(of: cursorUTF16Pos) { _ in updateSuggestions() }
    }

    // MARK: - Suggestion logic (debounced)
    private func updateSuggestions() {
        debounceTask?.cancel()

        let textSnapshot = text
        let cursorSnapshot = cursorUTF16Pos
        let lang = languageCode

        debounceTask = Task {
            // Debounce ~150 ms
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }

            let ns = textSnapshot as NSString
            let safeCursor = min(max(0, cursorSnapshot), ns.length)

            var start = safeCursor
            while start > 0 &&
                !ns.substring(with: NSRange(location: start - 1, length: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                start -= 1
            }

            var end = safeCursor
            while end < ns.length &&
                !ns.substring(with: NSRange(location: end, length: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                end += 1
            }

            guard end > start else {
                await MainActor.run {
                    suggestions = []
                    currentWord = ""
                }
                return
            }

            let word = ns.substring(with: NSRange(location: start, length: end - start))
            let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleaned.isEmpty, cleaned.count >= 2 else {
                await MainActor.run {
                    suggestions = []
                    currentWord = ""
                }
                return
            }

            let result = await suggester.suggest(cleaned, lang: lang)

            await MainActor.run {
                suggestions = result
                currentWord = cleaned
            }
        }
    }

    private func currentWordAndRange() -> (String?, NSRange?) {

        let ns = text as NSString
        let cursor = cursorUTF16Pos

        guard cursor <= ns.length else { return (nil, nil) }

        var start = cursor
        while start > 0 &&
                !ns.substring(with: NSRange(location: start-1, length: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            start -= 1
        }

        var end = cursor
        while end < ns.length &&
                !ns.substring(with: NSRange(location: end, length: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            end += 1
        }

        guard end > start else { return (nil, nil) }
        return (ns.substring(with: NSRange(location: start, length: end - start)),
                NSRange(location: start, length: end - start))
    }

    private func replaceCurrentWord(with newWord: String) {
        let ns = text as NSString
        let (_, rangeOpt) = currentWordAndRange()
        guard let r = rangeOpt else { return }

        text = ns.replacingCharacters(in: r, with: newWord)
        let newPos = r.location + newWord.utf16.count

        DispatchQueue.main.async {
            self.cursorUTF16Pos = newPos
            self.selectionLengthUTF16 = 0
        }

        suggestions = []
    }
}

// MARK: - UITextView Wrapper (tap cursor, no system keyboard)
struct EditableTextView: UIViewRepresentable {

    @Binding var text: String
    @Binding var cursorUTF16Pos: Int
    @Binding var selectionLength: Int

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 22)
        tv.delegate = context.coordinator
        tv.autocorrectionType = .no
        tv.backgroundColor = .clear
        tv.inputView = UIView()        // Disable system keyboard
        tv.isScrollEnabled = true
        tv.text = text

        // Enable tap-to-place cursor
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGesture.cancelsTouchesInView = false
        tv.addGestureRecognizer(tapGesture)

        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {

        // Sync text
        if uiView.text != text {
            uiView.text = text
        }

        // Sync selection
        let desiredRange = NSRange(location: cursorUTF16Pos, length: selectionLength)
        if uiView.selectedRange != desiredRange {

            let maxLen = (uiView.text as NSString).length
            let loc = max(0, min(desiredRange.location, maxLen))
            let len = max(0, min(desiredRange.length, maxLen - loc))

            uiView.selectedRange = NSRange(location: loc, length: len)
        }

        // Make first responder once so cursor shows immediately
        if !context.coordinator.didBecomeFirstResponder {
            uiView.becomeFirstResponder()
            context.coordinator.didBecomeFirstResponder = true
            uiView.selectedRange = desiredRange
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {

        var parent: EditableTextView
        var didBecomeFirstResponder = false
        private var isProgrammaticChange = false

        init(_ parent: EditableTextView) {
            self.parent = parent
        }

        // Tap → move cursor
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            let location = gesture.location(in: textView)

            if let position = textView.closestPosition(to: location) {

                let offset = textView.offset(
                    from: textView.beginningOfDocument,
                    to: position
                )

                parent.cursorUTF16Pos = offset
                parent.selectionLength = 0

                textView.selectedRange = NSRange(location: offset, length: 0)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            isProgrammaticChange = true

            parent.text = textView.text
            parent.cursorUTF16Pos = textView.selectedRange.location
            parent.selectionLength = textView.selectedRange.length

            isProgrammaticChange = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isProgrammaticChange else { return }

            parent.cursorUTF16Pos = textView.selectedRange.location
            parent.selectionLength = textView.selectedRange.length
        }
    }
}

// ---------------------------------------------------------
// SUPER-SMOOTH SPACE KEY
// ---------------------------------------------------------
struct FastKey: View {

    let label: String
    let action: () -> Void
    var textColor: Color = .blue   // default blue text

    var body: some View {
        Text(label)
            .font(.system(size: 20))
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity, maxHeight: 50)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if value.startLocation == value.location {
                            action()
                        }
                    }
            )
    }
}

// MARK: - Keyboard View
struct QWERTYKeyboardView: View {

    @Binding var text: String
    @Binding var cursorUTF16Pos: Int
    @Binding var selectionLengthUTF16: Int
    let langCode: String

    @State private var isNumberMode = false

    @State private var shiftOn = false
    @State private var capsLock = false
    @State private var blockIndex = 0  // which block of letters (for local langs)
    @State private var deleteTimer: Timer? = nil

    // Row counts for letters
    private let row1Count = 10
    private let row2Count = 9
    private let row3EnglishCount = 7
    private let row3LocalCount = 5

    private var slotsPerBlock: Int {
        if langCode == "en" {
            return row1Count + row2Count + row3EnglishCount
        } else {
            return row1Count + row2Count + row3LocalCount
        }
    }

    var body: some View {
        VStack(spacing: 8) {

            if isNumberMode {
                SymbolPad(onKey: handleKey, onABC: { isNumberMode = false })
            } else {
                letters
                actionRow
            }

            // Bottom hint label (ONLY Indic Languages)
            if langCode != "en" {
                Text("Long press keys to see matra and more characters")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.orange.opacity(0.85))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                    .padding(.top, 6)
            }
        }
        .padding(8)
        .background(Color(.systemBackground))
    }

    // Start auto-delete
    private func startDeleting() {
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
            handleKey("DEL")
        }
    }
    // Stop repeating when touch ends
    private func stopDeleting() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    // MARK: - Letter rows
    private var letters: some View {
        let flat = flattenLanguageKeys()

        let blocks: [[String]]
        if langCode == "en" {
            blocks = [Array(flat.prefix(slotsPerBlock))]
        } else {
            var tmp: [[String]] = []
            var i = 0
            while i < flat.count {
                let end = min(i + slotsPerBlock, flat.count)
                tmp.append(Array(flat[i..<end]))
                i += slotsPerBlock
            }
            blocks = tmp.isEmpty ? [[]] : tmp
        }

        let activeBlockIndex = (langCode == "en") ? 0 : blockIndex
        let block = blocks[safe: activeBlockIndex] ?? []

        return VStack(spacing: 6) {

            // Row 1
            HStack(spacing: 6) {
                ForEach(0..<row1Count, id: \.self) { i in
                    keyButton(block[safe: i] ?? "")
                }
            }

            // Row 2
            HStack(spacing: 6) {
                ForEach(0..<row2Count, id: \.self) { i in
                    keyButton(block[safe: row1Count + i] ?? "")
                }
            }

            // Row 3
            HStack(spacing: 6) {
                if langCode == "en" {
                    // English: Shift + 7 letters + Delete
                    shiftButton
                    ForEach(0..<row3EnglishCount, id: \.self) { i in
                        keyButton(block[safe: row1Count + row2Count + i] ?? "")
                    }
                    deleteKeyInRow
                } else {
                    // Local languages: Left Arrow + Right Arrow + 5 letters + Delete
                    blockLeftArrow
                    blockRightArrow
                    ForEach(0..<row3LocalCount, id: \.self) { i in
                        keyButton(block[safe: row1Count + row2Count + i] ?? "")
                    }
                    deleteKeyInRow
                }
            }
        }
    }

    // MARK: - Block arrows (local langs only)
    private var blockLeftArrow: some View {
        Button {
            moveBlock(forward: false)
        } label: {
            Image(systemName: "arrow.left.circle")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 46, height: 48)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var blockRightArrow: some View {
        Button {
            moveBlock(forward: true)
        } label: {
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 46, height: 48)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func moveBlock(forward: Bool) {
        let flat = flattenLanguageKeys()
        let totalBlocks = max(1, Int(ceil(Double(flat.count) / Double(slotsPerBlock))))
        guard totalBlocks > 1 else { return }

        if forward {
            blockIndex = (blockIndex + 1) % totalBlocks
        } else {
            blockIndex = (blockIndex - 1 + totalBlocks) % totalBlocks
        }
    }

    // MARK: - Action Row
    private var actionRow: some View {
        HStack(spacing: 8) {

            Button("123") {
                isNumberMode = true
            }
            .frame(width: 56, height: 48)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)

            // SPACE key
            FastKey(label: "SPACE", textColor: .blue) {
                handleKey(" ")
            }

            Button("↵") {
                handleKey("\n")
            }
            .frame(width: 70, height: 48)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }

    // MARK: - Shift Button (English only)
    private var shiftButton: some View {
        Button(action: toggleShift) {
            Image(systemName: shiftIcon)
                .frame(width: 46, height: 48)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
        }
    }

    private var shiftIcon: String {
        if langCode == "en" {
            return capsLock ? "capslock.fill" : (shiftOn ? "shift.fill" : "shift")
        }
        return "shift"
    }

    // English shift only; local languages ignore shift
    private func toggleShift() {
        guard langCode == "en" else { return }

        if capsLock {
            capsLock = false
            shiftOn = false
        } else if shiftOn {
            capsLock = true
            shiftOn = false
        } else {
            shiftOn = true
        }
    }

    // MARK: - Delete key in row
    private var deleteKeyInRow: some View {
        Button(action: {
            // Single tap delete
            stopDeleting()
            handleKey("DEL")
        }) {
            Image(systemName: "delete.left")
                .frame(width: 56, height: 48)
                .background(Color(.systemGray5))
                .cornerRadius(8)
        }
        // Long press starts auto delete
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    startDeleting()
                }
        )
        // Stop auto delete when finger lifts
        .simultaneousGesture(
            DragGesture(minimumDistance: 1)
                .onEnded { _ in stopDeleting() }
        )
    }

    private func keyButton(_ char: String) -> some View {
        LetterKey(title: displayTitle(for: char), langCode: langCode) { out in
            handleKey(out)
        }
    }

    private func displayTitle(for text: String) -> String {
        if langCode == "en", (shiftOn || capsLock) {
            return text.uppercased()
        }
        return text
    }

    // MARK: - Insert/delete logic
    private func handleKey(_ s: String) {

        if s == "DEL" {
            deleteGrapheme()
        } else {
            insertAtCursor(s)
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func insertAtCursor(_ s: String) {

        let ns = text as NSString
        let total = ns.length

        let safeLoc = min(max(0, cursorUTF16Pos), total)
        let safeLen = min(max(0, selectionLengthUTF16), total - safeLoc)

        let range = NSRange(location: safeLoc, length: safeLen)

        let replacement = (langCode == "en" && (shiftOn || capsLock)) ? s.uppercased() : s

        text = ns.replacingCharacters(in: range, with: replacement)
        let newPos = safeLoc + replacement.utf16.count

        cursorUTF16Pos = newPos
        selectionLengthUTF16 = 0
    }

    // MARK: - Delete logic (with smart Indic behavior)
    private func deleteGrapheme() {

        let ns = text as NSString
        let total = ns.length

        // If there is a selection, delete the whole selection.
        if selectionLengthUTF16 > 0 {
            let loc = min(max(0, cursorUTF16Pos), total)
            let len = min(max(0, selectionLengthUTF16), total - loc)
            let range = NSRange(location: loc, length: len)

            text = ns.replacingCharacters(in: range, with: "")
            cursorUTF16Pos = range.location
            selectionLengthUTF16 = 0
            return
        }

        guard cursorUTF16Pos > 0, total > 0 else { return }

        // For Devanagari-family: smart delete (matra first, then base)
        if ["hi", "mr", "sa"].contains(langCode) {
            smartDeleteDevanagariCluster()
        } else {
            deleteWholeCharacter()
        }
    }

    /// Delete 1 whole Character (grapheme cluster) for non-Devanagari languages
    private func deleteWholeCharacter() {
        let ns = text as NSString
        let total = ns.length
        guard cursorUTF16Pos > 0, total > 0 else { return }

        let safeCursor = min(max(0, cursorUTF16Pos), total)
        let charRange = ns.rangeOfComposedCharacterSequence(at: safeCursor - 1)

        text = ns.replacingCharacters(in: charRange, with: "")
        cursorUTF16Pos = charRange.location
        selectionLengthUTF16 = 0
    }

    /// Smart delete for Hindi/Marathi/Sanskrit:
    /// If previous cluster ends with matra (ि,ा,ी,ू,ं,ँ,् etc.), delete matra first, then consonant.
    private func smartDeleteDevanagariCluster() {
        let ns = text as NSString
        let total = ns.length
        guard cursorUTF16Pos > 0, total > 0 else { return }

        let safeCursor = min(max(0, cursorUTF16Pos), total)
        let charRange = ns.rangeOfComposedCharacterSequence(at: safeCursor - 1)
        let clusterString = ns.substring(with: charRange)

        // Devanagari marks & matras (ं,ँ,ः,़,ा,ि,ी,ु,ू,ृ,ॄ,ॅ,ॆ,े,ै,ॉ,ॊ,ो,ौ,्)
        let devanagariMarks: Set<UnicodeScalar> = [
            "\u{0901}", // ◌ँ
            "\u{0902}", // ◌ं
            "\u{0903}", // ◌ः
            "\u{093C}", // ◌़
            "\u{093E}", // ◌ा
            "\u{093F}", // ◌ि
            "\u{0940}", // ◌ी
            "\u{0941}", // ◌ु
            "\u{0942}", // ◌ू
            "\u{0943}", // ◌ृ
            "\u{0944}", // ◌ॄ
            "\u{0945}", // ◌ॅ
            "\u{0946}", // ◌ॆ
            "\u{0947}", // ◌े
            "\u{0948}", // ◌ै
            "\u{0949}", // ◌ॉ
            "\u{094A}", // ◌ॊ
            "\u{094B}", // ◌ो
            "\u{094C}", // ◌ौ
            "\u{094D}"  // ◌् (halant)
        ]

        var scalars = Array(clusterString.unicodeScalars)

        if scalars.count > 1, let last = scalars.last, devanagariMarks.contains(last) {
            // Remove only the last mark (matra/halant/etc.)
            scalars.removeLast()
            let replacementCluster = String(String.UnicodeScalarView(scalars))

            let prefix = (text as NSString).substring(to: charRange.location)
            let suffix = (text as NSString).substring(from: charRange.location + charRange.length)
            let newText = prefix + replacementCluster + suffix

            text = newText
            let newPos = charRange.location + replacementCluster.utf16.count
            cursorUTF16Pos = newPos
            selectionLengthUTF16 = 0
        } else {
            // No matra at the end: delete whole consonant cluster
            text = ns.replacingCharacters(in: charRange, with: "")
            cursorUTF16Pos = charRange.location
            selectionLengthUTF16 = 0
        }
    }

    // MARK: - Flatten keys
    private func flattenLanguageKeys() -> [String] {
        if langCode == "en" {
            return ["q","w","e","r","t","y","u","i","o","p",
                    "a","s","d","f","g","h","j","k","l",
                    "z","x","c","v","b","n","m"]
        }

        var r: [String] = []
        let rows = keysForLang(langCode)   // from AllLanguageKeys.swift
        for row in rows {
            for key in row {
                r.append(key.main)
            }
        }
        return r
    }
}

// MARK: - Letter Key Popup
struct LetterKey: View {

    let title: String
    let langCode: String
    let action: (String) -> Void

    @State private var showPopup = false

    var body: some View {
        Group {
            if title.isEmpty {
                Spacer()
            } else {
                Button {
                    action(title)
                } label: {
                    Text(title)
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .onEnded { _ in
                            if !popupVariants.isEmpty {
                                showPopup = true
                            }
                        }
                )
                .popover(isPresented: $showPopup) {
                    VStack(spacing: 12) {
                        LazyVGrid(columns: popupColumns, spacing: 10) {
                            ForEach(popupVariants, id: \.self) { p in
                                Button {
                                    action(p)
                                    showPopup = false
                                } label: {
                                    Text(p)
                                        .font(.system(size: 22))
                                        .padding(10)
                                        .background(Color(.systemBackground))
                                        .cornerRadius(10)
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(width: 260)
                }
            }
        }
    }

    private var popupColumns: [GridItem] {
        popupVariants.count <= 4
            ? Array(repeating: GridItem(.flexible()), count: 2)
            : Array(repeating: GridItem(.flexible()), count: 3)
    }

    private var popupVariants: [String] {
        for row in keysForLang(langCode) {    // from AllLanguageKeys.swift
            if let match = row.first(where: { $0.main == title }) {
                return match.popup
            }
        }
        return []
    }
}

// MARK: - Symbol Pad
struct SymbolPad: View {
    let onKey: (String) -> Void
    let onABC: () -> Void

    var body: some View {
        VStack(spacing: 8) {

            ForEach(symbolKeys, id: \.self) { row in   // from AllLanguageKeys.swift
                HStack(spacing: 8) {
                    ForEach(row, id: \.main) { k in
                        Button(k.main) {
                            onKey(k.main)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }

            HStack {
                Button("ABC") { onABC() }
                    .frame(width: 80, height: 48)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)

                Spacer()

                Button {
                    onKey("DEL")
                } label: {
                    Image(systemName: "delete.left")
                        .frame(width: 80, height: 48)
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - Safe Access
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview (for your demo app)
struct IndicKeyboardEditor_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            IndicKeyboardEditor(text: .constant("नमस्ते दुनिया"), languageCode: "hi")
        }
    }
}
