# AI Agent Rules

## Always read files before editing

**Before editing any file, always read its current content first using the read_file tool — even if the file was already seen earlier in the conversation.**

The user may have made manual edits in Xcode since the last time the file was read. Editing based on a stale version will silently overwrite those changes. There are no exceptions to this rule — always read, then edit.

## Code Style

### No single-line blocks — ever

All blocks must use braces on separate lines, no matter how short the body is.
This applies to **every** control flow construct: `if`, `else`, `guard`, `for`, `while`, `switch`, closures, and dispatch calls like `DispatchQueue.main.async`.

**Wrong:**
```swift
if condition { doSomething() }

guard let x = y else { return }

for item in items { process(item) }

completion { result in handle(result) }

DispatchQueue.main.async { completion(nil) }
```

**Correct:**
```swift
if condition {
    doSomething()
}

guard let x = y else {
    return
}

for item in items {
    process(item)
}

completion { result in
    handle(result)
}

DispatchQueue.main.async {
    completion(nil)
}
```

This rule has no exceptions — not for `guard`, not for one-liners, not for early returns, not for `DispatchQueue` calls.

---

### Multi-line function/struct call indentation

When a function or struct call doesn't fit on one line, align continuation lines with the first argument — **never use a hanging-indent style where arguments are indented with extra spaces from the call site**.

**Wrong:**
```swift
CGRect(
    x: w - stackW - 4,
    y: h - stackH,
    width: stackW,
    height: stackH
)
```

**Correct — single line when it fits:**
```swift
CGRect(x: w - stackW - 4, y: h - stackH, width: stackW, height: stackH)
```

**Correct — Xcode-style alignment when the line is too long:**
```swift
CGRect(x: imageRect.midX - iconSize / 2,
       y: imageRect.midY - iconSize / 2,
       width: iconSize,
       height: iconSize)
```

Prefer a single line. Only wrap when the line would exceed ~120 characters, and in that case align all subsequent arguments with the first one.

---

### Switch case indentation

`case` labels must be indented one level inside the `switch` — never at the same indentation as the `switch` keyword.

**Wrong:**
```swift
switch value {
case .a:
    doA()
case .b:
    doB()
}
```

**Correct:**
```swift
switch value {
    case .a:
        doA()
    case .b:
        doB()
}
```

This applies to all `switch` statements including `switch key`, `switch event.keyCode`, `switch label`, etc.

---

### Empty line after super call in overrides

When overriding a function and calling `super`, always leave one empty line after the `super` call before the rest of the body.

**Wrong:**
```swift
override func viewDidLoad() {
    super.viewDidLoad()
    setupViews()
}

override func prepareForReuse() {
    super.prepareForReuse()
    currentPath = nil
}
```

**Correct:**
```swift
override func viewDidLoad() {
    super.viewDidLoad()

    setupViews()
}

override func prepareForReuse() {
    super.prepareForReuse()

    currentPath = nil
}
```
