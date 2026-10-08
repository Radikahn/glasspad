// Offscreen editor tests: drives VimTextView with real key events and writes
// snapshots of a few states. Run with `just test`.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().path
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for f in ["Regular", "Bold", "Italic", "BoldItalic"] {
    let url = URL(fileURLWithPath: "\(root)/Glasspad/Resources/Fonts/JetBrainsMono-\(f).ttf")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(contentRect: NSRect(x: -3000, y: 200, width: 460, height: 560),
                      styleMask: [.titled], backing: .buffered, defer: false)
let (scroll, tv) = VimTextView.makeScrollable()
scroll.frame = window.contentView!.bounds
scroll.autoresizingMask = [.width, .height]
window.contentView!.addSubview(scroll)
window.orderFrontRegardless()
window.makeKey()
let status = EditorStatus()
tv.status = status
// Keep the tests off the real clipboard.
tv.pasteboard = NSPasteboard(name: NSPasteboard.Name("com.radikahn.glasspad.tests"))

func pump(_ t: TimeInterval = 0.05) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print((cond ? "  ok   " : "  FAIL ") + msg)
    if !cond { failures += 1 }
}

func key(_ chars: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: chars,
                             charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    tv.keyDown(with: e)
}
func keys(_ s: String) { for ch in s { key(String(ch)) } }
func esc() { key("\u{1b}", code: 53) }
func ret() { key("\r", code: 36) }
func bs() { key("\u{7f}", code: 51) }

func lineAtCursor() -> String {
    let ns = tv.string as NSString
    let r = ns.lineRange(for: NSRange(location: min(tv.cursor, ns.length), length: 0))
    return ns.substring(with: r).trimmingCharacters(in: .newlines)
}
func charAtCursor() -> String {
    let ns = tv.string as NSString
    return tv.cursor < ns.length ? ns.substring(with: NSRange(location: tv.cursor, length: 1)) : "<eof>"
}

