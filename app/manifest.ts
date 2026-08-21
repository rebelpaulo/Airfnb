import type { MetadataRoute } from "next";
import { resolveAppOrigin } from "@/lib/app-url.mjs";

const APP_URL = resolveAppOrigin();

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "F&B Tailor",
    short_name: "F&B Tailor",
    description: "Food Trucks, Catering e Bares para Eventos",
    start_url: "/",
    display: "standalone",
    background_color: "#FF6133",
    theme_color: "#FF4919",
    orientation: "portrait",
    lang: "pt-PT",
    scope: "/",
    id: `${APP_URL}/`,
    // Dedicated square/maskable icons are still required. The approved
    // wide wordmarks must not be advertised as square PWA assets.
    shortcuts: [
      {
        name: "Organizar evento",
        short_name: "Publicar",
        url: "/publicar",
        description: "Publica um pedido em 60s",
      },
      {
        name: "Encontrar fornecedores",
        short_name: "Catálogo",
        url: "/catalogo",
        description: "Explora Food Trucks, Catering e Bares",
      },
    ],
  };
}
