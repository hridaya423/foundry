const productionHost = process.env.VERCEL_PROJECT_PRODUCTION_URL;

export const siteUrl = new URL(process.env.NEXT_PUBLIC_SITE_URL ?? (productionHost ? `https://${productionHost}` : "http://localhost:3000"));
export const siteDescription = "Launch apps, find what you copied, transform files, run commands. One native launcher for macOS.";
export const foundryDownloadUrl = "https://github.com/hridaya423/foundry/releases/latest/download/Foundry.dmg";
