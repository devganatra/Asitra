import { env } from "cloudflare:workers";
import { betterAuth } from "better-auth";
import { SignJWT, importPKCS8 } from "jose";

type AuthEnvironment = {
  DB?: D1Database;
  BETTER_AUTH_SECRET?: string;
  ASITRA_PUBLIC_URL?: string;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
  APPLE_WEB_CLIENT_ID?: string;
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY_P8?: string;
  APPLE_SIGN_IN_AUDIENCE?: string;
};

export type AuthProviderAvailability = {
  configured: boolean;
  google: boolean;
  apple: boolean;
};

function authEnvironment(): AuthEnvironment {
  return env as unknown as AuthEnvironment;
}

export function authProviderAvailability(): AuthProviderAvailability {
  const runtime = authEnvironment();
  const google = Boolean(runtime.GOOGLE_CLIENT_ID && runtime.GOOGLE_CLIENT_SECRET);
  const apple = Boolean(
    runtime.APPLE_WEB_CLIENT_ID &&
      runtime.APPLE_TEAM_ID &&
      runtime.APPLE_KEY_ID &&
      runtime.APPLE_PRIVATE_KEY_P8,
  );
  return {
    configured: Boolean(runtime.DB && runtime.BETTER_AUTH_SECRET && (google || apple)),
    google,
    apple,
  };
}

async function appleClientSecret(runtime: AuthEnvironment): Promise<string> {
  const privateKey = (runtime.APPLE_PRIVATE_KEY_P8 ?? "").replace(/\\n/g, "\n");
  const key = await importPKCS8(privateKey, "ES256");
  const now = Math.floor(Date.now() / 1_000);
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: runtime.APPLE_KEY_ID })
    .setIssuer(runtime.APPLE_TEAM_ID!)
    .setSubject(runtime.APPLE_WEB_CLIENT_ID!)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt(now)
    .setExpirationTime(now + 60 * 60 * 24 * 30)
    .sign(key);
}

let cachedAuth: Promise<Awaited<ReturnType<typeof buildAuth>>> | undefined;

export function createAuth() {
  cachedAuth ??= buildAuth();
  return cachedAuth;
}

async function buildAuth() {
  const runtime = authEnvironment();
  const availability = authProviderAvailability();
  if (!availability.configured || !runtime.DB || !runtime.BETTER_AUTH_SECRET) return null;

  const socialProviders: Record<string, { clientId: string; clientSecret: string; appBundleIdentifier?: string }> = {};
  if (availability.google) {
    socialProviders.google = {
      clientId: runtime.GOOGLE_CLIENT_ID!,
      clientSecret: runtime.GOOGLE_CLIENT_SECRET!,
    };
  }
  if (availability.apple) {
    socialProviders.apple = {
      clientId: runtime.APPLE_WEB_CLIENT_ID!,
      clientSecret: await appleClientSecret(runtime),
      appBundleIdentifier: runtime.APPLE_SIGN_IN_AUDIENCE,
    };
  }

  const baseURL = runtime.ASITRA_PUBLIC_URL?.replace(/\/$/, "");
  return betterAuth({
    appName: "Asitra",
    database: runtime.DB,
    secret: runtime.BETTER_AUTH_SECRET,
    baseURL,
    basePath: "/api/auth",
    socialProviders,
    trustedOrigins: [baseURL, "https://appleid.apple.com"].filter((value): value is string => Boolean(value)),
    account: {
      encryptOAuthTokens: true,
      accountLinking: {
        enabled: true,
        trustedProviders: ["google", "apple"],
      },
    },
    user: {
      deleteUser: { enabled: true },
    },
    session: {
      expiresIn: 60 * 60 * 24 * 30,
      updateAge: 60 * 60 * 24,
      cookieCache: { enabled: false },
    },
    rateLimit: {
      enabled: true,
      storage: "database",
      window: 60,
      max: 30,
      customRules: {
        "/sign-in/social": { window: 60, max: 10 },
        "/callback/*": { window: 60, max: 15 },
      },
    },
    advanced: {
      cookiePrefix: "asitra",
      useSecureCookies: baseURL?.startsWith("https://") ?? true,
      defaultCookieAttributes: {
        httpOnly: true,
        secure: baseURL?.startsWith("https://") ?? true,
        sameSite: "lax",
        path: "/",
      },
    },
  });
}

export async function betterAuthSession(request: Request) {
  try {
    const auth = await createAuth();
    if (!auth) return null;
    return await auth.api.getSession({ headers: request.headers });
  } catch {
    return null;
  }
}
