import type { MetadataRoute } from "next";

const APP_URL = process.env.APP_URL ?? process.env.NEXT_PUBLIC_APP_URL ?? "https://airfnb.vercel.app";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Air F&B",
    short_name: "Air F&B",
    description: "Marketplace de Food Trucks para Eventos",
    start_url: "/",
    display: "standalone",
    background_color: "#FF6133",
    theme_color: "#FF4919",
    orientation: "portrait",
    lang: "pt-PT",
    scope: "/",
    id: APP_URL,
    icons: [
      {
        // 192/512 PNG variants would be ideal — the brand asset we have is the
        // single white-on-transparent PNG, used here for both small + large.
        // Install dialogs accept any image; iOS / Android will rescale.
        src: "/logo-airfb-white.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/logo-airfb-white.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/logo-airfb-black.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
    shortcuts: [
      {
        name: "Organizar evento",
        short_name: "Publicar",
        url: "/publicar",
        description: "Publica um pedido em 60s",
      },
      {
        name: "Encontrar trucks",
        short_name: "Catálogo",
        url: "/catalogo",
        description: "Explora food trucks certificados",
      },
    ],
  };
}
