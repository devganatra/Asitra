import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { betterAuthSession } from "./auth/server";
import { chatGPTSignOutPath, getChatGPTUser } from "./chatgpt-auth";
import AsitraWebApp from "./AsitraWebApp";

export const dynamic = "force-dynamic";

export default async function Page() {
  const requestHeaders = await headers();
  const host = requestHeaders.get("host") ?? "";
  const isLocalDesignPreview = process.env.NODE_ENV !== "production" && /^(localhost|127\.0\.0\.1)(:\d+)?$/.test(host);
  if (isLocalDesignPreview) {
    return <AsitraWebApp userName="Dev" logoutPath="/login" designPreview />;
  }
  const request = new Request("https://asitra.local", { headers: requestHeaders });
  const session = await betterAuthSession(request);
  if (session?.user) {
    return <AsitraWebApp userName={session.user.name || session.user.email} logoutPath="/api/auth/sign-out" />;
  }

  const legacyUser = await getChatGPTUser();
  if (legacyUser) {
    return <AsitraWebApp userName={legacyUser.displayName} logoutPath={chatGPTSignOutPath("/")} />;
  }
  redirect("/login");
}
