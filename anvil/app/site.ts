export const siteUrl = new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "https://foundry.hridya.tech");
export const siteTitle = "Foundry: a free native macOS launcher for apps and files";
export const siteDescription = "Foundry is a free, open-source launcher for macOS 14 or later. Open apps, search files and your clipboard history, and run commands from one panel.";
export const authorName = "Hridya Agrawal";
export const hubUrl = "https://www.hridya.tech";
export const caseStudyUrl = `${hubUrl}/projects/foundry`;
export const siteLastModified = "2026-11-03";
export const foundryDownloadUrl = "https://github.com/hridaya423/foundry/releases/latest/download/Foundry.dmg";
export const foundryVersion = process.env.FOUNDRY_VERSION;
export const repoUrl = "https://github.com/hridaya423/foundry";
export const sitePages = ["/", "/methodology", "/proof", "/changelog", "/privacy", "/brand"];
export const footerLinks = [
  { href: "/changelog", label: "Changelog" },
  { href: "/privacy", label: "Privacy" },
  { href: "/brand", label: "Brand" },
  { href: repoUrl, label: "GitHub" },
];
