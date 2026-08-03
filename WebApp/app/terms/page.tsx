import Link from "next/link";

export const dynamic = "force-static";

const termsDate = "3 August 2026";

export default function TermsPage() {
  return (
    <main className="privacy-shell">
      <article className="privacy-card">
        <Link className="privacy-back" href="/login">← Back to Asitra</Link>
        <p className="login-eyebrow">Terms of service</p>
        <h1>Clear terms for using Asitra.</h1>
        <p className="privacy-lead">These terms apply when you access or use Asitra. Effective {termsDate}.</p>

        <h2>The service</h2>
        <p>Asitra helps you organize personal information such as timelines, lists, wellbeing records, journals and financial planning views. Features may change as the service develops. Asitra is not a medical provider, financial adviser, emergency service or substitute for professional advice.</p>

        <h2>Your account and responsibilities</h2>
        <p>You must provide accurate account information through a supported sign-in provider and keep access to that provider secure. You are responsible for the information you add and for checking reminders, calendar items, classifications and AI-generated suggestions before relying on them.</p>

        <h2>Acceptable use</h2>
        <p>Do not use Asitra to break the law, harm another person, interfere with the service, bypass security or usage controls, upload malicious content, or access another account without permission. Automated or abusive use may be limited to protect users and infrastructure.</p>

        <h2>Your content and privacy</h2>
        <p>You retain ownership of content you add. You permit Asitra to process it only as needed to provide, secure and improve the features you request. The <Link href="/privacy">Privacy Policy</Link> explains the data lifecycle, providers and controls in detail.</p>

        <h2>AI and third-party services</h2>
        <p>AI features are optional and can make mistakes. Google, Apple, Cloudflare and OpenAI provide parts of the service under their own applicable terms. Availability can be affected by those providers, network conditions or account configuration.</p>

        <h2>Availability and liability</h2>
        <p>Asitra is provided on a reasonable-efforts basis without a guarantee of uninterrupted operation. To the extent permitted by law, Asitra is not liable for indirect or consequential loss. Nothing in these terms limits rights or liabilities that cannot legally be limited.</p>

        <h2>Ending use and changes</h2>
        <p>You may download your data, sign out or delete your account data from Settings. Access may be suspended for serious abuse or security risk. Material changes to these terms will be published with a revised effective date.</p>

        <h2>Contact</h2>
        <p>Questions about these terms can be sent to <a href="mailto:ganatra.dev@gmail.com">ganatra.dev@gmail.com</a>.</p>
      </article>
    </main>
  );
}
