import { chatGPTSignOutPath, requireChatGPTUser } from "./chatgpt-auth";
import AsitraWebApp from "./AsitraWebApp";

export const dynamic = "force-dynamic";

export default async function Page() {
  const user = await requireChatGPTUser("/");
  return <AsitraWebApp userName={user.displayName} logoutPath={chatGPTSignOutPath("/")} />;
}
