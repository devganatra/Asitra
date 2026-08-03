import Link from "next/link";

export const dynamic = "force-static";

export default function AboutPage() {
  return (
    <main className="privacy-shell">
      <article className="privacy-card">
        <Link className="privacy-back" href="/login">← Sign in to Asitra</Link>
        <p className="login-eyebrow">About Asitra</p>
        <h1>Your everyday assistant, built around your life.</h1>
        <p className="privacy-lead">Asitra provides one private place to capture your day and turn it into useful timelines, lists, trackers, financial views and reflections.</p>

        <h2>What Asitra does</h2>
        <ul>
          <li>Capture notes, plans, expenses, habits and personal progress through one simple entry point.</li>
          <li>Organize those entries into useful views without making you enter the same information repeatedly.</li>
          <li>Keep each account isolated, with download, recovery and deletion controls.</li>
          <li>Offer optional AI assistance only after the account holder explicitly enables it.</li>
        </ul>

        <h2>Who operates the service</h2>
        <p>Asitra is an independent application operated by dev ganatra. Support, privacy and security enquiries can be sent to <a href="mailto:ganatra.dev@gmail.com">ganatra.dev@gmail.com</a>.</p>

        <h2>Trust and transparency</h2>
        <p>Asitra uses Google or Apple for account authentication and does not collect your provider password. Essential sessions use secure, HTTP-only cookies. Read the <Link href="/privacy">Privacy Policy</Link> and <Link href="/terms">Terms of Service</Link> before using the service.</p>
      </article>
    </main>
  );
}
