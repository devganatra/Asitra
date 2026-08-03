import { requireChatGPTUser } from "./chatgpt-auth";
import SakhyaWebApp from "./SakhyaWebApp";

export const dynamic = "force-dynamic";

export default async function Page() {
  const user = await requireChatGPTUser("/");
  return <SakhyaWebApp userName={user.displayName} />;
}
