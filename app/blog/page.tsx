import Link from "next/link";
import type { Metadata } from "next";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary, getLocale } from "@/lib/i18n";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Blog",
  description:
    "Inspiração, dicas e histórias para organizadores de eventos e donos de food trucks em Portugal.",
  alternates: { canonical: "/blog" },
};

export const revalidate = 120;

export default async function BlogPage() {
  type Post = {
    id: string; slug: string; title: string;
    excerpt: string | null; cover_url: string | null; published_at: string | null;
  };

  const dict = await getDictionary();
  const locale = await getLocale();
  const t = dict.blog;
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  const supa = await supabaseServer();
  const { data, error } = await (supa as any)
    .from("airfnb_blog_posts")
    .select("id, slug, title, excerpt, cover_url, published_at")
    .eq("status", "published")
    .order("published_at", { ascending: false })
    .limit(20);
  if (error) {
    console.error("blog list query failed", error.message);
  }
  const posts: Post[] = (data as Post[] | null) ?? [];

  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80 }}>
      <h1 className="section-title">{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>{t.subtitle}</p>

      {posts.length === 0 ? (
        <div className="dash empty" style={{ marginTop: 30 }}>{t.empty}</div>
      ) : (
        <div className="blog-grid" style={{ marginTop: 26 }}>
          {posts.map((p) => (
            <article key={p.id} className="blog-card">
              {p.cover_url && <div className="cover" style={{ backgroundImage: `url(${p.cover_url})` }} />}
              <div className="body">
                {p.published_at && (
                  <div className="date">
                    {new Date(p.published_at).toLocaleDateString(dateLocale, { day: "2-digit", month: "short", year: "numeric" })}
                  </div>
                )}
                <h3>{p.title}</h3>
                {p.excerpt && <p className="excerpt">{p.excerpt}</p>}
              </div>
            </article>
          ))}
        </div>
      )}

      <p style={{ marginTop: 40 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>{t.back_home}</Link>
      </p>
    </div>
  );
}
