---
name: gtm-javascript
description: Generate ES5-compliant JavaScript for Google Tag Manager Custom HTML tags. Use when writing GTM tags, dataLayer code, or analytics implementations.
---

# GTM JavaScript Coding Standards

This skill ensures all JavaScript code generated for Google Tag Manager (GTM) Custom HTML tags is **ES5-compliant** and follows current best practices (2024-2025).

## Critical Constraint: ES5 Only

GTM's JavaScript compiler operates in **ES5 (ECMAScript 5) mode by default**. ES6+ syntax causes compilation errors and prevents tag publishing.

### Prohibited ES6+ Features

**NEVER use these in GTM Custom HTML tags:**

| Feature | ES6+ (Prohibited) | ES5 (Required) |
|---------|-------------------|----------------|
| Variables | `const`, `let` | `var` |
| Functions | `() => {}` | `function() {}` |
| Strings | `` `${var}` `` | `'str' + var` |
| Destructuring | `{a, b} = obj` | `var a = obj.a` |
| Spread | `[...arr]` | `arr.concat()` |
| Default params | `fn(x = 1)` | `x = x \|\| 1` |
| for-of | `for (x of arr)` | `for (var i...)` |
| Classes | `class Foo {}` | `function Foo(){}` |
| Block functions | `if(x){function f(){}}` | `if(x){var f=function(){}}` |

## 2024-2025 Updates

### Breaking Changes
- **IE11 Support Ended** (July 15, 2024): No longer tested or fixed
- **Consent Mode v2 Required** (March 2024): New parameters `ad_user_data` and `ad_personalization`
- **Google Ads Auto-Tag** (April 10, 2025): Containers with Google Ads tags auto-load Google tag first

### New Features
- Tag Diagnostics tool for issue detection
- `gtagSet` API for configuration settings
- `readAnalyticsStorage` sandbox API for custom templates
- Server-side GTM can load scripts via 1st-party domain

## Code Patterns

### IIFE Pattern (Recommended)
```javascript
(function() {
  'use strict';

  window.dataLayer = window.dataLayer || [];
  window.dataLayer.push({
    event: 'my_event',
    my_parameter: 'value'
  });
})();
```

### Error Handling
```javascript
(function() {
  'use strict';
  try {
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push({event: 'tracked_event'});
  } catch (e) {
    // Silent fail - do not break page
  }
})();
```

### Array Iteration (ES5)
```javascript
function forEach(arr, callback) {
  for (var i = 0; i < arr.length; i++) {
    callback(arr[i], i);
  }
}
```

## Consent Mode v2

When implementing consent, use these parameters:

```javascript
window.dataLayer = window.dataLayer || [];
function gtag() { dataLayer.push(arguments); }

// Default state (before consent)
gtag('consent', 'default', {
  ad_storage: 'denied',
  ad_user_data: 'denied',
  ad_personalization: 'denied',
  analytics_storage: 'denied'
});

// After user grants consent
gtag('consent', 'update', {
  ad_storage: 'granted',
  ad_user_data: 'granted',
  ad_personalization: 'granted',
  analytics_storage: 'granted'
});
```

## GA4 Ecommerce Events

Use the standard event names and items array structure:

```javascript
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({
  event: 'purchase',
  ecommerce: {
    transaction_id: 'T12345',
    value: 99.99,
    currency: 'USD',
    items: [{
      item_id: 'SKU123',
      item_name: 'Product Name',
      price: 99.99,
      quantity: 1
    }]
  }
});
```

## Validation Checklist

Before publishing any GTM tag:

1. No `const`/`let` - use `var` only
2. No arrow functions - use `function()` syntax
3. No template literals - use string concatenation
4. No destructuring - access properties individually
5. No for-of loops - use traditional for loops
6. No block-scoped function declarations
7. Test in GTM Preview Mode
8. Verify in GA4 DebugView (if applicable)
9. Check browser console for errors

## GTM MCP Server (API Access)

When you need to create, update, or manage GTM container entities programmatically (not just write Custom HTML JavaScript), use the **GTM MCP server** (`gtm` in mcp-templates). It provides 99 tools for full CRUD on tags, triggers, variables, built-in variables, versions, environments, user permissions, clients (sGTM), transformations, zones, Google tag config, and more via the GTM API v2. Enable it with `~/.claude/mcp-restart gtm`. Runs locally via stdio (pouyanafisi/gtm-mcp); no data goes through third parties.

**Known limitation:** `autoEventFilter` on click/form triggers is silently dropped by Google's API. Set those conditions in the GTM web UI instead.

## Playwright dataLayer Testing Pattern

When verifying GTM tags fire correctly in a browser, use this pattern to capture dataLayer events:

```javascript
// Monkey-patch dataLayer.push to intercept all events
var events = [];
await page.evaluate(function() {
  window.dataLayer = window.dataLayer || [];
  var origPush = window.dataLayer.push.bind(window.dataLayer);
  window.dataLayer.push = function() {
    origPush.apply(window.dataLayer, arguments);
    window.__capturedDL = window.__capturedDL || [];
    window.__capturedDL.push(arguments[0]);
  };
});

// Navigate/interact, then retrieve captured events
var captured = await page.evaluate(function() { return window.__capturedDL; });
```

## Resources

- [GTM Developer Guide](https://developers.google.com/tag-manager)
- [GA4 Ecommerce](https://developers.google.com/analytics/devguides/collection/ga4/ecommerce)
- [Consent Mode](https://developers.google.com/tag-platform/security/guides/consent)
- [Sandboxed JavaScript APIs](https://developers.google.com/tag-platform/tag-manager/templates/sandboxed-javascript)

## When to Use Custom Templates Instead

Consider using **Custom Templates** (not Custom HTML) when:
- Building reusable tag logic
- Need sandboxed security
- Want permission-based access control
- Sharing with organization

Custom Templates support some ES6 features and provide better security through the sandboxed JavaScript environment.
