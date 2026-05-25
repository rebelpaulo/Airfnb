"use client";
import { useState } from "react";
import { useDict } from "@/components/DictProvider";

export function CopyButton({ text }: { text: string }) {
  const dict = useDict();
  const t = dict.dashboard.shared_referral_copy;
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      className="btn-pill"
      style={{ padding: "10px 22px" }}
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(text);
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        } catch {
          // Fallback for browsers without clipboard API (e.g., http preview)
          window.prompt(t.fallback_prompt, text);
        }
      }}
    >
      {copied ? t.copied : t.copy}
    </button>
  );
}
