"use client";

import { useState } from "react";
import { authClient } from "../auth/client";

type Provider = "google" | "apple";

export default function LoginPage({ google, apple }: { google: boolean; apple: boolean }) {
  const [pending, setPending] = useState<Provider | null>(null);
  const [error, setError] = useState("");

  async function signIn(provider: Provider) {
    setPending(provider);
    setError("");
    const result = await authClient.signIn.social({ provider, callbackURL: "/" });
    if (result.error) {
      setError(result.error.message ?? "Sign-in could not be started.");
      setPending(null);
    }
  }

  return (
    <main className="login-shell">
      <section className="login-card" aria-labelledby="login-title">
        <div className="login-mark" aria-hidden="true">A</div>
        <p className="login-eyebrow">Your everyday assistant</p>
        <h1 id="login-title">Welcome to Asitra</h1>
        <p className="login-copy">Your timeline, health, money, lists and reflections—private to your account and available across your devices.</p>
        <div className="login-actions">
          {apple && <button className="login-provider login-provider-apple" disabled={pending !== null} onClick={() => signIn("apple")}>Continue with Apple</button>}
          {google && <button className="login-provider" disabled={pending !== null} onClick={() => signIn("google")}>Continue with Google</button>}
          {!apple && !google && <p className="login-notice">Public sign-in is being configured. Please try again shortly.</p>}
        </div>
        {error && <p className="login-error" role="alert">{error}</p>}
        <p className="login-legal">By continuing, you agree to essential account storage and acknowledge the <a href="/privacy">Privacy Policy</a>. AI analysis remains opt-in.</p>
      </section>
    </main>
  );
}
