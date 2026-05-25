"use client";

import { useState } from "react";
import { submitPartnerLead, type LeadKind } from "@/lib/partner-leads";
import { useDict } from "@/components/DictProvider";

export type FieldConfig =
  | { type: "text" | "tel" | "email" | "date" | "number"; name: string; label: string; required?: boolean; placeholder?: string; help?: string }
  | { type: "textarea"; name: string; label: string; required?: boolean; placeholder?: string; help?: string; rows?: number }
  | { type: "select"; name: string; label: string; required?: boolean; options: { value: string; label: string }[]; help?: string }
  | { type: "radio";  name: string; label: string; required?: boolean; options: { value: string; label: string }[]; help?: string }
  | { type: "checkboxes"; name: string; label: string; options: { value: string; label: string }[]; help?: string };

type Props = {
  kind: LeadKind;
  /** Free-text intro shown above the form fields. */
  intro?: string;
  /** Service-specific fields (always-shown name/email/phone are added automatically). */
  fields: FieldConfig[];
  /** CTA button text. */
  cta: string;
};

export function PartnerLeadForm({ kind, intro, fields, cta }: Props) {
  const dict = useDict();
  const t = dict.forms.partner_lead;
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setErr(null);
    setBusy(true);
    try {
      const fd = new FormData(e.currentTarget);
      const res = await submitPartnerLead(kind, fd);
      if (!res.ok) {
        setErr(res.error);
        setBusy(false);
        return;
      }
      setDone(true);
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : String(e2));
      setBusy(false);
    }
  }

  if (done) {
    return (
      <div style={{
        marginTop: 18, padding: 20, background: "#F1FBF5",
        border: "1px solid #C5EBD3", borderRadius: 12, color: "#0F7B4F",
      }}>
        <strong>{t.sent_ok}</strong> {t.sent_body}
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} style={{
      marginTop: 18, padding: 22, background: "#fff",
      border: "1px solid var(--line)", borderRadius: 14,
      display: "grid", gap: 14,
    }}>
      {intro && <p style={{ margin: 0, color: "var(--muted)" }}>{intro}</p>}

      {/* Honeypot — invisible to humans, irresistible to bots. */}
      <input
        type="text" name="website" tabIndex={-1} autoComplete="off"
        aria-hidden="true"
        style={{ position: "absolute", left: "-9999px", width: 1, height: 1, opacity: 0 }}
      />

      {/* Service-specific fields */}
      {fields.map((f) => <Field key={f.name} f={f} selectPlaceholder={t.select_option} />)}

      {/* Always-shown contact block */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
        <label style={{ display: "grid", gap: 6 }}>
          <span style={{ fontSize: 13, fontWeight: 600 }}>{t.name_label}</span>
          <input name="name" type="text" required autoComplete="name" />
        </label>
        <label style={{ display: "grid", gap: 6 }}>
          <span style={{ fontSize: 13, fontWeight: 600 }}>{t.email_label}</span>
          <input name="email" type="email" required autoComplete="email" />
        </label>
      </div>
      <label style={{ display: "grid", gap: 6 }}>
        <span style={{ fontSize: 13, fontWeight: 600 }}>{t.phone_label}</span>
        <input name="phone" type="tel" autoComplete="tel" placeholder={t.phone_placeholder} />
      </label>

      {err && (
        <div style={{
          padding: 12, background: "#FFE5E0", color: "#8B1100",
          borderRadius: 10, fontSize: 14,
        }}>
          {err}
        </div>
      )}

      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <button type="submit" className="btn-pill" disabled={busy}
                style={{ opacity: busy ? 0.65 : 1 }}>
          {busy ? t.sending : cta}
        </button>
      </div>
    </form>
  );
}

function Field({ f, selectPlaceholder }: { f: FieldConfig; selectPlaceholder: string }) {
  if (f.type === "textarea") {
    return (
      <label style={{ display: "grid", gap: 6 }}>
        <span style={{ fontSize: 13, fontWeight: 600 }}>
          {f.label}{f.required ? " *" : ""}
        </span>
        <textarea name={f.name} required={f.required} rows={f.rows ?? 3} placeholder={f.placeholder} />
        {f.help && <small style={{ color: "var(--muted)", fontSize: 12 }}>{f.help}</small>}
      </label>
    );
  }
  if (f.type === "select") {
    return (
      <label style={{ display: "grid", gap: 6 }}>
        <span style={{ fontSize: 13, fontWeight: 600 }}>
          {f.label}{f.required ? " *" : ""}
        </span>
        <select name={f.name} required={f.required} defaultValue="">
          <option value="" disabled>{selectPlaceholder}</option>
          {f.options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
        {f.help && <small style={{ color: "var(--muted)", fontSize: 12 }}>{f.help}</small>}
      </label>
    );
  }
  if (f.type === "radio") {
    return (
      <fieldset style={{ display: "grid", gap: 8, border: "none", padding: 0, margin: 0 }}>
        <legend style={{ fontSize: 13, fontWeight: 600, padding: 0 }}>
          {f.label}{f.required ? " *" : ""}
        </legend>
        <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
          {f.options.map((o) => (
            <label key={o.value} style={{ display: "inline-flex", alignItems: "center", gap: 6, fontSize: 14 }}>
              <input type="radio" name={f.name} value={o.value} required={f.required} />
              {o.label}
            </label>
          ))}
        </div>
        {f.help && <small style={{ color: "var(--muted)", fontSize: 12 }}>{f.help}</small>}
      </fieldset>
    );
  }
  if (f.type === "checkboxes") {
    return (
      <fieldset style={{ display: "grid", gap: 8, border: "none", padding: 0, margin: 0 }}>
        <legend style={{ fontSize: 13, fontWeight: 600, padding: 0 }}>{f.label}</legend>
        <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
          {f.options.map((o) => (
            <label key={o.value} style={{ display: "inline-flex", alignItems: "center", gap: 6, fontSize: 14 }}>
              <input type="checkbox" name={f.name} value={o.value} />
              {o.label}
            </label>
          ))}
        </div>
        {f.help && <small style={{ color: "var(--muted)", fontSize: 12 }}>{f.help}</small>}
      </fieldset>
    );
  }
  return (
    <label style={{ display: "grid", gap: 6 }}>
      <span style={{ fontSize: 13, fontWeight: 600 }}>
        {f.label}{f.required ? " *" : ""}
      </span>
      <input
        name={f.name} type={f.type} required={f.required}
        placeholder={f.placeholder}
        {...(f.type === "number" ? { min: 0 } : {})}
      />
      {f.help && <small style={{ color: "var(--muted)", fontSize: 12 }}>{f.help}</small>}
    </label>
  );
}
