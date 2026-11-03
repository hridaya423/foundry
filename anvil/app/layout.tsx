import type { Metadata, Viewport } from "next";
import { color } from "./foundry/tokens";
import { Geist, Geist_Mono } from "next/font/google";
import { siteDescription, siteUrl } from "./site";
import Palette from "./foundry/palette";
import "./foundry/tokens.css";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: siteUrl,
  title: "Foundry · The app you never open.",
  description: siteDescription,
  alternates: { canonical: "/" },
  openGraph: { type: "website", siteName: "Foundry", title: "Foundry · The app you never open.", description: siteDescription },
  twitter: { card: "summary_large_image" },
};

export const viewport: Viewport = { themeColor: color.ink, colorScheme: "dark" };

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col"><a className="skip-link" href="#content">Skip to content</a>{children}<Palette /></body>
    </html>
  );
}