func snapshot(_ name: String) {
    let rect = tv.visibleRect
    guard let rep = tv.bitmapImageRepForCachingDisplay(in: rect) else { return }
    tv.cacheDisplay(in: rect, to: rep)
    let image = NSImage(size: rect.size)
    image.lockFocus()
    NSColor(srgbRed: 0.22, green: 0.18, blue: 0.28, alpha: 1).setFill()
    NSRect(origin: .zero, size: rect.size).fill()
    rep.draw(in: NSRect(origin: .zero, size: rect.size))
    image.unlockFocus()
    let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

let sample = """
# Welcome to Glasspad

A quiet place to write. Everything is **markdown**, rendered *live* as you type.

## Vim keys
- `i` `a` `o` enter insert mode
- `/` searches, `n` and `N` cycle

```swift
struct Thought {
    let text: String  // note
}
```

> Write what you see.

- [ ] write something today
- [x] open Glasspad
"""

tv.load(text: sample, insertMode: false)
window.makeFirstResponder(tv)
pump(0.2)

print("== load")
check(tv.mode == .normal, "starts in normal mode")
check(tv.cursor == 0, "cursor at 0")
snapshot("01-load")

print("== hjkl")
keys("j")
check(lineAtCursor() == "", "j onto blank line (got '\(lineAtCursor())')")
keys("j")
check(lineAtCursor().hasPrefix("A quiet"), "j onto paragraph")
keys("llll")
check(tv.cursor - (tv.string as NSString).range(of: "A quiet").location == 4, "llll moves 4")
keys("h")
check(charAtCursor() == "u", "h moves back (char '\(charAtCursor())')")
keys("$")
check(charAtCursor() == "." , "$ to last char (got '\(charAtCursor())')")
keys("0")
check(charAtCursor() == "A", "0 to line start")
keys("w")
check(charAtCursor() == "q", "w to next word (got '\(charAtCursor())')")
keys("e")
check(charAtCursor() == "t", "e to word end (got '\(charAtCursor())')")
keys("b")
check(charAtCursor() == "q", "b back to word start")
keys("k")
check(lineAtCursor() == "", "k up")
keys("gg")
check(tv.cursor == 0, "gg to top")
keys("G")
check(lineAtCursor() == "- [x] open Glasspad", "G to last line (got '\(lineAtCursor())')")
keys("gg")
pump(0.4)

print("== search")
keys("/")
check(tv.mode == .search, "/ enters search")
keys("glass")
check(status.matchCount == 2, "incremental matches (\(status.matchCount))")
snapshot("02-search-typing")
ret()
check(tv.mode == .normal, "enter returns to normal")
check(charAtCursor() == "G", "cursor on first match after origin (got '\(charAtCursor())')")
let first = tv.cursor
keys("n")
check(tv.cursor != first, "n moves to next match")
keys("n")
check(tv.cursor == first, "n wraps")
keys("N")
check(tv.cursor != first, "N goes back")
esc()
check(status.matchCount == 0, "esc clears highlight")
keys("/"); keys("zzzz"); esc()
check(tv.cursor != 0 && tv.mode == .normal, "esc restores origin")

print("== insert")
keys("gg")
keys("jj")
keys("i")
check(tv.mode == .insert, "i enters insert")
keys("Hey. ")
check(lineAtCursor().hasPrefix("Hey. A quiet"), "typed text inserted (got '\(lineAtCursor())')")
snapshot("03-insert")
esc()
check(tv.mode == .normal, "esc to normal")
check(charAtCursor() == " ", "esc steps back one (got '\(charAtCursor())')")
keys("u")
check(lineAtCursor().hasPrefix("A quiet"), "u undoes insert (got '\(lineAtCursor())')")
key("r", flags: .control)
check(lineAtCursor().hasPrefix("Hey. A quiet"), "ctrl-r redoes")
keys("u")

print("== edits")
keys("x")
check(lineAtCursor().hasPrefix(" quiet"), "x deletes char (got '\(lineAtCursor())')")
keys("u")
let before = tv.string
keys("dd")
check(!tv.string.contains("A quiet"), "dd deletes line")
keys("u")
check(tv.string == before, "u restores line")
keys("A")
check(tv.mode == .insert && charAtCursor() == "\n", "A appends at line end")
esc()
keys("o")
check(tv.mode == .insert && lineAtCursor() == "", "o opens line below")
keys("- first")
ret()
check(lineAtCursor() == "- ", "list continues (got '\(lineAtCursor())')")
keys("second")
ret()
ret()
check(lineAtCursor() == "", "enter on empty item ends list (got '\(lineAtCursor())')")
keys("1. one")
ret()
check(lineAtCursor() == "2. ", "ordered list increments (got '\(lineAtCursor())')")
bs(); bs(); bs()
keys("```py")
ret()
let ns = tv.string as NSString
let fenceLoc = ns.range(of: "```py").location
check(ns.substring(from: fenceLoc).hasPrefix("```py\n\n```"), "fence auto-closes")
keys("def f(x):")
ret()
keys("return 1")
esc()
pump(0.3)
snapshot("04-edits")

print("== language pill")
if let block = tv.codeBlocks.first(where: { $0.language == "py" }) {
    tv.setLanguage("rust", forBlockAt: block.range.location)
    check(tv.string.contains("```rust\ndef f(x):"), "language replaced")
    keys("u")
    check(tv.string.contains("```py\ndef f(x):"), "language change undoable")
} else {
    check(false, "py block found")
}
check(tv.codeBlocks.count == 2, "two code blocks (\(tv.codeBlocks.count))")

let lines = "alpha beta gamma\nsecond line\nthird line\n"
func reset(_ text: String = lines) {
    tv.load(text: text, insertMode: false)
    pump(0.05)
}

print("== visual: charwise")
reset()
keys("v")
check(tv.mode == .visual && status.mode == .visual, "v enters visual")
keys("e")
check(tv.selectedRange() == NSRange(location: 0, length: 5), "v e selects the word (\(tv.selectedRange()))")
keys("y")
check(tv.mode == .normal && tv.cursor == 0 && tv.selectedRange().length == 0, "y yanks, returns to start")
check(tv.pasteboard.string(forType: .string) == "alpha", "yank lands on the clipboard")
keys("$p")
check(lineAtCursor() == "alpha beta gammaalpha", "p pastes after the cursor (got '\(lineAtCursor())')")
check(tv.cursor == 20, "cursor ends on last pasted char (\(tv.cursor))")
reset()
keys("P")
check(lineAtCursor() == "alphaalpha beta gamma", "P pastes before the cursor (got '\(lineAtCursor())')")
reset()
keys("wve")
keys("d")
check(lineAtCursor() == "alpha  gamma" && tv.mode == .normal, "v d deletes the selection (got '\(lineAtCursor())')")
check(tv.pasteboard.string(forType: .string) == "beta", "deleted text is yanked")
keys("u")
check(lineAtCursor() == "alpha beta gamma", "u restores it")
reset()
keys("wvllo")
check(tv.cursor == 6, "o swaps to the other end (\(tv.cursor))")
keys("h")
check(tv.selectedRange() == NSRange(location: 5, length: 4), "head moves from the new end (\(tv.selectedRange()))")
esc()
check(tv.mode == .normal && tv.selectedRange().length == 0, "esc leaves visual")
reset()
keys("vec")
check(tv.mode == .insert && lineAtCursor() == " beta gamma", "c deletes and enters insert (got '\(lineAtCursor())')")
keys("omega")
esc()
check(lineAtCursor() == "omega beta gamma", "typing replaces the selection")
reset()
keys("vey")
keys("wve")
keys("p")
check(lineAtCursor() == "alpha alpha gamma", "p over a selection replaces it (got '\(lineAtCursor())')")
keys("w")
keys("vep")
check(lineAtCursor() == "alpha alpha alpha", "register survives a visual put (got '\(lineAtCursor())')")
reset()
keys("v")
keys("v")
check(tv.mode == .normal, "v again exits")
keys("vjd")
check(tv.string == "econd line\nthird line\n", "v across lines deletes through the head (got \(tv.string.debugDescription))")

print("== visual: linewise")
reset()
keys("Vj")
check(tv.mode == .visualLine && status.mode == .visualLine, "V enters V-LINE")
check(tv.selectedRange() == NSRange(location: 0, length: 29), "Vj selects two whole lines (\(tv.selectedRange()))")
keys("d")
check(tv.string == "third line\n", "V d deletes the lines (got \(tv.string.debugDescription))")
keys("p")
check(tv.string == "third line\nalpha beta gamma\nsecond line\n", "linewise p puts below (got \(tv.string.debugDescription))")
check(lineAtCursor() == "alpha beta gamma", "cursor on first put line")
keys("ggP")
check(tv.string.hasPrefix("alpha beta gamma\nsecond line\nthird line\n"), "linewise P puts above")
reset("one\ntwo")
keys("jVy")
keys("p")
check(tv.string == "one\ntwo\ntwo", "linewise p after a last line with no newline (got \(tv.string.debugDescription))")
reset("one\ntwo")
keys("jVd")
check(tv.string == "one", "V d on the last line removes its newline (got \(tv.string.debugDescription))")
reset()
keys("Vjv")
check(tv.mode == .visual, "v switches V-LINE to charwise")

print("== yank & put in normal mode")
reset()
keys("yyp")
check(tv.string.hasPrefix("alpha beta gamma\nalpha beta gamma\nsecond"), "yy p duplicates the line")
check(tv.cursor == 17, "cursor on the pasted line (\(tv.cursor))")
reset()
keys("2yyGp")
check(tv.string.hasSuffix("third line\nalpha beta gamma\nsecond line\n"), "2yy yanks two lines (got \(tv.string.debugDescription))")
reset()
keys("ddp")
check(tv.string == "second line\nalpha beta gamma\nthird line\n", "dd p swaps lines (got \(tv.string.debugDescription))")
reset()
keys("xp")
check(tv.string.hasPrefix("lapha"), "x p swaps characters (got \(tv.string.prefix(6).debugDescription))")
reset()
keys("Y3p")
check(tv.string.components(separatedBy: "alpha beta gamma").count == 5, "counts repeat a put")
reset()
tv.pasteboard.clearContents()
tv.pasteboard.setString("EXT", forType: .string)
keys("P")
check(lineAtCursor().hasPrefix("EXTalpha"), "p uses text copied outside the app")
reset()
tv.selectAll(nil)
check(tv.mode == .visual && tv.selectedRange().length == (lines as NSString).length, "⌘A becomes a visual selection")
keys("d")
check(tv.string.isEmpty, "…which d deletes")
keys("u")
check(tv.string == lines, "u restores everything")

print("== code fences")
let fenceText = "Intro\n\n```swift\nlet x = 1\n```\n\nAfter"
reset(fenceText)
let fenceStart = (tv.string as NSString).range(of: "```swift").location
func fenceHidden() -> Bool { tv.textStorage!.attribute(.gpHidden, at: fenceStart, effectiveRange: nil) != nil }
check(fenceHidden(), "fence hidden while the cursor is elsewhere")
tv.setCursor((tv.string as NSString).range(of: "x = 1").location)
check(fenceHidden(), "fence stays hidden while editing inside the block")
tv.setCursor(fenceStart)
check(!fenceHidden(), "fence revealed with the cursor on its line")
pump(0.3)
snapshot("09-fence-revealed")

print("== smear")
keys("gg")
pump(0.5)
keys("G")
pump(0.03)
snapshot("05-smear-mid")
pump(0.6)
snapshot("06-smear-done")

print("== empty doc")
tv.load(text: "", insertMode: true)
pump(0.1)
check(tv.mode == .insert, "blank entry opens in insert mode")
snapshot("07-empty")
keys("# Title")
ret()
keys("Body")
esc()
check(tv.string == "# Title\nBody", "typing in empty doc (got \(tv.string.debugDescription))")
keys("k")
check(lineAtCursor() == "# Title", "k into heading")
pump(0.3)
snapshot("08-heading")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
print("snapshots: \(out)")
exit(failures == 0 ? 0 : 1)
