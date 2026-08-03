import Link from "next/link";

export const dynamic = "force-static";

const policyDate = "3 August 2026";

export default function PrivacyPage() {
  return (
    <main className="privacy-shell">
      <article className="privacy-card">
        <Link className="privacy-back" href="/">← Back to Asitra</Link>
        <p className="login-eyebrow">Privacy policy</p>
        <h1>Your life data stays under your control.</h1>
        <p className="privacy-lead">This policy explains what Asitra processes, why it is needed, and the choices available to you. Effective {policyDate}.</p>

        <h2>Who is responsible</h2>
        <p>Asitra is the data controller for the web service. Privacy enquiries and rights requests can be sent to <a href="mailto:ganatra.dev@gmail.com">ganatra.dev@gmail.com</a>.</p>

        <h2>Information we process</h2>
        <p>Account identity comes from Google or Apple: an account identifier, name, email address, verification state and optional profile picture. Asitra stores the records you choose to add, including timeline and journal entries, lists, trackers, financial organization data, settings, consent history, shared-list membership, pictures, PDFs and voice notes. Security records can include session identifiers, timestamps, IP address, browser information and rate-limit counters.</p>

        <h2>Purposes and legal bases</h2>
        <ul>
          <li><strong>Provide the service:</strong> account access, synchronization, private storage, sharing, export and recovery are necessary to perform the service you request.</li>
          <li><strong>Protect the service:</strong> session security, fraud prevention, audit information and abuse controls are used for legitimate security interests.</li>
          <li><strong>AI analysis:</strong> recent relevant records are sent only after explicit opt-in consent. You can withdraw consent at any time without losing non-AI features.</li>
          <li><strong>Legal obligations:</strong> limited information may be retained when required by applicable law.</li>
        </ul>

        <h2>Storage and service providers</h2>
        <p>Structured records are held in Cloudflare D1 and uploaded files in private Cloudflare R2 storage. Cloudflare also delivers the application and applies network protections. When AI is enabled, the question and a limited, relevant selection of account records are sent from Asitra’s server to OpenAI. The OpenAI API key is never sent to your browser. Asitra requests no-store model processing. Google and Apple process sign-in under their own privacy terms.</p>

        <h2>Retention, recovery and deletion</h2>
        <p>Current account data remains while your account is active. Asitra keeps up to 20 automatic state recovery points. Expired sessions, verification records and rate-limit counters are operational records and are periodically eligible for cleanup. Choosing Delete my data removes your private structured records, recovery copies, provider sessions and uploaded objects; shared content owned by another person is removed from your membership. A short-lived infrastructure backup can persist until its normal rotation completes.</p>

        <h2>Your controls and rights</h2>
        <p>Settings lets you download a machine-readable copy, withdraw AI consent, sign out and delete your data. Depending on your location, you may also request access, correction, erasure, restriction, portability, objection or withdrawal of consent, and complain to your local data-protection authority. Contact us if an in-app control does not cover your request.</p>

        <h2>Cookies, transfers and children</h2>
        <p>Asitra uses secure, HTTP-only cookies only for authentication and essential protection; advertising cookies are not used. Some providers may process information outside the European Economic Area using their applicable transfer safeguards. Asitra is not intended for children under 16 without authorization from a parent or guardian.</p>

        <h2>Changes</h2>
        <p>Material policy changes will be shown in the application with a new policy version. A new consent will be requested when a consent-based purpose changes materially.</p>
      </article>
    </main>
  );
}
