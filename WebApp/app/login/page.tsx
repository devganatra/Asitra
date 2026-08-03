import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { authProviderAvailability, betterAuthSession } from "../auth/server";
import { getChatGPTUser } from "../chatgpt-auth";
import LoginPage from "./LoginPage";

export const dynamic = "force-dynamic";

export default async function Login() {
  const existingChatGPTUser = await getChatGPTUser();
  if (existingChatGPTUser) redirect("/");

  const request = new Request("https://asitra.local", { headers: await headers() });
  if (await betterAuthSession(request)) redirect("/");
  const providers = authProviderAvailability();
  return <LoginPage google={providers.google} apple={providers.apple} />;
}
