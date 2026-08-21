/**
 * Serialize JSON-LD for embedding inside an HTML script element.
 *
 * Escaping the opening angle bracket prevents attacker-controlled strings from
 * terminating the script element. Escaping JavaScript line separators keeps
 * the payload safe for parsers that still interpret them as source boundaries.
 * JSON.parse reverses every escape without changing the structured data.
 *
 * @param {unknown} value
 * @returns {string}
 */
export function serializeJsonLd(value) {
  return JSON.stringify(value)
    .replace(/</g, "\\u003c")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}
