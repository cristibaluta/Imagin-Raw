# AI Agent Rules

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
