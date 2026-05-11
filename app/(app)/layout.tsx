import { auth, signOut } from "@/lib/auth";
import { redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell";
import { Toaster } from "@/components/ui/sonner";

export default async function AuthedLayout({ children }: { children: React.ReactNode }) {
  const session = await auth();
  if (!session?.user?.email) redirect("/login");

  async function signOutAction() {
    "use server";
    await signOut({ redirectTo: "/login" });
  }

  return (
    <>
      <AppShell email={session.user.email} signOutAction={signOutAction}>
        {children}
      </AppShell>
      <Toaster />
    </>
  );
}
