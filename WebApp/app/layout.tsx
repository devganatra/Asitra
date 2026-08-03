import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";
import { ASITRA_RELEASE } from "./release";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const title = "Asitra — Your everyday assistant";
const description =
  "Capture your day, organize commitments, follow personal progress, understand money, and protect your balance.";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const requestedHost =
    requestHeaders.get("x-forwarded-host") ??
    requestHeaders.get("host") ??
    "localhost:3000";
  const host = isAllowedHost(requestedHost)
    ? requestedHost
    : "asitra.app";
  const protocol =
    requestHeaders.get("x-forwarded-proto") ??
    (host.startsWith("localhost") ? "http" : "https");
  const origin = `${protocol}://${host}`;

  return {
    title,
    description,
    icons: {
      icon: "/favicon.png",
      shortcut: "/favicon.png",
    },
    openGraph: {
      title,
      description,
      type: "website",
      images: [{ url: `${origin}/og.png`, width: 1731, height: 909, alt: title }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [`${origin}/og.png`],
    },
    other: {
      "asitra-release": ASITRA_RELEASE,
    },
  };
}

function isAllowedHost(host: string): boolean {
  return (
    /^localhost(?::\d+)?$/i.test(host) ||
    /^(?:www\.)?asitra\.app$/i.test(host) ||
    /^devganatra\.github\.io$/i.test(host) ||
    /^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.chatgpt\.site$/i.test(host)
  );
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
