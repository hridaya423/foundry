export const siteUrl = new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "https://foundry.hridya.tech");
export const siteTitle = "Foundry: free Raycast & Spotlight alternative for Apple silicon";
export const siteDescription = "Foundry is a free, open-source Raycast and Spotlight alternative for Apple silicon Macs on macOS 14 or later. Open apps, files and your clipboard in one bar.";
export const authorName = "Hridya Agrawal";
export const hubUrl = "https://www.hridya.tech";
export const caseStudyUrl = `${hubUrl}/projects/foundry`;
export const foundryDownloadUrl = "https://github.com/hridaya423/foundry/releases/latest/download/Foundry.dmg";
export const foundryVersion = process.env.FOUNDRY_VERSION;
export const repoUrl = "https://github.com/hridaya423/foundry";
export const sitePages = ["/", "/methodology", "/proof", "/faq", "/changelog", "/privacy", "/brand"] as const;
export const footerLinks = [
  { href: "/faq", label: "FAQ" },
  { href: "/changelog", label: "Changelog" },
  { href: "/privacy", label: "Privacy" },
  { href: "/brand", label: "Brand" },
  { href: repoUrl, label: "GitHub" },
];
