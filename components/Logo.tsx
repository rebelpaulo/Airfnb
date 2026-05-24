/**
 * Brand wordmark. Use `variant="black"` only when the surface is white;
 * everything else (orange hero, dark teal sections, scrolled orange header)
 * should keep the default `variant="white"`.
 */
type Props = {
  variant?: "white" | "black";
  height?: number | string;
  className?: string;
  alt?: string;
};

export function Logo({ variant = "white", height = 36, className, alt = "Air F&B" }: Props) {
  const src = variant === "black" ? "/logo-airfb-black.png" : "/logo-airfb-white.png";
  return (
    <img
      src={src}
      alt={alt}
      className={className}
      style={{ height, width: "auto", display: "block" }}
    />
  );
}
