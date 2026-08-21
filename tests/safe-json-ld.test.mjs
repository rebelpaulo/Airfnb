import assert from "node:assert/strict";
import test from "node:test";

import { serializeJsonLd } from "../lib/safe-json-ld.mjs";

test("escapes HTML script breakouts and JavaScript line separators", () => {
  const payload = {
    name: "Evil </script><script>alert(1)</script>",
    description: "before\u2028between\u2029after",
    nested: ["</ScRiPt>", { text: "<!-- markup" }],
  };

  const serialized = serializeJsonLd(payload);

  assert.equal(serialized.includes("</script>"), false);
  assert.equal(serialized.toLowerCase().includes("</script>"), false);
  assert.equal(serialized.includes("\u2028"), false);
  assert.equal(serialized.includes("\u2029"), false);
  assert.deepEqual(JSON.parse(serialized), payload);
});

test("preserves legitimate JSON-LD values and JSON.stringify semantics", () => {
  const payload = {
    "@context": "https://schema.org",
    "@type": "Restaurant",
    name: "F&B Tailor — Sabores < 5€",
    aggregateRating: { ratingValue: "4.8", reviewCount: 12 },
    optional: undefined,
  };

  const serialized = serializeJsonLd(payload);

  assert.deepEqual(JSON.parse(serialized), JSON.parse(JSON.stringify(payload)));
});
