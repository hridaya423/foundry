const productionHost = process.env.VERCEL_PROJECT_PRODUCTION_URL;

export const siteUrl = new URL(process.env.NEXT_PUBLIC_SITE_URL ?? (productionHost ? `https://${productionHost}` : "http://localhost:3000"));
export const siteDescription = "Launch apps, find what you copied, transform files, run commands. One native launcher for macOS.";
export const foundryDownloadUrl = "https://github.com/hridaya423/foundry/releases/latest/download/Foundry.dmg";
export const foundryVersion = process.env.FOUNDRY_VERSION;
export const repoUrl = "https://github.com/hridaya423/foundry";
export const sitePages = ["/", "/methodology", "/proof", "/changelog", "/privacy", "/brand"];
export const footerLinks = [
  { href: "/proof", label: "Proof" },
  { href: "/changelog", label: "Changelog" },
  { href: "/privacy", label: "Privacy" },
  { href: "/brand", label: "Brand" },
  { href: `${repoUrl}/blob/main/LICENSE`, label: "MIT licence" },
  { href: repoUrl, label: "GitHub" },
];
