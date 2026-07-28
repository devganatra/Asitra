import { requireChatGPTUser } from "./chatgpt-auth";
import SakhyaWebApp from "./SakhyaWebApp";

export const dynamic = "force-dynamic";

export default async function Page() {
  await requireChatGPTUser("/");
  return <SakhyaWebApp />;
}
